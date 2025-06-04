#!/bin/bash
set -e

echo "🛡️ Safe Build & Packaging WhisperRecorder.app..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if any WhisperRecorder processes are running
check_running_processes() {
    local running=$(pgrep -f "WhisperRecorder|lipo")
    if [ -n "$running" ]; then
        echo -e "${RED}❌ ERROR: WhisperRecorder or lipo processes still running!${NC}"
        echo "Running processes: $running"
        echo "Kill them first or restart your Mac"
        exit 1
    fi
}

# Function to create lockfile
create_lockfile() {
    local lockfile="/tmp/whisperrecorder-build.lock"
    if [ -f "$lockfile" ]; then
        echo -e "${RED}❌ ERROR: Another build is already running!${NC}"
        echo "If this is wrong, remove: $lockfile"
        exit 1
    fi
    echo $$ > "$lockfile"
    trap "rm -f $lockfile" EXIT
}

# Skip checks if called from main whisper script
if [ "$SKIP_CHECKS" != "1" ]; then
    echo "1. Checking for running processes..."
    check_running_processes

    echo "2. Creating build lock..."
    create_lockfile
else
    echo "1. Skipping process checks (called from main script)..."
fi

echo "3. Cleaning previous builds..."
rm -rf .build
rm -f WhisperRecorder
rm -rf WhisperRecorder.app

# Build Swift app fresh
echo "4. Building Swift app (safe mode, no parallel jobs)..."
if [ "$DEBUG_BUILD" = "1" ]; then
    echo "   🐛 DEBUG BUILD MODE"
    swift build -c debug --arch arm64 --jobs 1
    BUILD_CONFIG="debug"
else
    echo "   🚀 RELEASE BUILD MODE"
swift build -c release --arch arm64 --jobs 1
    BUILD_CONFIG="release"
fi

# Copy fresh binary
echo "5. Copying fresh binary..."
cp ".build/arm64-apple-macosx/$BUILD_CONFIG/WhisperRecorder" .

APP_NAME="WhisperRecorder"

# Get version from VERSION file
if [ -f "VERSION" ]; then
    APP_VERSION=$(cat VERSION)
else
    APP_VERSION="1.0.0"
fi

echo "📦 Packaging WhisperRecorder v$APP_VERSION for Apple Silicon (arm64)..."

# Create app bundle structure
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

# Clean and create directories
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

# Copy the executable
echo "6. Packaging executable..."
cp "WhisperRecorder" "$MACOS/$APP_NAME.bin"
echo "✅ Binary packaged successfully"

