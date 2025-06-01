#!/bin/bash
set -e

echo "➡️ Packaging WhisperRecorder.app..."

# Define app name variable
APP_NAME="WhisperRecorder"

# Set version for this release
APP_VERSION="1.3.1"

# Parse command line arguments
BUILD_ARCH=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch)
            BUILD_ARCH="$2"
            shift
            ;;
        --universal)
            BUILD_ARCH="universal"
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: ./package_app.sh [--arch arm64|x86_64] [--universal]"
            exit 1
            ;;
    esac
    shift
done

# Set default to universal if not specified
if [ -z "$BUILD_ARCH" ]; then
    BUILD_ARCH="universal"
fi

echo "Building for architecture: $BUILD_ARCH"

# Build the app with the specified architecture
if [ "$BUILD_ARCH" = "universal" ]; then
    echo "Building universal binary (arm64 + x86_64)..."
    ./build.sh --universal
elif [ "$BUILD_ARCH" = "arm64" ]; then
    echo "Building for Apple Silicon (arm64) only..."
    ./build.sh --arch arm64
elif [ "$BUILD_ARCH" = "x86_64" ]; then
    echo "Building for Intel (x86_64) only..."
    ./build.sh --arch x86_64
else
    echo "Invalid architecture specified: $BUILD_ARCH"
    echo "Valid options: arm64, x86_64, universal"
    exit 1
fi

# Create app icon if it doesn't exist
if [ ! -f "AppIcon.icns" ]; then
    echo "Creating app icon..."
    chmod +x create_icon.sh
    ./create_icon.sh
fi

# Create app bundle structure
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

# Create the directory structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

# Copy the executable
cp "WhisperRecorder" "$MACOS/$APP_NAME.bin"

# Show architecture information - if this fails, the build is corrupted
echo "Binary architecture information:"
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 5"
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 5"
else
    # Use perl as timeout alternative on macOS
    TIMEOUT_CMD="perl -e 'alarm 5; exec @ARGV' --"
fi

if ! $TIMEOUT_CMD lipo -info "$MACOS/$APP_NAME.bin" 2>/dev/null; then
    echo "❌ ERROR: lipo command failed or timed out - binary is corrupted!"
    echo "Removing corrupted binary and app bundle..."
    rm -rf "$APP_BUNDLE"
    rm -f "WhisperRecorder"
    exit 1
fi

