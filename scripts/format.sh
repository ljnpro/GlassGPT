#!/usr/bin/env bash
set -euo pipefail

if ! command -v swiftformat &>/dev/null; then
    echo "Installing SwiftFormat..."
    brew install swiftformat
fi

swiftformat modules/native-chat/Sources modules/native-chat/Tests ios/GlassGPT "$@"
