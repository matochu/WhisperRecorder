# WhisperRecorder

A menu bar app for macOS that records audio and transcribes it using the Whisper model.

## Features

- Record audio with a keyboard shortcut (default: Command+Shift+R)
- Transcribe audio using the whisper.cpp library
- Copy transcription to clipboard
- Menu bar status indicator
- Notification when transcription is complete
- On-demand model download - select the model that works best for you

## Building

1. Clone this repository
2. Make sure you have Swift and Xcode installed
3. Run `./build.sh` to build the app
4. Run `./run_whisper.sh` to start the app

## Whisper Models

WhisperRecorder now allows users to select and download their preferred Whisper model at runtime:

- **Tiny models** (~75MB): Fast but less accurate. Good for simple transcriptions.
- **Base models** (~142MB): Good balance between speed and accuracy for everyday use.
- **Small models** (~466MB): More accurate but slower than base models.
- **Medium models** (~1.5GB): High accuracy but requires more memory and processing power.
- **Large models** (~3GB): Best accuracy but slowest and requires significant resources.

English-specific models (with `.en` suffix) are optimized for English language and typically perform better for English content.

On first launch, you'll be prompted to select and download a model. You can change models at any time through the menu bar interface.

## Auto-Update Feature

WhisperRecorder now includes an auto-update feature that checks for updates when the app starts and allows you to easily install new versions.

### How it works:

1. When the app starts, it automatically checks for updates from a remote server.
2. If an update is available, you'll see a notification in the app's menu.
3. You can click "Download & Install Update" to download and install the new version.
4. You can also manually check for updates by clicking the "Check for Updates" button.

### For developers (maintaining updates):

The app looks for an `updates.txt` file hosted on Google Drive with the following format:

```
https://drive.google.com/file/d/FILEID/view?usp=sharing WhisperRecorder-Universal.zip VERSION_NUMBER
```

Where:

- The first part is a link to the zip file containing the new app version
- The second part is the filename of the zip file
- The third part is the version number (e.g., "1.1")

When releasing a new version:

1. Package the app using `./package_app.sh`
2. Upload the resulting zip file to Google Drive
3. Update the `updates.txt` file with the new download link and version number
4. Make the file publicly accessible via a sharing link

## Packaging and Distribution

### Creating a Distributable App

To create a standalone app bundle that can be distributed to other users:

1. Run `./package_app.sh` to build the app bundle
2. The script will create `WhisperRecorder.app` with all necessary resources and libraries

### Creating a Distributable Zip File

To create a zip file for distribution:

```sh
zip -r WhisperRecorder.zip WhisperRecorder.app
```

This will create a zip file that includes:

- The application executable
- Required libraries (libwhisper.dylib, libggml libraries)
- No model files - users will download their preferred model on first run

### Installation on Other Machines

1. Download and unzip WhisperRecorder.zip
2. Move WhisperRecorder.app to the Applications folder
3. Right-click on the app and select "Open" to bypass macOS security (first run only)
4. Grant microphone permissions when prompted
5. Select and download your preferred Whisper model when prompted

## Troubleshooting

If the app doesn't start, check the logs:

- `~/Library/Logs/WhisperRecorder.log` - Contains launcher and environment information
- `~/Library/Application Support/WhisperRecorder/whisperrecorder_debug.log` - Contains detailed application logs

Common issues:

- Missing microphone permissions: Go to System Preferences > Security & Privacy > Microphone
- Missing notification permissions: Go to System Preferences > Notifications

## Credits

This app uses the following open-source libraries:

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C/C++ port of OpenAI's Whisper model
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Swift library for global keyboard shortcuts