# Copy dylib files to Frameworks
cp -R libs/* "$FRAMEWORKS/"

# Copy KeyboardShortcuts framework resources
KEYBOARD_SHORTCUTS_BUNDLE=""
# Try different possible locations for the bundle
for BUNDLE_PATH in \
    ".build/arm64-apple-macosx/debug/KeyboardShortcuts_KeyboardShortcuts.bundle" \
    ".build/arm64-apple-macosx/release/KeyboardShortcuts_KeyboardShortcuts.bundle" \
    ".build/x86_64-apple-macosx/debug/KeyboardShortcuts_KeyboardShortcuts.bundle" \
    ".build/x86_64-apple-macosx/release/KeyboardShortcuts_KeyboardShortcuts.bundle"; do
    if [ -d "$BUNDLE_PATH" ]; then
        KEYBOARD_SHORTCUTS_BUNDLE="$BUNDLE_PATH"
        break
    fi
done

if [ -n "$KEYBOARD_SHORTCUTS_BUNDLE" ]; then
    echo "📦 Copying KeyboardShortcuts resources from $KEYBOARD_SHORTCUTS_BUNDLE..."
    # Remove any existing bundle first
    rm -rf "$RESOURCES/KeyboardShortcuts_KeyboardShortcuts.bundle"
    # Copy the entire bundle directory to Resources
    cp -pR "$KEYBOARD_SHORTCUTS_BUNDLE" "$RESOURCES/"
    
    # Copy KeyboardShortcuts bundle to the root of app bundle where it expects to find it
    echo "📦 Copying KeyboardShortcuts bundle to app root for proper loading..."
    cp -pR "$KEYBOARD_SHORTCUTS_BUNDLE" "$APP_BUNDLE/"
    
    # Update the Info.plist to use relative paths
    INFO_PLIST="$RESOURCES/KeyboardShortcuts_KeyboardShortcuts.bundle/Info.plist"
    if [ -f "$INFO_PLIST" ]; then
        plutil -replace CFBundleExecutable -string "KeyboardShortcuts" "$INFO_PLIST" 2>/dev/null || true
        plutil -replace NSPrincipalClass -string "KeyboardShortcutsBundle" "$INFO_PLIST" 2>/dev/null || true
    fi
    
    # Verify the bundle was copied correctly
    if [ -d "$RESOURCES/KeyboardShortcuts_KeyboardShortcuts.bundle" ]; then
        echo "✅ KeyboardShortcuts bundle copied successfully to Resources"
    else
        echo "❌ Failed to copy KeyboardShortcuts bundle to Resources"
    fi
    
    if [ -d "$APP_BUNDLE/KeyboardShortcuts_KeyboardShortcuts.bundle" ]; then
        echo "✅ KeyboardShortcuts bundle copied successfully to app root"
    else
        echo "❌ Failed to copy KeyboardShortcuts bundle to app root"
    fi
else
    echo "⚠️ Warning: KeyboardShortcuts resources not found in any expected location"
    echo "Searching for bundle..."
    find .build -name "KeyboardShortcuts_KeyboardShortcuts.bundle" 2>/dev/null
fi

# Copy app icon to Resources
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES/"
fi

# Copy .env file if it exists
# if [ -f ".env" ]; then
#     echo "📄 Including .env file with Gemini API key"
#     cp ".env" "$RESOURCES/"
# else
#     echo "ℹ️ No .env file found. Creating a sample file in Resources."
#     cat > "$RESOURCES/.env.sample" << EOF
# # WhisperRecorder Gemini API Configuration
# # 
# # To use Gemini reformatting features:
# # 1. Get an API key from https://ai.google.dev/
# # 2. Copy this file to .env (remove the .sample extension)
# # 3. Add your API key after the equals sign below
# #
# GEMINI_API_KEY=your_api_key_here
# EOF
# fi

# Remove any whisper models from the bundle
echo "🔄 Removing any whisper models from the bundle"
rm -f "$RESOURCES/ggml-*.bin"

# Add a note about downloading models
cat > "$RESOURCES/README.txt" << EOF
WhisperRecorder will download models on demand.
You will be prompted to select and download a model when you first run the application.
EOF

# Note about whisper models
echo "📝 This version of WhisperRecorder will download models on demand."
echo "   The app will prompt the user to select and download models when needed."

# Create Info.plist
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhisperRecorder</string>
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
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperRecorder needs access to your microphone to record audio for transcription.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
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

# Create a launcher shell script that will be called by our C launcher
cat > "$MACOS/$APP_NAME.sh" << EOF
#!/bin/bash

# App name
APP_NAME="$APP_NAME" # Corrected this line

# Get the directory of this script
DIR="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" && pwd )"
APP_ROOT="\$( cd "\$DIR/../.." && pwd )"
CONTENTS="\$APP_ROOT/Contents"
RESOURCES="\$CONTENTS/Resources"
FRAMEWORKS="\$CONTENTS/Frameworks"
LOG_FILE="\$HOME/Library/Logs/WhisperRecorder.log"
DEBUG_LOG="\$HOME/Library/Application Support/WhisperRecorder/whisperrecorder_debug.log"

# Make sure the log directory exists
mkdir -p "\$(dirname "\$LOG_FILE")"
mkdir -p "\$(dirname "\$DEBUG_LOG")"

# Log function with stdout as well
log() {
    echo "\$(date): \$1" | tee -a "\$LOG_FILE"
}

# Start logging
log "==================== STARTING WHISPERRECORDER ===================="
log "Starting WhisperRecorder from launcher"
log "App path: \$APP_ROOT"
log "Frameworks path: \$FRAMEWORKS"
log "Resources path: \$RESOURCES"
log "Launcher directory: \$DIR"
log "Executable path: \$DIR/\$APP_NAME.bin"

# Check that the binary exists
if [ ! -f "\$DIR/\$APP_NAME.bin" ]; then
    log "ERROR: Main binary not found at \$DIR/\$APP_NAME.bin"
    osascript -e "display dialog \"WhisperRecorder could not start: Main binary not found\" buttons {\"OK\"} default button \"OK\" with icon stop"
    exit 1
fi

# Check executable permissions
if [ ! -x "\$DIR/\$APP_NAME.bin" ]; then
    log "ERROR: Main binary not executable at \$DIR/\$APP_NAME.bin"
    chmod +x "\$DIR/\$APP_NAME.bin"
    log "Fixed permissions on main binary"
fi

# List all libraries in Frameworks
log "Available libraries in Frameworks:"
ls -la "\$FRAMEWORKS" >> "\$LOG_FILE" 2>&1

# Setup environment variables for dynamically loaded libraries
export DYLD_LIBRARY_PATH="\$FRAMEWORKS:\$DYLD_LIBRARY_PATH"
log "DYLD_LIBRARY_PATH=\$DYLD_LIBRARY_PATH"

# Preload critical libraries
DYLD_LIBS=""
for lib in libwhisper.dylib libggml.dylib libggml-base.dylib libggml-cpu.dylib libggml-metal.dylib libggml-blas.dylib; do
    if [ -f "\$FRAMEWORKS/\$lib" ]; then
        if [ -n "\$DYLD_LIBS" ]; then
            DYLD_LIBS="\$DYLD_LIBS:\$FRAMEWORKS/\$lib"
        else
            DYLD_LIBS="\$FRAMEWORKS/\$lib"
        fi
    fi
done

export DYLD_INSERT_LIBRARIES="\$DYLD_LIBS"
log "DYLD_INSERT_LIBRARIES=\$DYLD_INSERT_LIBRARIES"

# Set environment variable to let app know it's running from bundle
export WHISPER_APP_BUNDLE=1
export WHISPER_RESOURCES_PATH="\$RESOURCES"
log "WHISPER_RESOURCES_PATH=\$WHISPER_RESOURCES_PATH"

# Add KeyboardShortcuts bundle path
if [ -d "\$RESOURCES/KeyboardShortcuts_KeyboardShortcuts.bundle" ]; then
    # Use @rpath for the bundle path
    export KEYBOARDSHORTCUTS_BUNDLE_PATH="@rpath/KeyboardShortcuts_KeyboardShortcuts.bundle"
    # Add Resources to rpath for bundle loading
    export DYLD_FRAMEWORK_PATH="\$RESOURCES:\$DYLD_FRAMEWORK_PATH"
    export DYLD_LIBRARY_PATH="\$RESOURCES:\$DYLD_LIBRARY_PATH"
    log "KEYBOARDSHORTCUTS_BUNDLE_PATH=\$KEYBOARDSHORTCUTS_BUNDLE_PATH"
else
    log "WARNING: KeyboardShortcuts bundle not found in resources"
fi

# Run the app with proper environment
log "Executing binary: \$DIR/\$APP_NAME.bin"
exec "\$DIR/\$APP_NAME.bin"
EOF
chmod +x "$MACOS/$APP_NAME.sh"

# Create a simple C launcher binary instead of shell script
cat > launcher.c << EOF
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <mach-o/dyld.h>

int main(int argc, char *argv[]) {
    char path[1024];
    char exec_path[1024];
    uint32_t size = sizeof(path);
    
    // Get the path of this executable - use macOS specific _NSGetExecutablePath
    if (_NSGetExecutablePath(path, &size) == 0) {
        printf("Executable path: %s\\n", path);
    } else {
        strcpy(path, argv[0]);
        printf("Using fallback path: %s\\n", path);
    }
    
    // Get the directory containing the executable
    char dir_path[1024];
    strcpy(dir_path, path);
    char *dir = dirname(dir_path);
    
    snprintf(exec_path, sizeof(exec_path), "%s/WhisperRecorder.sh", dir);
    printf("Looking for shell script at: %s\\n", exec_path);
    
    // Ensure the script exists
    if (access(exec_path, X_OK) != 0) {
        printf("Error: Cannot find or execute %s\\n", exec_path);
        return 1;
    }
    
    // Set environment variables
    setenv("WHISPER_APP_BUNDLE", "1", 1);
    setenv("WHISPER_RESOURCES_PATH", "@executable_path/../Resources", 1);
    setenv("KEYBOARDSHORTCUTS_BUNDLE_PATH", "@rpath/KeyboardShortcuts_KeyboardShortcuts.bundle", 1);
    printf("Launching shell script...\\n");
    
    // Execute the shell script
    char *args[2];
    args[0] = exec_path;
    args[1] = NULL;
    
    execv(exec_path, args);
    
    // If execv fails
    perror("Failed to execute WhisperRecorder.sh");
    return 1;
}
EOF

# Compile the C launcher
LAUNCHER_ARCH_FLAGS=""
if [ "$BUILD_ARCH" = "universal" ]; then
    LAUNCHER_ARCH_FLAGS="-arch arm64 -arch x86_64"
elif [ "$BUILD_ARCH" = "arm64" ]; then
    LAUNCHER_ARCH_FLAGS="-arch arm64"
elif [ "$BUILD_ARCH" = "x86_64" ]; then
    LAUNCHER_ARCH_FLAGS="-arch x86_64"
fi
gcc -mmacosx-version-min=12.0 $LAUNCHER_ARCH_FLAGS -o "$MACOS/$APP_NAME" launcher.c

# Update the executable to use @rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME.bin"

# Fix library paths in the executable
for lib in "$FRAMEWORKS"/*.dylib; do
    basename=$(basename "$lib")
    install_name_tool -change "$PWD/libs/$basename" "@rpath/$basename" "$MACOS/$APP_NAME.bin"
done

# Fix library paths in the dylibs themselves
for lib in "$FRAMEWORKS"/*.dylib; do
    basename=$(basename "$lib")
    for dep in "$FRAMEWORKS"/*.dylib; do
        depname=$(basename "$dep")
        if [ "$basename" != "$depname" ]; then
            install_name_tool -change "$PWD/libs/$depname" "@rpath/$depname" "$lib" 2>/dev/null || true
        fi
    done
done

# Clean up temporary files
rm -f launcher.c

# ./sign_app.sh "{{team id}}"

# zip -r WhisperRecorder-Universal.zip WhisperRecorder.app

echo "✅ WhisperRecorder.app has been created successfully!"
echo "You can run it from Finder or by double-clicking."