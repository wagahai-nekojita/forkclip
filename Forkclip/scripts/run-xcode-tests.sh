#!/bin/zsh
set -euo pipefail

XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$XCODE_DEVELOPER_DIR" ]]; then
  echo "Xcode.app not found at /Applications/Xcode.app" >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"

if ! xcrun --sdk macosx --show-sdk-platform-path >/dev/null; then
  echo "Xcode SDK platform path is unavailable; XCTest cannot be run." >&2
  exit 1
fi

exec xcrun swift test \
  --enable-xctest \
  --disable-swift-testing \
  --package-path "$PACKAGE_ROOT" \
  --scratch-path /tmp/forkclip-xcode-test-build
