#!/bin/bash

# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Inform about on-demand model downloading
echo "ℹ️ WhisperRecorder will prompt you to download a model on first run."
echo "   You can select from tiny to large models based on your needs."

# Set the library path
export DYLD_LIBRARY_PATH="$DIR/libs:$DYLD_LIBRARY_PATH"

# Run the app
"$DIR/WhisperRecorder" 