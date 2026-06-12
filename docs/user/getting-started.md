# Getting Started

Forkclip runs as a macOS menu bar app. The local development bundle is named `Forkclip.app`.

## Build and Launch

From the repository root:

```sh
Forkclip/scripts/build-and-refresh-app.sh
```

The script builds the Swift package, creates or refreshes `Forkclip.app`, copies app assets and user docs into the bundle, updates an installed `/Applications/Forkclip.app` when its bundled contents are stale, launches the app, and runs a smoke check.

## Menu Bar Controls

- Left-click the menu bar icon to open or close the history panel.
- Press `Control-Option-Command-V` from any app to open or close the history panel.
- Right-click the menu bar icon to open the context menu.
- Use `Dashboard を開く` to open the larger Dashboard window for browsing and inspecting history.
- Use `設定...` to open Settings.
- Use `Forkclip について` to open version and support information.
- Use `Forkclip を終了` to quit the app.

If macOS rejects the global hotkey because another app or system feature already owns it, Forkclip keeps running. The status item context menu and Settings show that the shortcut is not registered, and both provide the current shortcut so you can resolve the conflict and retry registration.

## First Use

After launch, copy text, URL text, supported rich text/HTML, file URLs, or images from any app. Recent clipboard entries appear in the polished history panel. Clicking an entry copies its compatible pasteboard representations back to the system pasteboard.

If `カード選択時に自動貼り付け` is enabled in Settings, clicking a history entry first copies it, then hides Forkclip, returns to the app that was active before the panel opened, and sends Paste. macOS must allow Forkclip in System Settings > Privacy & Security > Accessibility for this direct paste step. If direct paste is blocked, the item remains copied so you can paste manually.

When a new external clipboard item is saved or a history item is copied back successfully, Forkclip can play a short feedback sound and briefly animate the menu bar icon. Both feedback options are on by default and can be disabled in Settings.

Open Dashboard from the panel toolbar or the status item context menu when you want a larger history view with a sidebar, recent strip, dense list, and detail inspector. Dashboard uses the same history and filters as the quick panel, with actions for copying saved items and editing Display Titles.

If no entries appear, open the diagnostics button in the toolbar and check the monitor, database, and Keychain status.
