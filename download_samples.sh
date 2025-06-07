#!/bin/bash

# Download audio samples for WhisperRecorder testing
# Based on whisper.cpp samples infrastructure

set -e

echo "Downloading audio samples for testing..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is required but not installed. Please install it first:"
    echo "brew install ffmpeg"
    exit 1
fi

# Download original samples
echo "Downloading George W. Bush radio address..."
curl -L --progress-bar -o gb0.ogg "https://upload.wikimedia.org/wikipedia/commons/2/22/George_W._Bush%27s_weekly_radio_address_%28November_1%2C_2008%29.oga"

echo "Downloading George W. Bush Columbia speech..."
curl -L --progress-bar -o gb1.ogg "https://upload.wikimedia.org/wikipedia/commons/1/1f/George_W_Bush_Columbia_FINAL.ogg"

echo "Downloading Henry Phillips speech..."
curl -L --progress-bar -o hp0.ogg "https://upload.wikimedia.org/wikipedia/en/d/d4/En.henryfphillips.ogg"

echo "Downloading Micro Machines sample..."
curl -L --progress-bar -o mm1.wav "https://cdn.openai.com/whisper/draft-20220913a/micro-machines.wav"

echo "Downloading JFK sample..."
curl -L --progress-bar -o jfk.wav "https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav"

echo "Converting to 16-bit WAV 16kHz mono format..."

# Convert all files to required format: 16kHz mono PCM s16le
ffmpeg -loglevel error -y -i gb0.ogg -ar 16000 -ac 1 -c:a pcm_s16le gb0.wav
ffmpeg -loglevel error -y -i gb1.ogg -ar 16000 -ac 1 -c:a pcm_s16le gb1.wav  
ffmpeg -loglevel error -y -i hp0.ogg -ar 16000 -ac 1 -c:a pcm_s16le hp0.wav
ffmpeg -loglevel error -y -i mm1.wav -ar 16000 -ac 1 -c:a pcm_s16le mm0.wav

# JFK is already in WAV, but let's ensure it's in the right format
ffmpeg -loglevel error -y -i jfk.wav -ar 16000 -ac 1 -c:a pcm_s16le jfk_16k.wav

# Clean up original downloads
rm -f gb0.ogg gb1.ogg hp0.ogg mm1.wav jfk.wav

# Rename files to match our test expectations
mv gb0.wav hello_world.wav          # "And so my fellow Americans, ask not what your country can do for you..."
mv gb1.wav clear_speech.wav         # Clear presidential speech
mv hp0.wav counting.wav              # English speech sample
mv mm0.wav micro_machines.wav        # Fast speech sample
mv jfk_16k.wav jfk_original.wav      # JFK speech

echo ""
echo "Audio samples downloaded and converted successfully!"
echo ""
echo "Available test files:"
ls -la *.wav | while read -r line; do
    file=$(echo "$line" | awk '{print $NF}')
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null | cut -d. -f1)
    echo "  $file (${duration}s)"
done

echo ""
echo "Files are ready for WhisperRecorder testing!"
echo "Run './whisper test real' to execute the real audio tests." 