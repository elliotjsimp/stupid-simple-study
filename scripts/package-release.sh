#!/bin/bash
# Package Stupid Simple Study v0.1.0 for GitHub Releases.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project stupid-simple-study.xcodeproj \
  -scheme stupid-simple-study \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath ./build/DerivedData \
  build

APP_PATH="./build/DerivedData/Build/Products/Release/Stupid Simple Study.app"
ZIP_NAME="stupid-simple-study-v0.1.0-macos.zip"

ditto -c -k --keepParent "$APP_PATH" "./build/$ZIP_NAME"
echo "Created ./build/$ZIP_NAME"
