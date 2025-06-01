#!/bin/bash

echo "🔍 WhisperRecorder Audio Debug Script"
echo "======================================"

# Check if WhisperRecorder is running
echo "📱 Checking WhisperRecorder processes:"
ps aux | grep -i whisper | grep -v grep

# Check Core Audio daemon
echo ""
echo "🎵 Core Audio daemon status:"
ps aux | grep coreaudiod | grep -v grep

# Check audio devices
echo ""
echo "🎤 Audio input devices:"
system_profiler SPAudioDataType | grep -A5 "Input"

# Check permissions
echo ""
echo "🔐 Audio permissions:"
tccutil list | grep -i micro

# Check for zombie processes in UE state
echo ""
echo "👻 Processes in UE state:"
ps aux | awk '$8 ~ /U/ && $8 ~ /E/ {print $2, $8, $11}'

# Check system audio usage
echo ""
echo "🔊 Current audio usage:"
lsof /dev/audio* 2>/dev/null || echo "No processes using /dev/audio*"

# Check for stuck audio connections
echo ""
echo "🔌 Audio unit connections:"
lsof | grep -i audio | head -10

# Memory pressure
echo ""
echo "💾 Memory pressure:"
memory_pressure

echo ""
echo "🚨 If WhisperRecorder is stuck in UE state:"
echo "   1. Kill Core Audio: sudo killall coreaudiod"
echo "   2. Reset audio: sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist"
echo "   3. Force restart: sudo reboot"
echo ""
echo "🛠 Safe restart commands:"
echo "   sudo killall coreaudiod"
echo "   sleep 2"
echo "   sudo launchctl load /System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist" 