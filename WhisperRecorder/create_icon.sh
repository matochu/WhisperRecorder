#!/bin/bash
set -e

echo "➡️ Creating app icon for WhisperRecorder..."

# Create icon directory structure
ICON_SET="AppIcon.iconset"
mkdir -p "$ICON_SET"

# Create a basic SVG icon - a simple waveform symbol
cat > waveform.svg << 'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <rect width="1024" height="1024" rx="200" ry="200" fill="#4a86e8"/>
  <path d="M512 212c-33.1 0-60 26.9-60 60v480c0 33.1 26.9 60 60 60s60-26.9 60-60V272c0-33.1-26.9-60-60-60zm-180 120c-33.1 0-60 26.9-60 60v240c0 33.1 26.9 60 60 60s60-26.9 60-60V392c0-33.1-26.9-60-60-60zm360 0c-33.1 0-60 26.9-60 60v240c0 33.1 26.9 60 60 60s60-26.9 60-60V392c0-33.1-26.9-60-60-60zm-540 60c-33.1 0-60 26.9-60 60v120c0 33.1 26.9 60 60 60s60-26.9 60-60V452c0-33.1-26.9-60-60-60zm720 0c-33.1 0-60 26.9-60 60v120c0 33.1 26.9 60 60 60s60-26.9 60-60V452c0-33.1-26.9-60-60-60z" fill="white"/>
</svg>
EOF

# Check if qlmanage is available for converting SVG to PNG
if command -v qlmanage &> /dev/null; then
    # Generate PNGs at different sizes using qlmanage
    for size in 16 32 64 128 256 512 1024; do
        qlmanage -t -s $size -o . waveform.svg &> /dev/null
        mv waveform.svg.png "$ICON_SET/icon_${size}x${size}.png"
    done
else
    echo "⚠️ qlmanage not found. Please install command line tools or manually create icon images."
    exit 1
fi

# Create the iconset with the required file names - avoid duplicate copies
mv "$ICON_SET/icon_32x32.png" "$ICON_SET/icon_16x16@2x.png"
mv "$ICON_SET/icon_64x64.png" "$ICON_SET/icon_32x32@2x.png"
mv "$ICON_SET/icon_256x256.png" "$ICON_SET/icon_128x128@2x.png"
mv "$ICON_SET/icon_512x512.png" "$ICON_SET/icon_256x256@2x.png"
mv "$ICON_SET/icon_1024x1024.png" "$ICON_SET/icon_512x512@2x.png"

# Generate new images for the missing sizes
qlmanage -t -s 16 -o . waveform.svg &> /dev/null
mv waveform.svg.png "$ICON_SET/icon_16x16.png"
qlmanage -t -s 32 -o . waveform.svg &> /dev/null
mv waveform.svg.png "$ICON_SET/icon_32x32.png"
qlmanage -t -s 128 -o . waveform.svg &> /dev/null
mv waveform.svg.png "$ICON_SET/icon_128x128.png"
qlmanage -t -s 256 -o . waveform.svg &> /dev/null
mv waveform.svg.png "$ICON_SET/icon_256x256.png"
qlmanage -t -s 512 -o . waveform.svg &> /dev/null
mv waveform.svg.png "$ICON_SET/icon_512x512.png"

# Convert the iconset to icns file
if command -v iconutil &> /dev/null; then
    iconutil -c icns "$ICON_SET"
    echo "✅ Created AppIcon.icns"
else
    echo "⚠️ iconutil not found. Please run this script on macOS to generate the icns file."
    exit 1
fi

# Clean up
rm -rf "$ICON_SET" 