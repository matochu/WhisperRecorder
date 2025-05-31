#!/bin/bash

# Debug script for WhisperRecorder with stdout logging
# Usage: ./debug-run.sh

# Set environment variables for debug mode
export WHISPER_STDOUT_LOGS=1
export WHISPER_DEBUG=1

# Optional: Set log level
# export WHISPER_LOG_LEVEL=TRACE

echo "🚀 Starting WhisperRecorder in Debug Mode"
echo "📊 Environment Variables:"
echo "   WHISPER_STDOUT_LOGS=${WHISPER_STDOUT_LOGS}"
echo "   WHISPER_DEBUG=${WHISPER_DEBUG}"
echo "=================================="
echo ""

# Check if the app exists
APP_PATH="./WhisperRecorder/WhisperRecorder.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    echo "Please build the app first or adjust the path"
    exit 1
fi

# Run the app with stdout logging
echo "🎯 Launching WhisperRecorder..."
echo "💡 All debug logs will appear in this terminal"
echo "🛑 Press Ctrl+C to stop"
echo ""

# Run the app and capture all output
"$APP_PATH/Contents/MacOS/WhisperRecorder" 2>&1

echo ""
echo "🏁 WhisperRecorder debug session ended" 