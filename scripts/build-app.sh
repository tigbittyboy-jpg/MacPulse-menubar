#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "MacPulse.app must be built on macOS with Xcode 15 or later." >&2
  exit 1
fi
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p build
# Replace only our generated bundle; never modify installed applications.
if [[ -e build/MacPulse.app ]]; then rm -rf build/MacPulse.app; fi
ditto build/DerivedData/Build/Products/Release/MacPulse.app build/MacPulse.app
mkdir -p build/MacPulse.app/Contents/Resources
swift scripts/make-icon.swift build
iconutil -c icns build/MacPulse.iconset -o build/MacPulse.app/Contents/Resources/MacPulse.icns
codesign --force --sign - build/MacPulse.app
codesign --verify --strict build/MacPulse.app
echo "Built build/MacPulse.app. Drag it to Applications, then open it."
