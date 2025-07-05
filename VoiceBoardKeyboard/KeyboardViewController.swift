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

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadParakeetModel()
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            streamingTask.appendAudio(buffer)
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

    private func stopLiveDictation() {
        streamingTask?.finish()
        streamingTask = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

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
