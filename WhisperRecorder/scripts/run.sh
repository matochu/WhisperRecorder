#!/bin/bash

echo "🚦 Safe Run WhisperRecorder"
echo "==========================="

# Check if any WhisperRecorder processes are running
existing=$(pgrep -f WhisperRecorder)
if [ -n "$existing" ]; then
    echo "⚠️  Found existing WhisperRecorder processes: $existing"
    echo "Killing them..."
    echo "$existing" | xargs kill -TERM 2>/dev/null
    sleep 2
    echo "$existing" | xargs kill -KILL 2>/dev/null
    sleep 1
fi

# Check if app exists
if [ ! -d "WhisperRecorder.app" ]; then
    echo "❌ WhisperRecorder.app not found!"
    echo "Build first with: ./package_manual.sh"
    exit 1
fi

echo "🚀 Starting WhisperRecorder..."
open WhisperRecorder.app

echo "✅ WhisperRecorder started successfully!"
echo ""
echo "💡 To monitor for hangs:"
echo "   watch 'ps aux | grep WhisperRecorder'" 