#!/bin/bash
set -e

echo "➡️ Simple Packaging WhisperRecorder.app..."

APP_NAME="WhisperRecorder"
APP_VERSION="1.3.1"

# Just build the Swift app without rebuilding whisper.cpp
echo "Building Swift app..."
swift build -c release

# Copy the binary
cp .build/release/WhisperRecorder .

# Test binary integrity
echo "Testing binary integrity..."
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 5"
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 5"
else
    TIMEOUT_CMD="perl -e 'alarm 5; exec @ARGV' --"
fi

if $TIMEOUT_CMD lipo -info WhisperRecorder >/dev/null 2>&1; then
    echo "✅ Binary integrity verified"
    echo "Build completed successfully"
else
    echo "❌ ERROR: Binary verification failed - build is corrupted!"
    rm -f WhisperRecorder
    exit 1
fi

# Create basic app bundle
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp WhisperRecorder "$MACOS/$APP_NAME"

# Create minimal Info.plist
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisper.WhisperRecorder</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperRecorder needs microphone access.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Simple $APP_NAME.app created!" 