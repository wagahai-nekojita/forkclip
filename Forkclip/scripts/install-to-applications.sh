#!/bin/zsh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
SOURCE_APP="${SOURCE_APP:-$WORKSPACE_ROOT/Forkclip.app}"
TARGET_APP="${TARGET_APP:-/Applications/Forkclip.app}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Source app bundle not found: $SOURCE_APP" >&2
  exit 1
fi

echo "Installing $SOURCE_APP to $TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
touch "$TARGET_APP"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
fi
echo "Installed to /Applications successfully."
