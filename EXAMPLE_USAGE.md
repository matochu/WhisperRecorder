# Example Usage of Debug Mode

## Quick Start

### 1. Build the App

```bash
cd WhisperRecorder
swift build -c debug
```

### 2. Run with Full Logging

```bash
cd ..
./debug-run.sh
```

### Expected Output:

```
🚀 Starting WhisperRecorder in Debug Mode
📊 Environment Variables:
   WHISPER_STDOUT_LOGS=1
   WHISPER_DEBUG=1
==================================

🎯 Launching WhisperRecorder...
💡 All debug logs will appear in this terminal
🛑 Press Ctrl+C to stop

=== WhisperRecorder Debug Mode - Console Output ===
Configuration: stdout=true, console=false, file=false
Log Level: TRACE
Categories: AUDIO, WHISPER, LLM, UI, STORAGE, NETWORK, MEMORY, PERFORMANCE, SYSTEM, GENERAL
=================================================

[14:30:15.123] ℹ️  INFO SYSTEM: =====================================================
[14:30:15.124] ℹ️  INFO SYSTEM: WhisperRecorder starting
[14:30:15.125] ℹ️  INFO SYSTEM: Bundle ID: com.example.WhisperRecorder
[14:30:15.126] 🐛 DEBUG SYSTEM: Bundle resource path: /path/to/app/Resources
[14:30:15.127] ℹ️  INFO LLM: WritingStyleManager initializing...
[14:30:15.128] 🐛 DEBUG LLM: Starting to load API key...
[14:30:15.129] ⚠️  WARNING LLM: ❌ Could not locate .env file with valid Gemini API key
[14:30:15.130] ℹ️  INFO SYSTEM: Setting up keyboard shortcut
[14:30:15.131] ℹ️  INFO UI: Setting up status update handler
[14:30:15.132] 🐛 DEBUG UI: Creating status item
[14:30:15.133] 🐛 DEBUG UI: Configuring status item button
[14:30:15.134] 🐛 DEBUG UI: Creating popover
[14:30:15.135] 🐛 DEBUG UI: Menu bar setup complete
[14:30:15.136] ℹ️  INFO SYSTEM: Application startup complete
[14:30:20.001] 🐛 DEBUG MEMORY: Memory usage: 42.3MB (+0.0MB)
```

## Usage Scenarios

### Diagnosing Recording Issues

```bash
# Run debug mode
./debug-run.sh

# Press the record key and check the logs:
[14:31:15.234] 🐛 DEBUG AUDIO: AudioRecorder: toggleRecording called
[14:31:15.235] ℹ️  INFO AUDIO: AudioRecorder: Starting recording session
[14:31:15.236] 🐛 DEBUG AUDIO: AudioRecorder: AVAudioSession configured
[14:31:15.237] ℹ️  INFO AUDIO: AudioRecorder: ✅ Recording started successfully
[14:31:15.238] 🐛 DEBUG UI: Updating menu bar
```

### Diagnosing API Issues

```bash
# Filter only LLM and NETWORK logs
./debug-run.sh | grep "LLM\|NETWORK"

# Expected output when there are API issues:
[14:32:15.456] ⚠️  WARNING LLM: ❌ No Gemini API key available - returning original text
[14:32:15.457] ❌ ERROR NETWORK: Connection failed: timeout
```

### Monitoring Performance

```bash
# Filter only PERFORMANCE logs
./debug-run.sh | grep "PERFORMANCE"

# Expected output:
[14:33:15.678] 🔍 TRACE PERFORMANCE: Started timing: whisper_transcription
[14:33:17.890] ℹ️  INFO PERFORMANCE: whisper_transcription completed in 2.212s
[14:33:17.891] 🔍 TRACE PERFORMANCE: Started timing: llm_processing
[14:33:18.456] ℹ️  INFO PERFORMANCE: llm_processing completed in 0.565s
```

## Saving Logs for Analysis

```bash
# Save all logs to a file
./debug-run.sh 2>&1 | tee debug_session_$(date +%Y%m%d_%H%M%S).log

# Save only errors
./debug-run.sh 2>&1 | grep "ERROR\|WARNING" | tee errors_$(date +%Y%m%d_%H%M%S).log
```

## Useful Commands

### Check the API Key Status

```bash
./debug-run.sh | grep "API key"
```

### Monitor Memory in Real Time

```bash
./debug-run.sh | grep "Memory usage"
```

### Check Whisper Model Loading

```bash
./debug-run.sh | grep "WHISPER.*Model"
```

## Disabling Debug Mode

To run normally without logging:

```bash
./WhisperRecorder/WhisperRecorder.app/Contents/MacOS/WhisperRecorder &
```
