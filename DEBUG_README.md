# WhisperRecorder Debug Mode Guide

This document describes how to use debug mode in WhisperRecorder for troubleshooting and development.

## Debug Modes

### 1. 🖥️ Stdout Debug Mode (Console Mode)

Outputs all logs directly to the terminal with color formatting.

**How to Run:**

```bash
./debug-run.sh
```

**Features:**

- ✅ Detailed logs right in the terminal
- 🎨 Color formatting for easy reading
- ⚡ Quick start and monitoring
- 🔍 Emoji icons for different log levels
- 📊 Memory usage information

**Example Output:**

```
[14:30:15.123] ℹ️  INFO SYSTEM: WhisperRecorder starting
[14:30:15.125] 🐛 DEBUG AUDIO: Recording started - Sample rate: 44100Hz
[14:30:17.456] ⚠️  WARNING LLM: No Gemini API key available
[14:30:18.567] ❌ ERROR NETWORK: Connection failed
```

### 2. 📱 Simple Debug Mode (Console.app)

Standard mode with logging to macOS Console.app.

**How to Run:**

```bash
./debug-simple.sh
```

**Features:**

- 📋 Logs in the system Console.app
- 🔄 Application runs in the background
- 🔍 Search logs for "WhisperRecorder"
- 💾 Automatic log saving

## Environment Variables

### Main Variables

- `WHISPER_STDOUT_LOGS=1` - Enable output to stdout
- `WHISPER_DEBUG=1` - Enable debug mode
- `WHISPER_VERBOSE_LOGS=1` - Enable all types of logging

### Additional Settings

- `WHISPER_LOG_LEVEL=TRACE` - Set the logging level (TRACE, DEBUG, INFO, WARNING, ERROR)

## Manual Run

### For stdout logging:

```bash
export WHISPER_STDOUT_LOGS=1
export WHISPER_DEBUG=1
./WhisperRecorder/WhisperRecorder.app/Contents/MacOS/WhisperRecorder
```

### For Console.app logging:

```bash
export WHISPER_DEBUG=1
./WhisperRecorder/WhisperRecorder.app/Contents/MacOS/WhisperRecorder &
open -a Console
```

## Logging Categories

- **AUDIO** 🎵 - Audio recording and processing
- **WHISPER** 🗣️ - Operations with the Whisper model
- **LLM** 🤖 - Gemini API calls
- **UI** 🖼️ - Interface changes
- **STORAGE** 💾 - File operations
- **NETWORK** 🌐 - Network requests
- **MEMORY** 🧠 - Memory usage
- **PERFORMANCE** ⚡ - Performance measurement
- **SYSTEM** ⚙️ - System operations

## Logging Levels

1. **TRACE** 🔍 - Most detailed logs
2. **DEBUG** 🐛 - Information for debugging
3. **INFO** ℹ️ - General information
4. **WARNING** ⚠️ - Warnings
5. **ERROR** ❌ - Errors

## Practical Tips

### For troubleshooting:

1.  Run `./debug-run.sh`
2.  Reproduce the issue
3.  Copy the relevant logs
4.  Pay attention to ERROR and WARNING messages

### For development:

1.  Use `export WHISPER_VERBOSE_LOGS=1` for maximum logging
2.  Filter logs by category
3.  Monitor memory and performance

### Collecting logs for a report:

```bash
./debug-run.sh 2>&1 | tee debug_session.log
```

## Usage Examples

### Diagnosing API issues:

```bash
export WHISPER_STDOUT_LOGS=1
export WHISPER_DEBUG=1
./WhisperRecorder/WhisperRecorder.app/Contents/MacOS/WhisperRecorder | grep "LLM\|NETWORK"
```

### Monitoring memory:

```bash
./debug-run.sh | grep "MEMORY"
```

### Checking performance:

```bash
./debug-run.sh | grep "PERFORMANCE"
```

## Disabling Debug Mode

To disable, simply run the application without special variables:

```bash
./WhisperRecorder/WhisperRecorder.app/Contents/MacOS/WhisperRecorder
```

## File Structure

```
WhisperRecorder2/
├── debug-run.sh           # Stdout debug mode
├── debug-simple.sh        # Console.app debug mode
├── DEBUG_README.md        # This file
└── WhisperRecorder/
    └── Sources/
        └── WhisperRecorder/
            └── DebugManager.swift  # Main logging class
```

---

**Note:** This debug mode is intended for development and diagnostics. In production builds, logging will be minimal for optimal performance.
