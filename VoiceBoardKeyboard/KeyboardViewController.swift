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
    private var transcriptionTask: Task<Void, Never>?
    private var isTranscribing = false

    private let dictateButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)
    private let transcribedTextView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadParakeetModel()
    }

    private func loadParakeetModel() {
        Task {
            await MainActor.run {
                self.statusLabel.text = "Loading model..."
            }
            
            // Try multiple locations for the model
            var modelPath: String?
            
            // First try: Look for the model in the main bundle
            if let bundleURL = Bundle.main.url(forResource: "distil-whisper_distil-large-v3", withExtension: nil) {
                modelPath = bundleURL.path
            }
            // Second try: Look in the app group container (if configured)
            else if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.voiceboard") {
                let modelURL = containerURL.appendingPathComponent("distil-whisper_distil-large-v3")
                if FileManager.default.fileExists(atPath: modelURL.path) {
                    modelPath = modelURL.path
                }
            }
            // Third try: Use WhisperKit's default model download
            else {
                do {
                    // This will download the model if needed
                    let loaded = try await WhisperKit()
                    await MainActor.run {
                        self.whisperKit = loaded
                        self.statusLabel.text = "Ready to dictate"
                        self.dictateButton.isEnabled = true
                    }
                    return
                } catch {
                    await MainActor.run {
                        self.statusLabel.text = "Failed to download model: \(error.localizedDescription)"
                    }
                    return
                }
            }
            
            // Load the model from the found path
            if let modelPath = modelPath {
                do {
                    let loaded = try await WhisperKit(modelFolder: modelPath)
                    await MainActor.run {
                        self.whisperKit = loaded
                        self.statusLabel.text = "Ready to dictate"
                        self.dictateButton.isEnabled = true
                    }
                } catch {
                    await MainActor.run {
                        self.statusLabel.text = "Error: \(error.localizedDescription)"
                    }
                }
            } else {
                await MainActor.run {
                    self.statusLabel.text = "Model not found"
                }
            }
        }
    }

    private func setupUI() {
        // Configure keyboard view background
        view.backgroundColor = UIColor.systemBackground
        
        // Configure dictate button
        dictateButton.setTitle("🎤", for: .normal)
        dictateButton.titleLabel?.font = .systemFont(ofSize: 30)
        dictateButton.addTarget(self, action: #selector(dictateTapped), for: .touchUpInside)
        dictateButton.isEnabled = false
        dictateButton.layer.cornerRadius = 25
        dictateButton.backgroundColor = UIColor.systemGray5
        dictateButton.clipsToBounds = true
        dictateButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        dictateButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        // Configure status label
        statusLabel.text = "Loading Model..."
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel

        // Configure next keyboard button
        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 24)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        nextKeyboardButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Configure transcribed text view
        transcribedTextView.isEditable = false
        transcribedTextView.backgroundColor = UIColor.systemGray6
        transcribedTextView.layer.cornerRadius = 8
        transcribedTextView.font = .systemFont(ofSize: 16)
        transcribedTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        transcribedTextView.text = "Tap the microphone to start dictating..."
        transcribedTextView.textColor = .placeholderText

        // Create "Insert" button
        let insertButton = UIButton(type: .system)
        insertButton.setTitle("Insert Text", for: .normal)
        insertButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        insertButton.addTarget(self, action: #selector(insertTextTapped), for: .touchUpInside)
        insertButton.isEnabled = false
        insertButton.tag = 100 // Tag to identify the button later

        // Create button row
        let buttonRow = UIStackView(arrangedSubviews: [nextKeyboardButton, dictateButton, insertButton])
        buttonRow.distribution = .equalSpacing
        buttonRow.alignment = .center
        buttonRow.spacing = 20

        // Create main stack
        let mainStack = UIStackView(arrangedSubviews: [transcribedTextView, statusLabel, buttonRow])
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            transcribedTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    @objc private func dictateTapped() {
        guard whisperKit != nil else {
            statusLabel.text = "Model not ready."
            return
        }
        if !isTranscribing {
            startLiveDictation()
        } else {
            stopLiveDictation()
        }
    }
    
    @objc private func insertTextTapped() {
        guard let text = transcribedTextView.text, !text.isEmpty, 
              text != "Tap the microphone to start dictating..." else { return }
        
        textDocumentProxy.insertText(text)
        
        // Clear the text view after insertion
        transcribedTextView.text = ""
        transcribedTextView.textColor = .label
        
        // Disable insert button
        if let insertButton = view.viewWithTag(100) as? UIButton {
            insertButton.isEnabled = false
        }
    }

    private func startLiveDictation() {
        guard let whisperKit = whisperKit else { return }
        
        // Request microphone permission first
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.statusLabel.text = "Microphone access denied"
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.performLiveDictation()
            }
        }
    }
    
    private func performLiveDictation() {
        guard let whisperKit = whisperKit else { return }
        
        isTranscribing = true
        
        // Clear previous text
        transcribedTextView.text = ""
        transcribedTextView.textColor = .label
        
        // Update UI
        statusLabel.text = "Listening..."
        dictateButton.setTitle("⏹️", for: .normal)
        dictateButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.3)
        
        // Animate recording indicator
        UIView.animate(withDuration: 1.0, delay: 0, options: [.repeat, .autoreverse], animations: {
            self.dictateButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        })
        
        // Start transcription task
        transcriptionTask = Task {
            do {
                // Configure audio session
                try await AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement)
                try await AVAudioSession.sharedInstance().setActive(true)
                
                // Set up audio engine for recording
                let audioEngine = AVAudioEngine()
                self.audioEngine = audioEngine
                
                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                
                // Create audio buffer for accumulating audio
                var audioBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: AVAudioFrameCount(recordingFormat.sampleRate * 5))! // 5 seconds buffer
                audioBuffer.frameLength = 0
                
                // Install tap to capture audio
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                    guard let self = self, self.isTranscribing else { return }
                    
                    // Accumulate audio in buffer
                    let framesToCopy = min(buffer.frameLength, audioBuffer.frameCapacity - audioBuffer.frameLength)
                    if framesToCopy > 0 {
                        // Safely check for float channel data before processing
                        guard let audioBufferChannelData = audioBuffer.floatChannelData?[0],
                              let bufferChannelData = buffer.floatChannelData?[0] else {
                            print("Warning: Audio buffer channel data is nil or format is not float")
                            return
                        }
                        
                        memcpy(audioBufferChannelData.advanced(by: Int(audioBuffer.frameLength)), 
                               bufferChannelData, 
                               Int(framesToCopy) * MemoryLayout<Float>.size)
                        audioBuffer.frameLength += framesToCopy
                    }
                    
                    // Process when we have enough audio (every 3 seconds)
                    if audioBuffer.frameLength >= AVAudioFrameCount(recordingFormat.sampleRate * 3) {
                        Task {
                            await self.processAudioBuffer(audioBuffer, whisperKit: whisperKit)
                        }
                        audioBuffer.frameLength = 0 // Reset buffer
                    }
                }
                
                // Start the audio engine
                try audioEngine.start()
                
                // Keep the task alive while transcribing
                while isTranscribing && !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
                
            } catch {
                await MainActor.run {
                    self.statusLabel.text = "Error: \(error.localizedDescription)"
                    self.stopLiveDictation()
                }
            }
        }
    }
    
    private func processAudioBuffer(_ audioBuffer: AVAudioPCMBuffer, whisperKit: WhisperKit) async {
        do {
            // Convert audio buffer to the format expected by WhisperKit
            guard let channelData = audioBuffer.floatChannelData?[0] else {
                print("Warning: Audio buffer channel data is nil or format is not float")
                return
            }
            
            let audioArray = Array(UnsafeBufferPointer(start: channelData, count: Int(audioBuffer.frameLength)))
            
            // Transcribe the audio
            let result = try await whisperKit.transcribe(audioArray: audioArray)
            
            await MainActor.run {
                if let segments = result?.segments, !segments.isEmpty {
                    let text = segments.compactMap { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !text.isEmpty {
                        // Append new text to existing text
                        let existingText = self.transcribedTextView.text ?? ""
                        let newText = existingText.isEmpty ? text : existingText + " " + text
                        self.transcribedTextView.text = newText
                        
                        // Enable insert button when we have text
                        if let insertButton = self.view.viewWithTag(100) as? UIButton {
                            insertButton.isEnabled = true
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.statusLabel.text = "Transcription error: \(error.localizedDescription)"
            }
        }
    }

    private func stopLiveDictation() {
        isTranscribing = false
        
        // Cancel transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        // Stop audio engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Stop audio session
        Task {
            try? await AVAudioSession.sharedInstance().setActive(false)
        }
        
        // Reset UI
        UIView.animate(withDuration: 0.3) {
            self.dictateButton.layer.removeAllAnimations()
            self.dictateButton.backgroundColor = UIColor.systemGray5
            self.dictateButton.transform = .identity
            self.dictateButton.setTitle("🎤", for: .normal)
        }
        
        statusLabel.text = "Ready to dictate"
    }
}
