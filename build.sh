#!/bin/bash

# Set app name
APP_NAME="KT Locker"

# Set output directory
OUTPUT_DIR="."

# Clean up previous build
echo "Cleaning previous build..."
rm -rf "${OUTPUT_DIR}/${APP_NAME}.app"

# Create app bundle structure
mkdir -p "${OUTPUT_DIR}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/${APP_NAME}.app/Contents/Resources"

# Create Info.plist with correct icon settings
cat > "${OUTPUT_DIR}/${APP_NAME}.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.ktlocker</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF

echo "Building ${APP_NAME}..."

# Copy our Apple-spec icon
echo "Copying Apple-spec icon..."
cp AppleIcon.icns "${OUTPUT_DIR}/${APP_NAME}.app/Contents/Resources/AppIcon.icns"

# Compile Swift files
echo "Compiling Swift files..."
xcrun swiftc main.swift Classes/*.swift \
    -o "${OUTPUT_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" \
    -framework Cocoa \
    -framework ApplicationServices

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    # Make executable
    chmod +x "${OUTPUT_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

    # Create PkgInfo
    echo "APPL????" > "${OUTPUT_DIR}/${APP_NAME}.app/Contents/PkgInfo"

    # Fix permissions and clean extended attributes
    echo "Setting correct permissions and attributes..."
    xattr -cr "${OUTPUT_DIR}/${APP_NAME}.app"

    # Clear icon caches thoroughly
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${OUTPUT_DIR}/${APP_NAME}.app"

    # Update modification times to refresh caches
    touch "${OUTPUT_DIR}/${APP_NAME}.app"
    touch "${OUTPUT_DIR}/${APP_NAME}.app/Contents/Info.plist"

    echo "Build successful!"
    echo "Run the application with: open \"${APP_NAME}.app\""
    echo "Note: You will need to grant accessibility permissions when prompted."
else
    echo "Build failed!"
    exit 1
fi
