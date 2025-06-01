#!/bin/bash

# WhisperRecorder Proper Launch Script
# This script launches the app through Finder to ensure proper accessibility permissions

APP_PATH="$(pwd)/WhisperRecorder.app"

echo "🚀 Launching WhisperRecorder properly..."
echo "📍 App path: $APP_PATH"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ WhisperRecorder.app not found. Please run './package_manual.sh' first."
    exit 1
fi

echo "🔧 Opening app through Finder to ensure proper permissions..."
# Use 'open' command which launches through Finder/LaunchServices
open "$APP_PATH"

echo "✅ WhisperRecorder launched successfully!"
echo ""
echo "💡 TIP: For accessibility permissions:"
echo "   1. Click the WhisperRecorder menu bar icon"
echo "   2. Look for the Auto-Paste status in the configuration panel"
echo "   3. If permissions are needed, follow the prompts"
echo "   4. The app should appear as 'WhisperRecorder' in System Preferences → Privacy & Security → Accessibility"
echo "" 