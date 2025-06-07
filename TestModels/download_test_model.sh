#!/bin/bash

# WhisperRecorder Test Model Download Script
# Downloads lightweight Whisper model for automated testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🤖 Whisper Test Model Download${NC}"
echo "================================="

# Model configuration
MODEL_NAME="ggml-tiny.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
MODEL_DIR="$(pwd)/TestModels"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
INSTRUCTIONS_FILE="$MODEL_DIR/MODEL_INFO.txt"

# Create model directory
mkdir -p "$MODEL_DIR"

# Check if model already exists
if [ -f "$MODEL_PATH" ]; then
    echo -e "${GREEN}✅ Test model already exists: $MODEL_NAME${NC}"
    echo "   Size: $(du -h "$MODEL_PATH" | cut -f1)"
    echo "   Path: $MODEL_PATH"
    exit 0
fi

echo -e "${YELLOW}📥 Downloading Whisper tiny.en model for testing...${NC}"
echo "   Model: $MODEL_NAME (~39MB)"
echo "   URL: $MODEL_URL"
echo "   Destination: $MODEL_PATH"
echo ""

# Download model with progress
echo -e "${BLUE}🌐 Starting download...${NC}"
if command -v curl &> /dev/null; then
    curl -L --progress-bar -o "$MODEL_PATH" "$MODEL_URL" || {
        echo -e "${RED}❌ Failed to download model with curl${NC}"
        rm -f "$MODEL_PATH"
        exit 1
    }
elif command -v wget &> /dev/null; then
    wget --progress=bar:force:noscroll -O "$MODEL_PATH" "$MODEL_URL" || {
        echo -e "${RED}❌ Failed to download model with wget${NC}"
        rm -f "$MODEL_PATH"
        exit 1
    }
else
    echo -e "${RED}❌ Error: Neither curl nor wget found${NC}"
    echo "Please install curl or wget to download test model"
    exit 1
fi

# Verify download
if [ ! -f "$MODEL_PATH" ]; then
    echo -e "${RED}❌ Model download failed${NC}"
    exit 1
fi

# Check file size (should be around 39MB)
MODEL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || stat -c%s "$MODEL_PATH" 2>/dev/null)
if [ "$MODEL_SIZE" -lt 30000000 ]; then  # Less than 30MB indicates incomplete download
    echo -e "${RED}❌ Downloaded model appears incomplete (${MODEL_SIZE} bytes)${NC}"
    rm -f "$MODEL_PATH"
    exit 1
fi

echo -e "${GREEN}✅ Model downloaded successfully!${NC}"
echo "   File: $MODEL_NAME"
echo "   Size: $(du -h "$MODEL_PATH" | cut -f1)"
echo "   Location: $MODEL_PATH"

# Create instructions file
cat > "$INSTRUCTIONS_FILE" << EOF
# WhisperRecorder Test Model Information

**Model**: ggml-tiny.en.bin
**Size**: ~39MB
**Language**: English only
**Quality**: Low (for testing only)
**Source**: Hugging Face (ggerganov/whisper.cpp)
**URL**: $MODEL_URL

## Usage in Tests

This model is automatically downloaded for testing purposes only.
It provides fast, lightweight transcription for test validation.

**DO NOT** use this model for production - it's optimized for speed, not accuracy.

## Cleanup

This model is automatically deleted after test completion to save space.
Run \`./download_test_model.sh\` to re-download if needed.

Downloaded: $(date)
Path: $MODEL_PATH
EOF

echo ""
echo -e "${BLUE}📋 Model Information:${NC}"
echo "   • Tiny English-only model (~39MB)"
echo "   • Fast processing for testing"
echo "   • Low quality (testing only)"
echo "   • Auto-cleanup after tests"
echo ""
echo -e "${GREEN}🚀 Ready for testing!${NC}" 