# Copy dylib files to Frameworks (one by one to avoid conflicts)
echo "7. Copying libraries (safe mode)..."
if [ -d "libs" ]; then
    for lib in libs/*.dylib; do
        if [ -f "$lib" ]; then
            echo "   Copying $(basename "$lib")..."
            cp "$lib" "$FRAMEWORKS/"
        fi
    done
else
    echo -e "${YELLOW}⚠️  Warning: libs directory not found${NC}"
fi

# Copy KeyboardShortcuts bundle if it exists
KEYBOARD_SHORTCUTS_BUNDLE=""
# First try current build config, then fallback to any available
if [ -n "$BUILD_CONFIG" ] && [ -d ".build/arm64-apple-macosx/$BUILD_CONFIG/KeyboardShortcuts_KeyboardShortcuts.bundle" ]; then
    KEYBOARD_SHORTCUTS_BUNDLE=".build/arm64-apple-macosx/$BUILD_CONFIG/KeyboardShortcuts_KeyboardShortcuts.bundle"
else
    # Fallback to searching all configs
for BUNDLE_PATH in \
    ".build/arm64-apple-macosx/debug/KeyboardShortcuts_KeyboardShortcuts.bundle" \
    ".build/arm64-apple-macosx/release/KeyboardShortcuts_KeyboardShortcuts.bundle"; do
    if [ -d "$BUNDLE_PATH" ]; then
        KEYBOARD_SHORTCUTS_BUNDLE="$BUNDLE_PATH"
        break
    fi
done
fi

if [ -n "$KEYBOARD_SHORTCUTS_BUNDLE" ]; then
    echo "8. Copying KeyboardShortcuts resources from $KEYBOARD_SHORTCUTS_BUNDLE..."
    cp -pR "$KEYBOARD_SHORTCUTS_BUNDLE" "$RESOURCES/"
    echo "✅ KeyboardShortcuts bundle copied"
fi

# Copy app icon to Resources
echo "9. Copying app icon..."
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/"
    echo "✅ App icon copied successfully"
else
    echo "⚠️  Warning: AppIcon.icns not found. Run ./create_icon.sh first"
fi

# Remove any whisper models from the bundle (they will be downloaded on demand)
echo "10. Removing any whisper models from bundle..."
rm -f "$RESOURCES/ggml-*.bin"

# Add a note about downloading models
echo "11. Creating README for model downloads..."
cat > "$RESOURCES/README.txt" << EOF
WhisperRecorder will download models on demand.
You will be prompted to select and download a model when you first run the application.
EOF

echo "📝 Note: WhisperRecorder will download models on demand."
echo "   The app will prompt the user to select and download models when needed."

# Create Info.plist
echo "11. Creating Info.plist with version $APP_VERSION..."
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhisperRecorder.bin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisper.WhisperRecorder</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2025 WhisperRecorder. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperRecorder needs microphone access to record and transcribe audio.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>WhisperRecorder needs permission to send keystrokes for auto-paste functionality.</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSEnvironment</key>
    <dict>
        <key>WHISPER_APP_BUNDLE</key>
        <string>1</string>
        <key>WHISPER_RESOURCES_PATH</key>
        <string>@executable_path/../Resources</string>
    </dict>
</dict>
</plist>
EOF

# Create launcher shell script
echo "13. Creating launcher shell script..."
cat > "$MACOS/$APP_NAME.sh" << EOF
#!/bin/bash
DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
FRAMEWORKS="\$DIR/../Frameworks"
export DYLD_LIBRARY_PATH="\$FRAMEWORKS:\$DYLD_LIBRARY_PATH"
export WHISPER_APP_BUNDLE=1
export WHISPER_RESOURCES_PATH="\$DIR/../Resources"
exec "\$DIR/$APP_NAME.bin"
EOF
chmod +x "$MACOS/$APP_NAME.sh"

# Create C launcher
echo "14. Creating C launcher..."
cat > launcher.c << EOF
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <mach-o/dyld.h>

int main(int argc, char *argv[]) {
    char path[1024];
    uint32_t size = sizeof(path);
    
    if (_NSGetExecutablePath(path, &size) == 0) {
        char dir_path[1024];
        strcpy(dir_path, path);
        char *dir = dirname(dir_path);
        
        char exec_path[1024];
        snprintf(exec_path, sizeof(exec_path), "%s/WhisperRecorder.sh", dir);
        
        setenv("WHISPER_APP_BUNDLE", "1", 1);
        setenv("WHISPER_RESOURCES_PATH", "@executable_path/../Resources", 1);
        
        char *args[2];
        args[0] = exec_path;
        args[1] = NULL;
        
        execv(exec_path, args);
    }
    
    return 1;
}
EOF

# Compile launcher
echo "15. Compiling launcher..."
gcc -mmacosx-version-min=12.0 -arch arm64 -o "$MACOS/$APP_NAME" launcher.c

# Fix library paths
echo "16. Fixing library paths..."
if [ "$DEBUG_BUILD" = "1" ]; then
    echo "   🐛 SKIPPING library path fixes for debug build (to preserve code signing)"
    echo "   📝 Debug builds will use DYLD_LIBRARY_PATH from launcher script"
else
    echo "   🔧 Applying library path fixes for release build..."
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME.bin"
fi

echo "17. Updating dylib references..."
if [ "$DEBUG_BUILD" = "1" ]; then
    echo "   🐛 SKIPPING dylib reference updates for debug build (to preserve code signing)"
else
    echo "   🔧 Updating dylib references for release build..."
    for lib in "$FRAMEWORKS"/*.dylib; do
        if [ -f "$lib" ]; then
            basename=$(basename "$lib")
            echo "   Fixing $basename..."
            install_name_tool -change "$PWD/libs/$basename" "@rpath/$basename" "$MACOS/$APP_NAME.bin" 2>/dev/null || echo "   (no change needed for $basename)"
        fi
    done
fi

# Clean up
echo "18. Cleaning up temporary files..."
rm -f launcher.c
rm -f WhisperRecorder

echo -e "${GREEN}✅ WhisperRecorder.app created successfully (safe build)!${NC}"
echo ""
echo "🚦 To run safely:"
echo "   open WhisperRecorder.app"
echo ""
echo "💡 To check for hangs:"
echo "   watch 'ps aux | grep WhisperRecorder'" 