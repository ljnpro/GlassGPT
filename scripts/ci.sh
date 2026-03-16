#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

echo "==> Building app"
xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "==> Testing package"
xcodebuild \
  -project ios/GlassGPT.xcodeproj \
  -scheme GlassGPT \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
