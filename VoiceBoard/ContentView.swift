//
//  ContentView.swift
//  VoiceBoard
//
//  Created by Admin on 7/5/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("How to Enable VoiceBoard")) {
                    InstructionStep(step: 1, text: "Open the Settings app")
                    InstructionStep(step: 2, text: "Go to General > Keyboard")
                    InstructionStep(step: 3, text: "Tap 'Keyboards' at the top")
                    InstructionStep(step: 4, text: "Tap 'Add New Keyboard...'")
                    InstructionStep(step: 5, text: "Select 'VoiceBoard' under Third-Party Keyboards")
                    InstructionStep(step: 6, text: "Tap 'VoiceBoard - VoiceBoard' and then enable 'Allow Full Access'")
                }
                
                Section(header: Text("Why Full Access?")) {
                    Text("VoiceBoard requires Full Access to access the microphone for dictation and to use the Whisper model for offline speech recognition. Your voice data is processed entirely on your iPhone and is never sent to any servers.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Using VoiceBoard")) {
                    InstructionStep(step: 1, text: "Open any app with a text field (Messages, Notes, etc.)")
                    InstructionStep(step: 2, text: "Tap in the text field to bring up the keyboard")
                    InstructionStep(step: 3, text: "Tap the globe icon (🌐) to switch to VoiceBoard")
                    InstructionStep(step: 4, text: "Tap the microphone button (🎤) to start dictating")
                    InstructionStep(step: 5, text: "Speak clearly, then tap 'Insert Text' to add your dictation")
                }
            }
            .navigationTitle("Welcome to VoiceBoard")
        }
    }
}

struct InstructionStep: View {
    let step: Int
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "\(step).circle.fill")
                .font(.headline)
                .foregroundColor(.accentColor)
            Text(text)
        }
    }
}

#Preview {
    ContentView()
}
