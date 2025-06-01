#!/bin/bash

# Safe Debug script for WhisperRecorder with stdout logging
# Usage: ./debug-run.sh

echo "🛡️ Safe Interactive Debug Mode for WhisperRecorder"
echo "================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if any WhisperRecorder processes are running
check_running_processes() {
    local running=$(pgrep -f WhisperRecorder)
    if [ -n "$running" ]; then
        echo -e "${YELLOW}⚠️  Found existing WhisperRecorder processes: $running${NC}"
        echo "Killing them for clean debug session..."
        echo "$running" | xargs kill -TERM 2>/dev/null
        sleep 2
        echo "$running" | xargs kill -KILL 2>/dev/null
        sleep 1
        
        # Double check
        local still_running=$(pgrep -f WhisperRecorder)
        if [ -n "$still_running" ]; then
            echo -e "${RED}❌ Could not kill processes: $still_running${NC}"
            echo "Run: ./emergency-cleanup.sh"
            exit 1
        fi
    fi
}

# Function to create debug lockfile
create_debug_lockfile() {
    local lockfile="/tmp/whisperrecorder-debug-interactive.lock"
    if [ -f "$lockfile" ]; then
        echo -e "${RED}❌ ERROR: Another interactive debug session is already running!${NC}"
        echo "If this is wrong, remove: $lockfile"
        exit 1
    fi
    echo $$ > "$lockfile"
    trap "rm -f $lockfile; echo 'Debug session ended'" EXIT
}

echo "1. Checking for running processes..."
check_running_processes

echo "2. Creating debug lock..."
create_debug_lockfile

# Set environment variables for debug mode
export WHISPER_STDOUT_LOGS=1
export WHISPER_DEBUG=1

# Optional: Set log level
# export WHISPER_LOG_LEVEL=TRACE

echo "3. Setting up debug environment..."
echo "📊 Environment Variables:"
echo "   WHISPER_STDOUT_LOGS=${WHISPER_STDOUT_LOGS}"
echo "   WHISPER_DEBUG=${WHISPER_DEBUG}"
echo "=================================="
echo ""

# Check if the app exists
APP_PATH="./WhisperRecorder/WhisperRecorder.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at $APP_PATH${NC}"
    echo "Build first with: cd WhisperRecorder && ./package_manual.sh"
    exit 1
fi

# Run the app with stdout logging
echo "4. Launching WhisperRecorder in interactive debug mode..."
echo "💡 All debug logs will appear in this terminal"
echo "🛑 Press Ctrl+C to stop"
echo ""

# Run the app and capture all output
echo -e "${GREEN}🚀 Starting debug session...${NC}"
"$APP_PATH/Contents/MacOS/WhisperRecorder" 2>&1

echo ""
echo -e "${YELLOW}🏁 WhisperRecorder debug session ended${NC}" 