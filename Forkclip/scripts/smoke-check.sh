#!/bin/zsh
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
APP_BINARY="${APP_BINARY:-$WORKSPACE_ROOT/Forkclip.app/Contents/MacOS/Forkclip}"
DB_PATH="${DB_PATH:-$HOME/Library/Application Support/Forkclip/forkclip.sqlite}"
LOG_PREDICATE='subsystem == "com.user.forkclip"'
TEST_VALUE="${1:-codex-smoke-$(date +%Y%m%d-%H%M%S)}"
SMOKE_MODE="${FORKCLIP_SMOKE_MODE:-plainText}"
POLL_RETRIES="${POLL_RETRIES:-10}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
RUN_NATIVE_UI_SMOKE="${RUN_NATIVE_UI_SMOKE:-1}"

if [[ ! -x "$APP_BINARY" ]]; then
  echo "App binary not found: $APP_BINARY" >&2
  exit 1
fi

read_count() {
  if [[ ! -f "$DB_PATH" ]]; then
    echo 0
    return
  fi
  sqlite3 "$DB_PATH" 'select count(*) from clipboard_items;'
}

read_latest_payload() {
  if [[ ! -f "$DB_PATH" ]]; then
    echo ""
    return
  fi
  sqlite3 "$DB_PATH" 'select substr(content, 1, 32) from clipboard_items order by timestamp desc limit 1;'
}

read_latest_primary_type() {
  if [[ ! -f "$DB_PATH" ]]; then
    echo ""
    return
  fi
  sqlite3 "$DB_PATH" 'select primary_content_type from clipboard_items order by timestamp desc limit 1;'
}

read_latest_payload_types() {
  if [[ ! -f "$DB_PATH" ]]; then
    echo ""
    return
  fi
  sqlite3 "$DB_PATH" "select group_concat(content_type, ',') from (select p.content_type from clipboard_payloads p where p.item_id = (select id from clipboard_items order by timestamp desc limit 1) order by p.rank asc);"
}

seed_image_clipboard() {
  local mode="$1"
  local value="$2"
  local seed_script
  seed_script="$(mktemp "${TMPDIR:-/tmp}/forkclip-seed-image.XXXXXX")"
  cat > "$seed_script" <<'SWIFT'
import AppKit

let mode = CommandLine.arguments[1]
let value = CommandLine.arguments[2]
let pasteboard = NSPasteboard.general

func makeSmokeImage() -> (image: NSImage, pngData: Data) {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("failed to create PNG smoke payload")
    }
    return (image, pngData)
}

let smokeImage = makeSmokeImage()
pasteboard.clearContents()
if mode == "mixedImageFileURL" {
    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("forkclip-smoke-\(UUID().uuidString).png")
    do {
        try smokeImage.pngData.write(to: fileURL)
    } catch {
        fatalError("failed to write temporary image file: \(error)")
    }
    guard pasteboard.writeObjects([fileURL as NSURL, smokeImage.image]) else {
        fatalError("failed to seed mixed image/file URL pasteboard")
    }
} else {
    guard pasteboard.writeObjects([smokeImage.image]) else {
        fatalError("failed to seed image pasteboard")
    }
}
print("Clipboard seeded: \(mode)")
SWIFT
  if ! swift "$seed_script" "$mode" "$value"; then
    rm -f "$seed_script"
    return 1
  fi
  rm -f "$seed_script"
}

seed_clipboard() {
  case "$SMOKE_MODE" in
    plainText)
      pbcopy <<< "$TEST_VALUE"
      echo "Clipboard seeded: $TEST_VALUE"
      ;;
    image|mixedImageFileURL)
      seed_image_clipboard "$SMOKE_MODE" "$TEST_VALUE"
      ;;
    *)
      echo "Unknown FORKCLIP_SMOKE_MODE: $SMOKE_MODE" >&2
      exit 1
      ;;
  esac
}

verify_latest_item() {
  local latest_primary
  local latest_payload_types
  latest_primary="$(read_latest_primary_type)"
  latest_payload_types="$(read_latest_payload_types)"
  echo "Latest primary type: $latest_primary"
  echo "Latest payload types: $latest_payload_types"

  case "$SMOKE_MODE" in
    plainText)
      if [[ "$latest_primary" != "plainText" ]]; then
        echo "Smoke check failed: expected latest primary_content_type=plainText." >&2
        exit 1
      fi
      ;;
    image)
      if [[ "$latest_primary" != "image" || "$latest_payload_types" != *"image"* ]]; then
        echo "Smoke check failed: expected latest image item." >&2
        exit 1
      fi
      ;;
    mixedImageFileURL)
      if [[ "$latest_primary" != "image" || "$latest_payload_types" != *"image"* || "$latest_payload_types" != *"fileURL"* ]]; then
        echo "Smoke check failed: expected latest mixed image/fileURL item." >&2
        exit 1
      fi
      ;;
  esac
}

before_count="$(read_count)"
echo "DB count before: $before_count"
echo "Smoke mode: $SMOKE_MODE"
seed_clipboard

after_count="$before_count"
for _ in $(seq 1 "$POLL_RETRIES"); do
  sleep "$POLL_INTERVAL"
  after_count="$(read_count)"
  if [[ "$after_count" -gt "$before_count" ]]; then
    break
  fi
done

echo "DB count after: $after_count"
if [[ "$after_count" -le "$before_count" ]]; then
  echo "Smoke check failed: clipboard_items count did not increase." >&2
  /usr/bin/log show --last 5m --predicate "$LOG_PREDICATE" --style compact | tail -n 20 >&2 || true
  exit 1
fi

verify_latest_item

if security find-generic-password -s "com.user.forkclip.encryption" -a "symmetricKey" >/dev/null 2>&1; then
  echo "Keychain status: present"
else
  echo "Keychain status: missing" >&2
  exit 1
fi

if [[ "$RUN_NATIVE_UI_SMOKE" == "1" ]]; then
  native_report="$(mktemp "${TMPDIR:-/tmp}/forkclip-native-smoke.XXXXXX")"
  echo "Running native UI smoke..."
  if FORKCLIP_NATIVE_SMOKE_REPORT="$native_report" "$APP_BINARY"; then
    cat "$native_report"
  else
    cat "$native_report" >&2 || true
    echo "Native UI smoke failed." >&2
    rm -f "$native_report"
    exit 1
  fi
  if ! grep -q '^nativeSmokeStatus=passed$' "$native_report"; then
    echo "Native UI smoke report did not mark success." >&2
    rm -f "$native_report"
    exit 1
  fi
  rm -f "$native_report"
else
  echo "Skipping native UI smoke."
fi

echo "Latest encrypted payload prefix: $(read_latest_payload)"
echo "Recent logs:"
/usr/bin/log show --last 5m --predicate "$LOG_PREDICATE" --style compact | tail -n 20 || true
