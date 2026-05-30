#!/bin/zsh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_PATH="${SCRATCH_PATH:-/tmp/forkclip-focused-state-performance-build}"

cd "$PACKAGE_ROOT"
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 \
  swift test \
  --scratch-path "$SCRATCH_PATH" \
  --filter FocusedStatePerformanceTests
