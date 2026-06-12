# Settings

Forkclip settings are saved automatically. Settings are stored locally under `~/Library/Application Support/Forkclip`.

## Appearance

- `表示モード`: choose System, Light, or Dark. System follows the current macOS appearance.
- `履歴の表示`: choose horizontal, grid, or list history layout.
- `サウンド`: play a short quiet click when Forkclip successfully saves a new external clipboard item or copies a history item back to the pasteboard.
- `メニューバーのアニメーション`: briefly cushions the menu bar icon after successful save/copy feedback. The animation is skipped when macOS Reduce Motion is enabled.
- `起動時にプライベートモード`: start without saving clipboard history.

## Panel

- `Quick Panel`: shows the shipped global shortcut, `Control-Option-Command-V`, and its current registration status. The shortcut is fixed in this release; Settings can retry registration but does not edit the key combination.
- `表示位置`: choose whether the quick panel opens from the bottom, top, left, or right edge of the visible screen.
- `パネルサイズ`: choose compact, standard, large, or custom.
- `カード選択時に自動貼り付け`: default off. When enabled, clicking a history card copies it, hides Forkclip, returns to the app that was active before the panel opened, and sends Paste when macOS permits Forkclip to post the paste shortcut.
- Top and bottom placements use a full-width panel with compact, standard, and large height presets.
- Left and right placements use a full-height side panel with compact, standard, and large width presets.
- Custom size controls appear only when `カスタム` is selected. Custom height is used for top and bottom placements, and custom width is used for left and right placements.

The global shortcut opens the Quick Panel from another app and closes it when the panel is already visible. It uses macOS global hotkey registration rather than Accessibility-based key monitoring. If macOS rejects the registration because the shortcut is reserved or already claimed, Settings shows a failed state with the OSStatus code and a retry button. Resolve the conflicting shortcut first, then retry registration or restart Forkclip.

Auto Paste depends on macOS allowing Forkclip to activate the previous app and send the paste shortcut. macOS may require Accessibility permission for reliable synthetic paste events, and some target apps or non-editable fields may still reject the paste. If the paste event cannot be completed, the item remains copied to the pasteboard and Forkclip shows a status message the next time the panel is visible.

### Auto Paste Troubleshooting

Use these steps when Auto Paste copies the item but does not insert it into the target app:

1. Quit Forkclip.
2. Open System Settings > Privacy & Security > Accessibility.
3. Remove any existing Forkclip entry.
4. Add the currently running app bundle. For repository builds, this is usually `<repo-root>/Forkclip.app`. If you installed Forkclip into Applications, use `/Applications/Forkclip.app` instead.
5. Enable Forkclip in the Accessibility list.
6. Restart Forkclip.
7. Put the cursor in an editable target, such as an empty TextEdit document.
8. Open Forkclip, enable Auto Paste, and click a Clipboard Item.

Local development builds are ad hoc signed by default. After rebuilding or refreshing the local app bundle, macOS may treat the new binary as a different Accessibility client even though the bundle name is still Forkclip. If Auto Paste regresses after a rebuild, repeat the remove/add/restart steps for the current `Forkclip.app`.

## Startup

- `ログイン時に起動`: registers Forkclip as a login item on macOS 13 or later.
- macOS 12 does not support direct login item control through this app.

## Storage

- `表示する履歴数`: controls how many items are loaded into the panel. The default is 40.
- `保存件数を制限`: caps stored history count. The default is on with a 100 item limit.
- `古い履歴を削除`: removes entries older than the configured number of days. The default is on with a 14 day limit.
- Favorite items are excluded from automatic count and age cleanup.

## Privacy

- The application blacklist file stores bundle identifiers that Forkclip should ignore.
- Use `Finder で表示` to locate the file.
- Use `除外リストを再読み込み` after editing it.

## Reset

`初期値に戻す` asks for confirmation before changing settings.
