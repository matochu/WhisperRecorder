#!/bin/bash

# Setup script for WhisperRecorder Speaker Diarization
# Installs Python dependencies for pyannote.audio integration

set -e  # Exit on any error

echo "🎤 Setting up Speaker Diarization for WhisperRecorder"
echo "=================================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed!"
    echo "📥 Please install Python 3 first:"
    echo "   brew install python3"
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Check if pip is available
if ! python3 -m pip --version &> /dev/null; then
    echo "❌ pip is not available!"
    echo "📥 Please install pip first"
    exit 1
fi

echo "✅ pip found: $(python3 -m pip --version)"

# Check if requirements.txt exists
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "❌ requirements.txt not found at: $REQUIREMENTS_FILE"
    exit 1
fi

# Create virtual environment (optional but recommended)
VENV_DIR="$SCRIPT_DIR/../.venv_speaker_diarization"

if [ ! -d "$VENV_DIR" ]; then
    echo "🐍 Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

echo "🔄 Activating virtual environment..."
source "$VENV_DIR/bin/activate"

echo "📦 Installing Python dependencies..."
pip install --upgrade pip
pip install -r "$REQUIREMENTS_FILE"

echo ""
echo "✅ Speaker Diarization setup completed!"
echo ""
echo "📋 Summary:"
echo "   - Virtual environment: $VENV_DIR"
echo "   - Python script: $SCRIPT_DIR/speaker_diarization.py"
echo "   - Dependencies installed from: $REQUIREMENTS_FILE"
echo ""
echo "🧪 To test the installation:"
echo "   source $VENV_DIR/bin/activate"
echo "   python3 $SCRIPT_DIR/speaker_diarization.py --help"
echo ""
echo "⚠️  Note: First run may be slow as it downloads models from HuggingFace"
echo "   You may need to accept the pyannote license at:"
echo "   https://huggingface.co/pyannote/speaker-diarization-3.1"
echo ""
echo "🎯 To use in WhisperRecorder:"
echo "   1. Enable 'Speakers' in Configuration Card"
echo "   2. Record audio with multiple speakers"
echo "   3. Enjoy speaker-labeled transcriptions!"

deactivate 