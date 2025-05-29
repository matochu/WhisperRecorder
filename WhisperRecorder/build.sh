#!/bin/bash

# Get the absolute path to the whisper.cpp directory
WHISPER_PATH=$(cd .. && pwd)

# Check for architecture flag
BUILD_UNIVERSAL=true
BUILD_ARCH=""

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch)
            BUILD_UNIVERSAL=false
            BUILD_ARCH="$2"
            shift
            ;;
        --universal)
            BUILD_UNIVERSAL=true
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Usage: ./build.sh [--arch arm64|x86_64] [--universal]"
            exit 1
            ;;
    esac
    shift
done

if [ "$BUILD_UNIVERSAL" = true ]; then
    echo "Building universal binary (arm64 + x86_64)"
elif [ "$BUILD_ARCH" = "arm64" ]; then
    echo "Building for Apple Silicon (arm64) only"
elif [ "$BUILD_ARCH" = "x86_64" ]; then
    echo "Building for Intel (x86_64) only"
else
    echo "No architecture specified, defaulting to universal binary"
    BUILD_UNIVERSAL=true
fi

# Build whisper.cpp with architecture flags
if [ ! -f "$WHISPER_PATH/build/src/libwhisper.dylib" ]; then
    echo "Building whisper.cpp library..."
    cd "$WHISPER_PATH"
    
    # Set architecture flags for cmake
    if [ "$BUILD_UNIVERSAL" = true ]; then
        # Build for both architectures
        CMAKE_OPTS="-DCMAKE_OSX_ARCHITECTURES='arm64;x86_64' -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
    elif [ "$BUILD_ARCH" = "arm64" ]; then
        CMAKE_OPTS="-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
    elif [ "$BUILD_ARCH" = "x86_64" ]; then
        CMAKE_OPTS="-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DWHISPER_COREML=OFF  -DGGML_METAL=OFF -DBUILD_SHARED_LIBS=OFF"
    else
        # Default to native architecture if not specified, still set deployment target
        CMAKE_OPTS="-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0"
    fi
    
    # Build with the appropriate architecture flags
    cmake -B build -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF $CMAKE_OPTS
    cmake --build build --config Release
else
    echo "whisper.cpp library already built. Use 'make clean' in the parent directory if you want to rebuild with different architecture settings."
fi

# Back to WhisperRecorder directory
cd "$WHISPER_PATH/WhisperRecorder"

# Create local libs directory
mkdir -p libs

# Copy whisper.cpp libraries to libs folder with better error messages
echo "Copying dynamic libraries..."

# Function to copy a library file with proper error handling
copy_lib() {
    src="$1"
    dest="libs/"
    if [ -f "$src" ]; then
        cp "$src" "$dest" && echo "✅ Copied $(basename $src)" || echo "❌ Failed to copy $(basename $src)"
        # Create symlink for version 1 if it doesn't exist
        base_name=$(basename "$src")
        if [[ ! "$base_name" == *".1.dylib" ]]; then
            ln -sf "$base_name" "libs/${base_name%.dylib}.1.dylib" 2>/dev/null || echo "ℹ️ Symlink for ${base_name%.dylib}.1.dylib already exists"
        fi
    else
        echo "❌ File not found: $src"
    fi
}

# Copy all required libraries
copy_lib "$WHISPER_PATH/build/src/libwhisper.dylib"
copy_lib "$WHISPER_PATH/build/ggml/src/libggml.dylib"
copy_lib "$WHISPER_PATH/build/ggml/src/libggml-base.dylib"
copy_lib "$WHISPER_PATH/build/ggml/src/libggml-cpu.dylib"
copy_lib "$WHISPER_PATH/build/ggml/src/ggml-metal/libggml-metal.dylib"
copy_lib "$WHISPER_PATH/build/ggml/src/ggml-blas/libggml-blas.dylib"

# Make sure necessary directories exist
mkdir -p Sources/CWhisper/include
mkdir -p include

# Create symlinks to necessary include directories
if [ ! -L "include" ]; then
    ln -sf ../include .
fi

# Copy the whisper_wrapper.h to the include directory
cp -f Sources/CWhisper/include/whisper_wrapper.h include/whisper_wrapper.h 2>/dev/null || echo "No header file to copy"

# Remove any old and potentially problematic files
rm -rf .build

# Set Swift build flags for architecture
SWIFT_BUILD_FLAGS="-c release"

if [ "$BUILD_UNIVERSAL" = true ]; then
    # Build for each architecture separately and then combine them
    echo "Building WhisperRecorder for arm64..."
    swift build $SWIFT_BUILD_FLAGS --arch arm64
    
    echo "Building WhisperRecorder for x86_64..."
    swift build $SWIFT_BUILD_FLAGS --arch x86_64
    
    # Create a universal binary by combining both architectures
    echo "Creating universal binary..."
    mkdir -p .build/universal
    lipo -create \
        .build/arm64-apple-macosx/release/WhisperRecorder \
        .build/x86_64-apple-macosx/release/WhisperRecorder \
        -output .build/universal/WhisperRecorder
    
    # Copy the universal binary to the current directory
    cp .build/universal/WhisperRecorder .
elif [ "$BUILD_ARCH" = "arm64" ]; then
    echo "Building WhisperRecorder for arm64..."
    swift build $SWIFT_BUILD_FLAGS --arch arm64
    cp .build/arm64-apple-macosx/release/WhisperRecorder .
elif [ "$BUILD_ARCH" = "x86_64" ]; then
    echo "Building WhisperRecorder for x86_64..."
    swift build $SWIFT_BUILD_FLAGS --arch x86_64
    cp .build/x86_64-apple-macosx/release/WhisperRecorder .
else
    # Default to native architecture if not specified
    echo "Building WhisperRecorder for native architecture..."
    swift build $SWIFT_BUILD_FLAGS
    cp .build/release/WhisperRecorder .
fi

# Check if build succeeded
if [ -f "./WhisperRecorder" ]; then
    # Create a simple shell script to run with proper library path
    cat > run_whisper.sh << 'EOF'
#!/bin/bash
# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Set the library path
export DYLD_LIBRARY_PATH="$DIR/libs:$DYLD_LIBRARY_PATH"
# Run the app
"$DIR/WhisperRecorder"
EOF
    chmod +x run_whisper.sh
    
    # Display architecture information of the built binary
    echo "Build completed successfully."
    echo "Binary architecture information:"
    lipo -info WhisperRecorder
    
    echo "Run './run_whisper.sh' to start the app."
else
    echo "Build failed. Check the error messages above."
fi