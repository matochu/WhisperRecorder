#!/bin/bash
# Get the directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Set the library path
export DYLD_LIBRARY_PATH="$DIR/libs:$DYLD_LIBRARY_PATH"
# Run the app
"$DIR/WhisperRecorder"
