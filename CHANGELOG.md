# WhisperRecorder Changelog

All notable changes to WhisperRecorder will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- UI state debugging and monitoring in ConfigurationCard
- Enhanced LLM management with multiple provider support
- State tracking for menu interactions with timestamps
- Accessibility and Clipboard Managers for auto-paste functionality
- Contextual processing features with improved keyboard shortcuts
- Debug mode functionality with comprehensive logging system
- Audio debugging tools and enhanced recording features
- Popover improvements for better UI interaction
- Periodic UI state logging to detect potential freezes
- Enhanced ToastManager with different toast types (normal, contextual, error)
- Toast visual improvements with proper styling for different types
- Packaging script (package.sh) with build safety and process monitoring
- Release management commands in main whisper script
- Build lockfile management to prevent concurrent builds
- Waveform SVG asset for visual representation
- Automated GitHub release workflow with smart versioning
- Version management system with semantic versioning (patch/minor/major)
- Feature branch pre-release support
- CHANGELOG.md integration for release notes generation

### Fixed

- Build process safety with hanging process detection and cleanup
- Toast notification reliability and visual consistency
- UI interaction monitoring for debugging purposes

### Changed

- Refactored LLM management architecture
- Enhanced ToastManager to support contextual feedback during operations
- Updated AudioRecorder with improved toast integration
- Improved build script with safety checks and lockfiles
- GitHub release workflow now uses dropdown selection instead of manual version entry
- Release notes now generated from CHANGELOG.md instead of git commits
- Enhanced popover functionality for better UX

## [1.3.0]

### Added

- AI-powered text enhancement with Gemini integration
- KeyboardShortcuts bundle loading fixes (from upstream)
- Writing style templates

### Fixed

- KeyboardShortcuts bundle loading in app bundle (upstream merge)
- LLM provider integration and API management
- Audio recording stability and accessibility permissions
- Build process improvements and packaging

### Changed

- Improved writing style features and processing

## [1.0.0] - Initial Release

### Added

- Complete WhisperRecorder macOS application
- Real-time voice recording and transcription using Whisper AI
- Auto-paste functionality to active applications
- Smart toast notification system
- Offline Whisper AI model support
- macOS menu bar integration
- Apple Silicon (arm64) optimized build
- Basic configuration management
- Model download and management system
- Hotkeys and keyboard shortcuts support
- Status monitoring and recording controls
- Accessibility permissions handling

### Features

- 🎙️ Real-time voice recording and transcription
- 🤖 AI-powered text enhancement
- 📋 Auto-paste to active applications
- 💬 Smart toast notifications with previews
- ⚡ Offline Whisper AI models
- 🌍 Multiple language support
- ⚙️ Configuration management
- 🔐 Accessibility permissions handling
- 📱 Menu bar integration
- 🎨 Modern macOS design

### Requirements

- macOS 12.0+ (Monterey or later)
- Apple Silicon (M1/M2/M3) Mac
- Microphone access permission
- Optional: Accessibility permissions for auto-paste
