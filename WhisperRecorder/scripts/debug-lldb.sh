#!/bin/bash

# Safe LLDB Debug script for WhisperRecorder
# Usage: ./debug-lldb.sh

echo "🛡️ Safe LLDB Debug Mode for WhisperRecorder"
echo "==========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    local lockfile="/tmp/whisperrecorder-debug-lldb.lock"
    if [ -f "$lockfile" ]; then
        echo -e "${RED}❌ ERROR: Another LLDB debug session is already running!${NC}"
        echo "If this is wrong, remove: $lockfile"
        exit 1
    fi
    echo $$ > "$lockfile"
    trap "rm -f $lockfile; echo 'LLDB debug session ended'" EXIT
}

echo "1. Checking for running processes..."
check_running_processes

echo "2. Creating debug lock..."
create_debug_lockfile

# Check if lldb is available
if ! command -v lldb &> /dev/null; then
    echo -e "${RED}❌ ERROR: lldb not found!${NC}"
    echo "Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

# Check if the app exists
APP_PATH="./WhisperRecorder/WhisperRecorder.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at $APP_PATH${NC}"
    echo "Build first with: cd WhisperRecorder && ./package_manual.sh"
    exit 1
fi

BINARY_PATH="$APP_PATH/Contents/MacOS/WhisperRecorder.bin"
if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}❌ Binary not found at $BINARY_PATH${NC}"
    exit 1
fi

echo "3. Setting up LLDB environment..."
echo -e "${BLUE}📊 Debug Target: $BINARY_PATH${NC}"
echo ""

echo "4. Starting LLDB session..."
echo -e "${GREEN}💡 Useful LLDB commands:${NC}"
echo "   (lldb) run                    # Start the app"
echo "   (lldb) bt                     # Show backtrace if crashed"
echo "   (lldb) thread list            # List all threads"
echo "   (lldb) thread backtrace all   # Backtrace of all threads"
echo "   (lldb) c                      # Continue execution"
echo "   (lldb) quit                   # Exit LLDB"
echo ""
echo -e "${YELLOW}🛑 Starting LLDB...${NC}"
echo ""

# Set environment variables for debug mode
export WHISPER_DEBUG=1
export WHISPER_STDOUT_LOGS=1

# Start LLDB with the binary
lldb "$BINARY_PATH"

echo ""
echo -e "${YELLOW}🏁 LLDB debug session ended${NC}" 