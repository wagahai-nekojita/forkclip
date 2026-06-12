#!/bin/zsh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$WORKSPACE_ROOT/Forkclip.app}"
APP_CONTENTS_DIR="$APP_BUNDLE/Contents"
APP_MACOS_DIR="$APP_CONTENTS_DIR/MacOS"
APP_BINARY="$APP_MACOS_DIR/Forkclip"
APP_INFO_PLIST="$APP_CONTENTS_DIR/Info.plist"
APP_RESOURCES_DIR="$APP_CONTENTS_DIR/Resources"
APP_USER_DOCS_DIR="$APP_RESOURCES_DIR/ForkclipUserDocs"
REGISTERED_APP="${REGISTERED_APP:-/Applications/Forkclip.app}"
AUTO_UPDATE_REGISTERED_APP="${AUTO_UPDATE_REGISTERED_APP:-1}"
LAUNCH_APP="${LAUNCH_APP:-1}"
RUN_SMOKE="${RUN_SMOKE:-1}"
CODESIGN_APP="${CODESIGN_APP:-1}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_STARTUP_SETTLE_SECONDS="${APP_STARTUP_SETTLE_SECONDS:-7}"
SCRATCH_PATH="${SCRATCH_PATH:-/tmp/forkclip-build}"
BUILD_BINARY="$SCRATCH_PATH/debug/Forkclip"
BUILD_RESOURCE_BUNDLE="$SCRATCH_PATH/debug/Forkclip_Forkclip.bundle"
APP_SWIFTPM_RESOURCE_BUNDLE="$APP_BUNDLE/Forkclip_Forkclip.bundle"
APP_PROCESS_PATTERN="$APP_BINARY|Forkclip.app/Contents/MacOS/Forkclip"
ASSET_ROOT="$PACKAGE_ROOT/Assets"
PACKAGE_INFO_PLIST="$PACKAGE_ROOT/Info.plist"
USER_DOCS_DIR="$WORKSPACE_ROOT/docs/user"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

plist_value() {
  local plist="$1"
  local key="$2"
  if [[ -f "$plist" ]]; then
    "$PLIST_BUDDY" -c "Print :$key" "$plist" 2>/dev/null || true
  fi
}

bundle_version() {
  local plist="$1"
  local short_version
  local build_version
  short_version="$(plist_value "$plist" "CFBundleShortVersionString")"
  build_version="$(plist_value "$plist" "CFBundleVersion")"
  echo "${short_version:-unknown} (${build_version:-unknown})"
}

bundle_path_differs() {
  local source_path="$1"
  local target_path="$2"

  if [[ ! -e "$source_path" && ! -e "$target_path" ]]; then
    return 1
  fi

  if [[ ! -e "$source_path" || ! -e "$target_path" ]]; then
    return 0
  fi

  if [[ -d "$source_path" || -d "$target_path" ]]; then
    if [[ ! -d "$source_path" || ! -d "$target_path" ]]; then
      return 0
    fi

    if ! diff -qr "$source_path" "$target_path" >/dev/null; then
      return 0
    fi
    return 1
  fi

  if ! cmp -s "$source_path" "$target_path"; then
    return 0
  fi
  return 1
}

binary_hash() {
  shasum -a 256 "$1" | awk '{print $1}'
}

process_binary_path() {
  local pid="$1"
  local command
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  echo "${command%% *}"
}

running_forkclip_pids() {
  pgrep -f 'Forkclip.app/Contents/MacOS/Forkclip' || true
}

running_binary_matches_build() {
  local binary="$1"
  [[ -x "$binary" ]] || return 1
  [[ "$(binary_hash "$binary")" == "$(binary_hash "$APP_BINARY")" ]]
}

find_current_running_app() {
  local pid
  local binary
  for pid in $(running_forkclip_pids); do
    binary="$(process_binary_path "$pid")"
    if running_binary_matches_build "$binary"; then
      echo "$pid $binary"
      return 0
    fi
  done
  return 1
}

print_running_forkclip_apps() {
  local pid
  local binary
  local hash
  for pid in $(running_forkclip_pids); do
    binary="$(process_binary_path "$pid")"
    if [[ -x "$binary" ]]; then
      hash="$(binary_hash "$binary")"
    else
      hash="unreadable"
    fi
    echo "Running Forkclip pid=$pid binary=$binary hash=$hash"
  done
}

registered_app_needs_update() {
  local -a tracked_paths=(
    "Contents/MacOS/Forkclip"
    "Contents/Info.plist"
    "Contents/Resources/AppIcon.icns"
    "Contents/Resources/AppMenuIconTemplate.png"
    "Contents/Resources/ClipboardFeedbackClick.wav"
    "Contents/Resources/ForkclipUserDocs"
    "Forkclip_Forkclip.bundle"
  )

  local relative_path
  for relative_path in "${tracked_paths[@]}"; do
    if bundle_path_differs "$APP_BUNDLE/$relative_path" "$REGISTERED_APP/$relative_path"; then
      echo "Registered app differs at $relative_path"
      return 0
    fi
  done

  return 1
}

