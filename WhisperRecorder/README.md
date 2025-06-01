# WhisperRecorder

A macOS menu bar app for voice recording and transcription using OpenAI's Whisper model with AI-powered text enhancement.

## Features

- 🎤 **Voice Recording**: Record audio with configurable hotkeys
- 🤖 **AI Transcription**: Local Whisper model processing
- 🌍 **Translation**: Automatic translation to multiple languages
- ✨ **Text Enhancement**: AI-powered text formatting and style improvements
- 📋 **Smart Clipboard**: Auto-copy and paste functionality
- 🔄 **Offline Support**: Works completely offline (except for AI enhancement)
- ⌨️ **Hotkey Support**: Customizable keyboard shortcuts

## Quick Start

### 🛡️ Safe Building & Running (New!)

We now have a unified, safe-by-default script that prevents process hangs:

```bash
cd WhisperRecorder

# Build the app (safe mode, no parallel jobs)
./whisper build

# Run the app (automatic process cleanup)
./whisper run

# Debug interactively (with terminal output)
./whisper debug

# Emergency cleanup (kill hanging processes)
./whisper cleanup

# See all options
./whisper help
```

### ⚠️ Legacy Scripts (Deprecated)

Old scripts are now in `scripts/` directory and should not be used directly:

```bash
# ❌ Old way (can cause hangs)
./package_manual.sh
./run.sh

# ✅ New way (safe by default)
./whisper build
./whisper run
```

### Setting Up Permissions

1. **Microphone**: Granted automatically when first recording
2. **Accessibility** (for auto-paste):
   - Launch app using `./whisper run`
   - Click menu bar icon → Configuration panel
   - Look for "Auto-Paste" status
   - If needed, click to request permissions
   - In System Preferences, you should see "WhisperRecorder" (not "Cursor" or "Terminal")

## Troubleshooting

### Process Hangs (UE State)

If you encounter hanging processes that can't be killed with `kill -9`:

```bash
# Emergency cleanup
./whisper cleanup

# Check status
./whisper status

# If cleanup doesn't work, restart your Mac
sudo reboot
```

**Causes**: Audio engine hangs, Core Audio daemon issues, lipo conflicts during parallel builds.

**Prevention**: Always use `./whisper` commands instead of old scripts.

### Auto-Paste Not Working

- Make sure you launched with `./whisper run`
- Check that "WhisperRecorder" appears in System Preferences → Privacy & Security → Accessibility

### Build Issues

```bash
# Clean build
./whisper clean
./whisper build

# If problems persist
./whisper cleanup
./whisper build
```

## Configuration

- **Model Selection**: Download and switch between different Whisper models
- **Writing Styles**: AI-powered text enhancement (requires Gemini API key)
- **Target Language**: Automatic translation support
- **Hotkeys**: Customizable keyboard shortcuts for recording

## Development

Built with:

- Swift 5.9+
- SwiftUI
- AVFoundation
- whisper.cpp integration
- Gemini AI API

### New Safety Features (v1.3.1+)

- ✅ Automatic process cleanup before operations
- ✅ Lockfiles prevent multiple instances
- ✅ No parallel jobs to avoid lipo conflicts
- ✅ Timeout protection for audio operations
- ✅ Emergency cleanup functionality

See documentation in `../docs/` for detailed development information.

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

## Credits

This app uses the following open-source libraries:

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C/C++ port of OpenAI's Whisper model
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Swift library for global keyboard shortcuts
