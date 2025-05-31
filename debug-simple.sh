#!/bin/bash

# Simple debug script for WhisperRecorder with basic logging
# Usage: ./debug-simple.sh

# Set environment variables for basic debug mode
export WHISPER_DEBUG=1

echo "🚀 Starting WhisperRecorder in Simple Debug Mode"
echo "📊 Basic debugging enabled (Console.app logs)"
echo "=================================="
echo ""

# Check if the app exists
APP_PATH="./WhisperRecorder/WhisperRecorder.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    echo "Please build the app first or adjust the path"
    exit 1
fi

# Run the app normally (logs go to Console.app)
echo "🎯 Launching WhisperRecorder..."
echo "💡 Debug logs available in Console.app (search for 'WhisperRecorder')"
echo "🛑 App will run in background"
echo ""

# Run the app in background
"$APP_PATH/Contents/MacOS/WhisperRecorder" &

echo "✅ WhisperRecorder started with PID: $!"
echo "📱 Check your menu bar for the app icon"
echo "🔍 Open Console.app to view debug logs" 