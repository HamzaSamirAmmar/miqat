#!/bin/bash
# Builds and launches "Miqat Dev": a Debug build with its own bundle id
# (personal.hamza.miqat.dev), so it runs beside the installed Miqat and keeps
# separate settings and notification permissions. Nothing is installed.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="$PWD/.build/dev"
APP="$BUILD_DIR/Build/Products/Debug/Miqat Dev.app"

xcodebuild -project Miqat.xcodeproj -scheme Miqat -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  PRODUCT_BUNDLE_IDENTIFIER=personal.hamza.miqat.dev \
  PRODUCT_NAME="Miqat Dev" \
  build | tail -3

pkill -f "Miqat Dev.app/Contents/MacOS" 2>/dev/null || true
while pgrep -f "Miqat Dev.app/Contents/MacOS" >/dev/null; do sleep 0.2; done
open "$APP"
