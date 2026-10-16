#!/bin/bash
set -e

echo "=================================================="
echo " Building DriveCine Pro (macOS Apple Silicon App)"
echo "=================================================="

APP_NAME="DriveCine"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 1. Clean and create bundle directories
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" ".cache/clang"

# 2. Copy Info.plist and Resources
echo "-> Copying resources..."
cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"
if [ -f Resources/AppIcon.png ]; then
    cp Resources/AppIcon.png "${RESOURCES_DIR}/AppIcon.png"
fi

# 3. Compile native Apple Silicon binary
echo "-> Compiling Swift sources for arm64..."
swiftc -parse-as-library \
  -module-cache-path "$PWD/.cache/clang" \
  -target arm64-apple-macosx14.0 \
  -O \
  -lsqlite3 \
  -framework Security \
  -framework CryptoKit \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  Sources/Main.swift \
  Sources/Models/*.swift \
  Sources/Storage/*.swift \
  Sources/Network/*.swift \
  Sources/Views/*.swift \
  Sources/Views/Components/*.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

# 4. Ad-hoc codesign the application bundle
echo "-> Signing application bundle..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "=================================================="
echo " Build Succeeded!"
echo " App location: ${PWD}/${BUNDLE_DIR}"
echo " Launch with: open '${BUNDLE_DIR}'"
echo "=================================================="
