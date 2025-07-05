# VoiceBoard - Voice-to-Text Keyboard

A custom iOS keyboard that provides voice-to-text dictation using the Whisper model for accurate offline transcription.

## Features

- **Offline voice transcription** using the Whisper distil-large-v3 model
- **Real-time dictation** with live audio processing
- **Simple UI** with microphone button, text preview, and insert functionality
- **Privacy-focused** - all processing happens on device

## Setup Instructions

1. **Build and install** the app on your iOS device
2. **Enable the keyboard**:
   - Open **Settings** app
   - Go to **General** > **Keyboard**
   - Tap **Keyboards** at the top
   - Tap **Add New Keyboard...**
   - Select **VoiceBoard** under Third-Party Keyboards
   - Tap **VoiceBoard - VoiceBoard** and enable **Allow Full Access**

3. **Grant microphone permission** when prompted

## Usage

1. **Switch to VoiceBoard** by tapping the globe icon in any text field
2. **Tap the microphone button** to start dictation
3. **Speak clearly** - the transcribed text will appear in the preview area
4. **Tap "Insert Text"** to add the transcribed text to your document
5. **Tap the stop button** to end dictation

## Model Information

The keyboard uses the `distil-whisper_distil-large-v3` model for transcription:
- **Accurate** transcription in multiple languages
- **Fast** processing optimized for mobile devices
- **Offline** operation - no internet connection required

## Technical Details

- **Framework**: WhisperKit for iOS
- **Audio Processing**: Real-time audio capture and processing
- **UI**: Native UIKit with custom keyboard extension
- **Permissions**: Microphone access required for voice input

## Troubleshooting

- **Keyboard not appearing**: Make sure Full Access is enabled in Settings
- **No microphone access**: Check app permissions in Settings > Privacy & Security > Microphone
- **Model not loading**: Ensure the app has been launched at least once before using the keyboard
- **Poor transcription quality**: Speak clearly and avoid background noise

## Privacy

VoiceBoard processes all audio locally on your device. No voice data is transmitted to external servers.