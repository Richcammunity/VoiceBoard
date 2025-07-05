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
    private var audioFormat: AVAudioFormat?
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
    private let preferredSampleRate: Double = 16000.0
    private let bufferSize: UInt32 = 1024
    private let maxBufferDuration: TimeInterval = 30.0 // Maximum buffer duration in seconds
    
    // Audio format converter for handling different input formats
    private var audioConverter: AVAudioConverter?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadParakeetModel()
        // Don't setup audio buffer here - it will be setup when we know the actual input format
    }
    
    private func setupAudioBuffer() {
        // This method is now replaced by setupAudioBuffer(with:) to handle dynamic formats
        // Keep this for backwards compatibility but it won't be used
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate maximum frame capacity based on sample rate and duration
            let maxFrameCapacity = AVAudioFrameCount(self.preferredSampleRate * self.maxBufferDuration)
            
            // Create audio buffer with proper format
            guard let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                                sampleRate: self.preferredSampleRate, 
                                                channels: 1, 
                                                interleaved: false) else {
                print("Failed to create audio format")
                return
            }
            
            self.audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: maxFrameCapacity)
            self.audioBuffer?.frameLength = 0
        }
    }
    
    private func setupAudioBuffer(with inputFormat: AVAudioFormat) {
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Store the actual input format
            self.audioFormat = inputFormat
            
            // Log input format details for debugging
            self.logAudioFormat("Input", format: inputFormat)
            
            // Create preferred output format for WhisperKit (16kHz, 1 channel, Float32)
            guard let preferredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                                     sampleRate: self.preferredSampleRate, 
                                                     channels: 1, 
                                                     interleaved: false) else {
                print("Failed to create preferred audio format")
                return
            }
            
            // Log preferred format details for debugging
            self.logAudioFormat("Preferred", format: preferredFormat)
            
            // Calculate maximum frame capacity based on preferred sample rate and duration
            let maxFrameCapacity = AVAudioFrameCount(self.preferredSampleRate * self.maxBufferDuration)
            
            // Create audio buffer with preferred format
            self.audioBuffer = AVAudioPCMBuffer(pcmFormat: preferredFormat, frameCapacity: maxFrameCapacity)
            self.audioBuffer?.frameLength = 0
            
            // Setup converter if formats don't match
            if !inputFormat.isEqual(preferredFormat) {
                print("Format conversion required")
                self.audioConverter = AVAudioConverter(from: inputFormat, to: preferredFormat)
                if self.audioConverter == nil {
                    print("Failed to create audio converter")
                }
            } else {
                print("No format conversion needed")
                self.audioConverter = nil
            }
        }
    }
    
    private func logAudioFormat(_ label: String, format: AVAudioFormat) {
        print("\(label) Audio Format:")
        print("  Sample Rate: \(format.sampleRate) Hz")
        print("  Channels: \(format.channelCount)")
        print("  Common Format: \(format.commonFormat.rawValue)")
        print("  Interleaved: \(format.isInterleaved)")
        if let channelLayout = format.channelLayout {
            print("  Channel Layout: \(channelLayout)")
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
        
        // Setup audio buffer with actual input format
        setupAudioBuffer(with: inputFormat)

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
        
        // Check if audio buffer is properly initialized
        guard audioBuffer != nil else {
            print("Audio buffer not yet initialized, skipping frame")
            return
        }
        
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Double-check buffer is still valid after async dispatch
            guard self.audioBuffer != nil else {
                print("Audio buffer was deallocated during async dispatch")
                return
            }
            
            // Thread-safe buffer accumulation
            self.accumulateAudioBuffer(buffer, floatChannelData: floatChannelData)
            
            // Check if we have enough data for transcription
            if self.shouldProcessBuffer() {
                self.processAudioBuffer()
            }
        }
    }
    
    private func accumulateAudioBuffer(_ buffer: AVAudioPCMBuffer, floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>) {
        guard let audioBuffer = self.audioBuffer else {
            print("Audio buffer not initialized")
            return
        }
        
        // Handle format conversion if needed
        let processedBuffer: AVAudioPCMBuffer
        if let converter = self.audioConverter {
            // Convert the input buffer to the preferred format
            guard let convertedBuffer = convertAudioBuffer(buffer, using: converter) else {
                print("Failed to convert audio buffer")
                return
            }
            processedBuffer = convertedBuffer
        } else {
            // No conversion needed, use the buffer directly
            processedBuffer = buffer
        }
        
        // Get the processed buffer's data
        guard let processedChannelData = processedBuffer.floatChannelData,
              let audioBufferChannelData = audioBuffer.floatChannelData else {
            print("Failed to get audio buffer channel data")
            return
        }
        
        let incomingFrames = processedBuffer.frameLength
        let currentFrames = audioBuffer.frameLength
        let maxFrames = audioBuffer.frameCapacity
        
        // Ensure we don't exceed buffer capacity
        let framesToCopy = min(incomingFrames, maxFrames - currentFrames)
        
        if framesToCopy > 0 {
            // Safe memory copy operation with proper format handling
            let sourcePointer = processedChannelData[0]
            let destinationPointer = audioBufferChannelData[0].advanced(by: Int(currentFrames))
            
            // Use safe memory copy
            destinationPointer.assign(from: sourcePointer, count: Int(framesToCopy))
            
            // Update frame length atomically
            audioBuffer.frameLength = currentFrames + framesToCopy
        }
        
        // Send original buffer to streaming task (WhisperKit handles its own format conversion)
        if let streamingTask = self.streamingTask {
            streamingTask.appendAudio(buffer)
        }
    }
    
    private func convertAudioBuffer(_ inputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        // Calculate the output buffer size based on the converter's output format
        let outputFormat = converter.outputFormat
        let sampleRateRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * sampleRateRatio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            print("Failed to create output buffer for conversion")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        
        if status == .error {
            print("Audio conversion failed: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return outputBuffer
    }
    
    private func shouldProcessBuffer() -> Bool {
        guard let audioBuffer = self.audioBuffer else { return false }
        
        // Use the actual sample rate from the audio buffer's format
        let actualSampleRate = audioBuffer.format.sampleRate
        
        // Process buffer when we have enough data (e.g., 1 second of audio)
        let targetFrameCount = AVAudioFrameCount(actualSampleRate * 1.0) // 1 second
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
        
        // Reset audio buffer and converter
        audioBufferQueue.async { [weak self] in
            self?.audioBuffer?.frameLength = 0
            self?.audioBuffer = nil
            self?.audioConverter = nil
            self?.audioFormat = nil
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
