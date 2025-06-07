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

# 📦 Build Commands
./whisper build           # Build WhisperRecorder.app (safe mode, no parallel jobs)
./whisper build-debug     # Build in debug mode with enhanced logging
./whisper run             # Run the app (automatic process cleanup)
./whisper clean           # Clean build artifacts

# 🚀 Release Commands
./whisper release         # Create release package with signing
./whisper icon            # Generate app icon from create_icon.sh
./whisper notarize        # Apple notarization for public distribution

# 📋 Version Management (New!)
./whisper version                # Show current version
./whisper version set 1.4.0     # Set specific version
./whisper version bump patch    # Bump version (1.3.1 → 1.3.2)
./whisper version bump minor    # Bump version (1.3.1 → 1.4.0)
./whisper version bump major    # Bump version (1.3.1 → 2.0.0)

# 🚀 Release Workflows
./whisper version release       # Local release (no GitHub)
./whisper version preview       # Preview build → GitHub pre-release
./whisper version publish minor # Local build + GitHub release + version bump
./whisper version tag-release   # Tag + push (triggers GitHub Action)

# 🧪 Testing Commands (New!)
./whisper test            # Interactive test selection menu
./whisper test quick      # E2E simulated tests (~21s)
./whisper test real       # Real audio with Whisper model
./whisper test performance # Performance benchmarks (~5s)
./whisper test ui         # UI Integration tests (~1s)
./whisper test ui-e2e     # UI Component E2E tests (~0.3s)
./whisper test ui-full    # Complete UI test suite (~1.5s)
./whisper test all        # All available tests

# 🔗 Development Setup
../scripts/setup-git-hooks.sh  # Install pre-commit testing hooks

# 🔧 Utility Commands
./whisper help            # Show all available commands
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
# Emergency cleanup - use scripts directly
./scripts/emergency-cleanup.sh

# Check for hanging processes
ps aux | grep WhisperRecorder | grep -v grep

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
./scripts/emergency-cleanup.sh
./whisper build

# For detailed debugging
./whisper build-debug
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
- ✅ Unified command interface (`./whisper`)
- ✅ Version management and automated releases
- ✅ GitHub Actions integration for CI/CD
- ✅ CHANGELOG.md based release notes

### Release Management

For creating and managing releases, see the **[Release Guide](RELEASE_GUIDE.md)** which covers:

- Automated GitHub release workflow with smart versioning
- Version management commands (`./whisper version`)
- Feature branch pre-releases and CHANGELOG.md integration
- Step-by-step release process and troubleshooting

### GitHub Actions (New!)

WhisperRecorder now includes automated GitHub release workflow:

```bash
# Automatic release (creates tag and triggers GitHub Action)
./whisper version bump minor
./whisper version release

# Manual GitHub workflow
# 1. Go to GitHub Actions → "WhisperRecorder Release"
# 2. Click "Run workflow"
# 3. Select version bump type (patch/minor/major)
# 4. Optionally check "Create pre-release" for feature branches
```

**Features:**

- ✅ Smart versioning with dropdown selection
- ✅ Automatic artifact creation: `WhisperRecorder-v1.4.0-macOS-arm64.zip`
- ✅ CHANGELOG.md integration for release notes
- ✅ Feature branch pre-release support
- ✅ Safe build environment with process monitoring

See documentation in `../docs/` for detailed development information.

## 🧪 Testing Infrastructure

WhisperRecorder includes a comprehensive testing suite for quality assurance and regression prevention:

### Test Categories

#### 🏃‍♂️ Development Tests (Fast)

- **quick** - E2E simulated tests (~21s) - Complete flow without Whisper model
- **ui** - UI Integration tests (~1s) - Component integration validation (12 tests)
- **ui-e2e** - UI Component E2E tests (~0.3s) - Real UI behavior testing (9 tests)

#### 🎯 Validation Tests (Real)

- **real** - Real Whisper model testing with actual .wav files
- **performance** - Performance benchmarks (~5s) - Memory and speed metrics
- **ui-full** - Complete UI test suite (~1.5s) - All UI tests combined (21 tests)

#### 🚀 Complete Testing

- **all** - Complete test suite - All categories combined

### What Each Category Tests

- **🏃‍♂️ Quick Tests**: Transcription flow, error recovery, state transitions (no model required)
- **🎨 UI Tests**: Toast system, clipboard operations, component integration (100% success)
- **🎯 Real Audio**: Whisper model accuracy with known transcription validation
- **⚡ Performance**: Memory tracking (~7.4MB peak), processing speed, resource cleanup

### Interactive Testing

```bash
# Interactive test selection
./whisper test              # Shows organized menu with all options

# Quick development tests
./whisper test quick        # Fast E2E feedback (~21s)
./whisper test ui           # UI component validation (~1s)

# Complete validation
./whisper test ui-full      # All UI tests (21 tests, ~1.5s)
./whisper test all          # Complete test suite

# Pre-commit testing (automatic)
git commit                  # Triggers pre-commit hook with quick tests
```

### CI/CD Integration

- **GitHub Actions**: Automated testing on PR/push
- **Pre-commit Hooks**: Local testing before commits
- **Performance Monitoring**: Track speed and memory regressions
- **Test Coverage**: E2E, UI, Performance, Real Audio validation

### Test Results (Latest)

- ✅ **UI Integration Tests**: 12/12 passed (100% success)
- ✅ **UI Component E2E Tests**: 9/9 passed (100% success)
- ✅ **Performance Tests**: ~38K ops/sec (Integration), ~226K ops/sec (E2E)
- ✅ **Library Management**: Automated libwhisper.1.dylib handling
- ✅ **Memory Efficiency**: Proper cleanup, no memory leaks

For detailed testing documentation, see [test-suite-overview.md](../docs/contexts/technical/test-suite-overview.md).

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

### Automated Release (Recommended)

For automated releases with proper versioning and GitHub integration:

```bash
# 1. Automatic release
./whisper version bump minor    # or patch/major
./whisper version release      # Creates tag and triggers GitHub Action

# 2. Manual GitHub release
# Go to GitHub Actions → "WhisperRecorder Release" → "Run workflow"
# Select version bump type and run
```

This will automatically:

- Build and package the app
- Create versioned ZIP: `WhisperRecorder-v1.4.0-macOS-arm64.zip`
- Generate release notes from CHANGELOG.md
- Upload to GitHub Releases

### Manual Packaging

For local development and testing:

```bash
# Create release package manually
./whisper release

# Or use the package script directly
./package.sh
```

### Creating a Distributable App

To create a standalone app bundle that can be distributed to other users:

1. Run `./whisper release` to build the app bundle with signing
2. The script will create `WhisperRecorder.app` with all necessary resources and libraries

### Installation on Other Machines

1. Download `WhisperRecorder-v{version}-macOS-arm64.zip` from GitHub Releases
2. Unzip and move WhisperRecorder.app to the Applications folder
3. Right-click on the app and select "Open" to bypass macOS security (first run only)
4. Grant microphone permissions when prompted
5. Select and download your preferred Whisper model when prompted

## Credits

This app uses the following open-source libraries:

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C/C++ port of OpenAI's Whisper model
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - Swift library for global keyboard shortcuts
