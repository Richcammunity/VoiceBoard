//
//  KeyboardViewController.swift
//  VoiceBoardKeyboard
//
//  Created by Admin on 7/5/25.
//

import UIKit
import WhisperKit
import AVFoundation

class KeyboardViewController: UIInputViewController {

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var streamingTask: WhisperKit.StreamingTask?

    private let dictateButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)
    
    // Audio buffer management with thread safety
    private var audioBuffer: AVAudioPCMBuffer?
    private let audioBufferQueue = DispatchQueue(label: "audio.buffer.queue", qos: .userInitiated)
    private let transcriptionQueue = DispatchQueue(label: "transcription.queue", qos: .userInitiated)
    
    // Thread-safe transcription state
    private var _isTranscribing: Bool = false
    private let isTranscribingLock = NSLock()
    
    private var isTranscribing: Bool {
        get {
            isTranscribingLock.lock()
            defer { isTranscribingLock.unlock() }
            return _isTranscribing
        }
        set {
            isTranscribingLock.lock()
            defer { isTranscribingLock.unlock() }
            _isTranscribing = newValue
        }
    }
    
    // Audio processing constants
    private let sampleRate: Double = 16000.0
    private let bufferSize: UInt32 = 1024
    private let maxBufferDuration: TimeInterval = 30.0 // Maximum buffer duration in seconds

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadParakeetModel()
        setupAudioBuffer()
    }
    
    private func setupAudioBuffer() {
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate maximum frame capacity based on sample rate and duration
            let maxFrameCapacity = AVAudioFrameCount(self.sampleRate * self.maxBufferDuration)
            
            // Create audio buffer with proper format
            guard let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                                sampleRate: self.sampleRate, 
                                                channels: 1, 
                                                interleaved: false) else {
                print("Failed to create audio format")
                return
            }
            
            self.audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: maxFrameCapacity)
            self.audioBuffer?.frameLength = 0
        }
    }

    private func loadParakeetModel() {
        Task {
            // This now points to the correct, downloaded Whisper model folder
            guard let modelURL = Bundle.main.url(forResource: "openai_whisper-distil-large-v3", withExtension: nil) else {
                await MainActor.run {
                    self.statusLabel.text = "Error: Model folder not found in app bundle."
                }
                return
            }
            do {
                let loaded = try await WhisperKit(modelPath: modelURL.path)
                await MainActor.run {
                    self.whisperKit = loaded
                    self.statusLabel.text = "Ready"
                    self.dictateButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.text = "Error loading model"
                }
            }
        }
    }

    private func setupUI() {
        dictateButton.setTitle("🎤", for: .normal)
        dictateButton.titleLabel?.font = .systemFont(ofSize: 28)
        dictateButton.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)
        dictateButton.isEnabled = false
        dictateButton.layer.cornerRadius = 10
        dictateButton.clipsToBounds = true

        statusLabel.text = "Loading Model..."
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14)

        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 28)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let topRow = UIStackView(arrangedSubviews: [statusLabel])
        topRow.distribution = .fillEqually

        let bottomRow = UIStackView(arrangedSubviews: [nextKeyboardButton, dictateButton])
        bottomRow.distribution = .fillEqually
        
        let mainStack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        mainStack.axis = .vertical
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    @objc private func dictateTapped() {
        guard whisperKit != nil else {
            statusLabel.text = "Model not ready."
            return
        }
        if streamingTask == nil {
            startLiveDictation()
        } else {
            stopLiveDictation()
        }
    }

    private func startLiveDictation() {
        guard let whisperKit = whisperKit else { return }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let streamingTask = whisperKit.startStreamingRecognition { [weak self] results in
            guard let self = self else { return }
            if let text = results.compactMap({ $0.text }).joined(separator: " ").nilIfEmpty {
                Task { @MainActor in
                    self.textDocumentProxy.insertText(text)
                }
            }
        }
        self.streamingTask = streamingTask

        // Install tap with thread-safe audio buffer management
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            statusLabel.text = "Listening..."
            dictateButton.layer.removeAllAnimations()
            dictateButton.setTitle("🛑", for: .normal)
            UIView.animate(withDuration: 0.8, delay: 0, options: [.repeat, .autoreverse, .allowUserInteraction], animations: {
                self.dictateButton.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                self.dictateButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }, completion: nil)
        } catch {
            statusLabel.text = "Audio Engine start failed."
            stopLiveDictation()
        }
    }
    
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Ensure we have valid audio data before processing
        guard let floatChannelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            print("Invalid audio buffer: missing float channel data or zero frame length")
            return
        }
        
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Thread-safe buffer accumulation
            self.accumulateAudioBuffer(buffer, floatChannelData: floatChannelData)
            
            // Check if we have enough data for transcription
            if self.shouldProcessBuffer() {
                self.processAudioBuffer()
            }
        }
    }
    
    private func accumulateAudioBuffer(_ buffer: AVAudioPCMBuffer, floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>) {
        guard let audioBuffer = self.audioBuffer,
              let audioBufferChannelData = audioBuffer.floatChannelData else {
            print("Audio buffer not initialized")
            return
        }
        
        let incomingFrames = buffer.frameLength
        let currentFrames = audioBuffer.frameLength
        let maxFrames = audioBuffer.frameCapacity
        
        // Ensure we don't exceed buffer capacity
        let framesToCopy = min(incomingFrames, maxFrames - currentFrames)
        
        if framesToCopy > 0 {
            // Safe memory copy operation
            let sourcePointer = floatChannelData[0]
            let destinationPointer = audioBufferChannelData[0].advanced(by: Int(currentFrames))
            
            // Use safe memory copy instead of memcpy
            destinationPointer.assign(from: sourcePointer, count: Int(framesToCopy))
            
            // Update frame length atomically
            audioBuffer.frameLength = currentFrames + framesToCopy
        }
        
        // Send real-time audio to streaming task
        if let streamingTask = self.streamingTask {
            streamingTask.appendAudio(buffer)
        }
    }
    
    private func shouldProcessBuffer() -> Bool {
        guard let audioBuffer = self.audioBuffer else { return false }
        
        // Process buffer when we have enough data (e.g., 1 second of audio)
        let targetFrameCount = AVAudioFrameCount(sampleRate * 1.0) // 1 second
        return audioBuffer.frameLength >= targetFrameCount
    }
    
    private func processAudioBuffer() {
        // Check if already transcribing to prevent multiple concurrent transcriptions
        guard !isTranscribing else {
            return
        }
        
        // Create a copy of the current buffer for processing
        guard let audioBuffer = self.audioBuffer,
              audioBuffer.frameLength > 0,
              let bufferCopy = createBufferCopy(from: audioBuffer) else {
            return
        }
        
        // Mark as transcribing before dispatching the task
        isTranscribing = true
        
        // Process the copy on a background queue
        transcriptionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Process the buffer copy (this is where you would do additional processing)
            // For now, we'll just simulate processing
            self.simulateAudioProcessing(bufferCopy)
            
            // Reset transcription state
            self.isTranscribing = false
            
            // Reset buffer after processing the copy
            self.audioBufferQueue.async {
                self.audioBuffer?.frameLength = 0
            }
        }
    }
    
    private func createBufferCopy(from originalBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: originalBuffer.format, frameCapacity: originalBuffer.frameLength),
              let originalData = originalBuffer.floatChannelData,
              let copyData = copy.floatChannelData else {
            return nil
        }
        
        // Safe copy operation
        let frameCount = Int(originalBuffer.frameLength)
        copyData[0].assign(from: originalData[0], count: frameCount)
        copy.frameLength = originalBuffer.frameLength
        
        return copy
    }
    
    private func simulateAudioProcessing(_ buffer: AVAudioPCMBuffer) {
        // Simulate processing time
        Thread.sleep(forTimeInterval: 0.1)
        
        // Here you would implement your custom audio processing logic
        // For now, we'll just log that processing occurred
        print("Processed audio buffer with \(buffer.frameLength) frames")
    }

    private func stopLiveDictation() {
        streamingTask?.finish()
        streamingTask = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Reset transcription state
        isTranscribing = false
        
        // Reset audio buffer
        audioBufferQueue.async { [weak self] in
            self?.audioBuffer?.frameLength = 0
        }

        Task {
            try? AVAudioSession.sharedInstance().setActive(false)
        }

        UIView.animate(withDuration: 0.2) {
            self.dictateButton.backgroundColor = .clear
            self.dictateButton.transform = .identity
            self.dictateButton.setTitle("🎤", for: .normal)
        }
        statusLabel.text = "Ready"
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self else { return nil }
        return self.isEmpty ? nil : self
    }
}
