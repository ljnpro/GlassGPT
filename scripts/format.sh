#!/usr/bin/env bash
set -euo pipefail

if ! command -v swiftformat &>/dev/null; then
    echo "Installing SwiftFormat..."
    brew install swiftformat
fi

mapfile -t swift_files < <(rg --files modules/native-chat/Sources modules/native-chat/Tests ios/GlassGPT -g '*.swift')

if [[ ${#swift_files[@]} -eq 0 ]]; then
    echo "No Swift files found to format."
    exit 0
fi

swiftformat --quiet "${swift_files[@]}" "$@"
