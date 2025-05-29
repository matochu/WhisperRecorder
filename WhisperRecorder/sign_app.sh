#!/bin/bash
set -e

APP_NAME="WhisperRecorder.app"

# Check if the app exists
if [ ! -d "$APP_NAME" ]; then
    echo "❌ Error: $APP_NAME not found. Run package_app.sh first."
    exit 1
fi

# Check if developer identity is provided
if [ -z "$1" ]; then
    echo "⚠️ No signing identity provided. You can run this script with your Developer ID to sign the app:"
    echo "./sign_app.sh \"Developer ID Application: Your Name (TEAMID)\""
    echo ""
    echo "Available signing identities:"
    security find-identity -v -p codesigning
    echo ""
    echo "⚠️ Creating unsigned distributable package..."
    
    # Create zip without signing
    zip -r WhisperRecorder.zip "$APP_NAME"
    echo "✅ Created unsigned WhisperRecorder.zip"
    exit 0
fi

IDENTITY="$1"
echo "➡️ Signing $APP_NAME with identity: $IDENTITY"

# Sign all the dylib files in the Frameworks directory
find "$APP_NAME/Contents/Frameworks" -name "*.dylib" -exec codesign --force --sign "$IDENTITY" --options runtime {} \;

# Sign the main executable
codesign --force --sign "$IDENTITY" --options runtime --entitlements entitlements.plist "$APP_NAME/Contents/MacOS/WhisperRecorder.bin"
codesign --force --sign "$IDENTITY" --options runtime --entitlements entitlements.plist "$APP_NAME/Contents/MacOS/WhisperRecorder.sh"
codesign --force --sign "$IDENTITY" --options runtime --entitlements entitlements.plist "$APP_NAME/Contents/MacOS/WhisperRecorder"

# Sign the app bundle
codesign --force --deep --sign "$IDENTITY" --options runtime --entitlements entitlements.plist "$APP_NAME"

# Verify the signature
echo "✅ Verifying signature..."
codesign --verify --verbose "$APP_NAME"

# Create a dmg file for distribution
echo "➡️ Creating distributable dmg..."
hdiutil create -volname "WhisperRecorder" -srcfolder "$APP_NAME" -ov -format UDZO "WhisperRecorder.dmg"

echo "✅ App signed and packaged as WhisperRecorder.dmg"
echo ""
echo "Note: For distribution outside the App Store, you may want to notarize the app."
echo "See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution" 

codesign --verify --deep --strict --verbose=2 "$APP_NAME"