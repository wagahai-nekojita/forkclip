#!/bin/zsh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$WORKSPACE_ROOT/Forkclip.app}"
RELEASE_ENTITLEMENTS="${RELEASE_ENTITLEMENTS:-$PACKAGE_ROOT/Release.entitlements}"
RELEASE_CODESIGN_IDENTITY="${RELEASE_CODESIGN_IDENTITY:-}"
APPLY_RELEASE_SIGNING="${APPLY_RELEASE_SIGNING:-0}"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-0}"

skip_or_fail() {
  local reason="$1"
  if [[ "$REQUIRE_RELEASE_SIGNING" == "1" ]]; then
    echo "FAIL: $reason" >&2
    exit 1
  fi
  echo "SKIP: $reason"
  exit 0
}

if [[ ! -f "$RELEASE_ENTITLEMENTS" ]]; then
  echo "Missing release entitlements file: $RELEASE_ENTITLEMENTS" >&2
  exit 1
fi

plutil -lint "$RELEASE_ENTITLEMENTS" >/dev/null

echo "Release signing profile:"
echo "  app bundle: $APP_BUNDLE"
echo "  entitlements: $RELEASE_ENTITLEMENTS"
echo "  hardened runtime: codesign --options runtime"

if [[ -z "$RELEASE_CODESIGN_IDENTITY" ]]; then
  skip_or_fail "RELEASE_CODESIGN_IDENTITY is not set; release signing requires a Developer ID or Apple Distribution identity."
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  skip_or_fail "APP_BUNDLE does not exist; build it first with LAUNCH_APP=0 RUN_SMOKE=0 Forkclip/scripts/build-and-refresh-app.sh."
fi

if [[ "$APPLY_RELEASE_SIGNING" != "1" ]]; then
  skip_or_fail "APPLY_RELEASE_SIGNING=1 is required before mutating the app bundle with the release signature."
fi

echo "Signing app bundle with release identity: $RELEASE_CODESIGN_IDENTITY"
codesign --force \
  --options runtime \
  --entitlements "$RELEASE_ENTITLEMENTS" \
  --sign "$RELEASE_CODESIGN_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" >/dev/null
echo "Release signing check passed."