update_registered_app_if_needed() {
  if [[ "$AUTO_UPDATE_REGISTERED_APP" != "1" ]]; then
    echo "Registered app auto-update disabled."
    return
  fi

  if [[ ! -d "$REGISTERED_APP" ]]; then
    echo "Registered app not found; skipping auto-update: $REGISTERED_APP"
    return
  fi

  local source_version
  local registered_version
  source_version="$(bundle_version "$APP_INFO_PLIST")"
  registered_version="$(bundle_version "$REGISTERED_APP/Contents/Info.plist")"

  if ! registered_app_needs_update; then
    echo "Registered app already current: $REGISTERED_APP $registered_version"
    return
  fi

  echo "Updating registered app: $REGISTERED_APP ($registered_version -> $source_version)"
  SOURCE_APP="$APP_BUNDLE" TARGET_APP="$REGISTERED_APP" "$PACKAGE_ROOT/scripts/install-to-applications.sh"
}

sign_app_bundle_if_needed() {
  if [[ "$CODESIGN_APP" != "1" ]]; then
    echo "Skipping app bundle signing."
    return
  fi

  echo "Signing app bundle with identity: $CODESIGN_IDENTITY"
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR"

echo "Building Forkclip..."
(
  cd "$PACKAGE_ROOT"
  env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 swift build --scratch-path "$SCRATCH_PATH"
)

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Built binary not found: $BUILD_BINARY" >&2
  exit 1
fi
if [[ ! -d "$BUILD_RESOURCE_BUNDLE" ]]; then
  echo "SwiftPM resource bundle not found: $BUILD_RESOURCE_BUNDLE" >&2
  exit 1
fi

existing_pid="$(pgrep -af "$APP_PROCESS_PATTERN" | awk 'NR==1 {print $1}' || true)"
if [[ -n "${existing_pid:-}" ]]; then
  echo "Stopping running app: $existing_pid"
  kill "$existing_pid"
  sleep 1
fi

echo "Refreshing app bundle..."
mkdir -p "$APP_RESOURCES_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$PACKAGE_INFO_PLIST" "$APP_INFO_PLIST"
if [[ -f "$ASSET_ROOT/AppIcon.icns" ]]; then
  cp "$ASSET_ROOT/AppIcon.icns" "$APP_RESOURCES_DIR/AppIcon.icns"
fi
if [[ -f "$ASSET_ROOT/AppMenuIconTemplate.png" ]]; then
  cp "$ASSET_ROOT/AppMenuIconTemplate.png" "$APP_RESOURCES_DIR/AppMenuIconTemplate.png"
fi
if [[ -f "$ASSET_ROOT/ClipboardFeedbackClick.wav" ]]; then
  cp "$ASSET_ROOT/ClipboardFeedbackClick.wav" "$APP_RESOURCES_DIR/ClipboardFeedbackClick.wav"
fi
ditto "$BUILD_RESOURCE_BUNDLE" "$APP_SWIFTPM_RESOURCE_BUNDLE"
if [[ -d "$USER_DOCS_DIR" ]]; then
  echo "Bundling user docs..."
  mkdir -p "$APP_USER_DOCS_DIR"
  ditto "$USER_DOCS_DIR" "$APP_USER_DOCS_DIR"
else
  echo "User docs not found; skipping docs bundle."
fi

sign_app_bundle_if_needed
update_registered_app_if_needed

if [[ "$LAUNCH_APP" == "1" ]]; then
  echo "Launching refreshed app..."
  if ! open "$APP_BUNDLE"; then
    echo "LaunchServices launch failed; falling back to direct binary execution."
    nohup "$APP_BINARY" >/tmp/forkclip-app.stdout.log 2>/tmp/forkclip-app.stderr.log < /dev/null &
  fi

  app_pid=""
  running_binary=""
  for _ in $(seq 1 10); do
    current_app="$(find_current_running_app || true)"
    if [[ -n "$current_app" ]]; then
      app_pid="${current_app%% *}"
      running_binary="${current_app#* }"
      break
    fi
    sleep 1
  done

  if [[ -z "$app_pid" ]]; then
    echo "App failed to stay running with the refreshed binary after launch." >&2
    echo "Expected binary hash: $(binary_hash "$APP_BINARY") ($APP_BINARY)" >&2
    print_running_forkclip_apps >&2
    exit 1
  fi

  echo "Running app verified: pid=$app_pid binary=$running_binary"

  sleep "$APP_STARTUP_SETTLE_SECONDS"
else
  echo "Skipping app launch."
fi

if [[ "$RUN_SMOKE" == "1" ]]; then
  echo "Running smoke check..."
  "$PACKAGE_ROOT/scripts/smoke-check.sh" "${1:-build-refresh-smoke}"
else
  echo "Skipping smoke check."
fi

echo "Build refresh completed successfully."
