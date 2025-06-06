#!/bin/bash

echo "🚨 EMERGENCY CLEANUP for WhisperRecorder"
echo "========================================"

# Function to safely kill processes
safe_kill() {
    local pids="$1"
    local process_name="$2"
    
    if [ -n "$pids" ]; then
        echo "🔫 Killing $process_name processes: $pids"
        echo "$pids" | xargs kill -TERM 2>/dev/null
        sleep 2
        echo "$pids" | xargs kill -KILL 2>/dev/null
        sleep 1
    else
        echo "✅ No $process_name processes found"
    fi
}

# 1. Kill all lipo processes (these are blocking the binary)
echo "1. Killing all lipo processes..."
LIPO_PIDS=$(pgrep lipo)
safe_kill "$LIPO_PIDS" "lipo"

# 2. Kill all WhisperRecorder processes
echo "2. Killing all WhisperRecorder processes..."
WHISPER_PIDS=$(pgrep -f WhisperRecorder)
safe_kill "$WHISPER_PIDS" "WhisperRecorder"

# 3. Kill any cmake test processes
echo "3. Killing cmake test processes..."
CMAKE_PIDS=$(pgrep -f cmTC_)
safe_kill "$CMAKE_PIDS" "cmake test"

# 4. Clean up build artifacts
echo "4. Cleaning build artifacts..."
cd "$(dirname "$0")"
rm -rf build/
rm -rf WhisperRecorder/.build/
rm -rf WhisperRecorder/WhisperRecorder.app/

# 5. Check if any processes are still running
echo "5. Checking remaining processes..."
REMAINING=$(pgrep -f "WhisperRecorder|lipo")
if [ -n "$REMAINING" ]; then
    echo "⚠️  WARNING: Some processes still running: $REMAINING"
    echo "   You may need to restart your Mac"
else
    echo "✅ All processes cleaned up successfully"
fi

echo ""
echo "🎯 Ready for clean build!"
echo "Use: ./safe-build.sh" 