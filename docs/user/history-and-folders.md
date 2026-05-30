# History and Folders

The history panel is designed for quick reuse from the menu bar, with a slim search and folder chip toolbar above the history cards.

Dashboard is available from the panel action menu or the menu bar context menu when you need a larger browsing surface. It shows a sidebar, frequently used items, dense list, and item inspector while sharing the same history data.

## Search and Filters

- Use the search field to filter by clipboard text.
- Use the action menu to filter by the originating app.
- Use `お気に入り` to show only favorite items. This filter combines with search, source, and folder filters.
- Use the folder chips to filter by folder.

Filters combine with each other. If no entries match, clear one or more filters.

## Layouts

- Horizontal layout keeps the panel compact and scrolls left to right. Use native horizontal scrolling, or scroll vertically over the history strip to move it horizontally.
- Grid layout shows more entries at once.
- List layout gives each entry more horizontal space.

## Item Actions

- Click an item to copy it back to the system pasteboard.
- If Auto Paste is enabled in Settings, clicking an item copies it, hides Forkclip, returns to the previously active app, and attempts to paste there. If macOS blocks the paste event or the target app is unavailable, the item remains copied on the system pasteboard for manual paste.
- Use the item context menu or card action controls to add or remove Favorites.
- Use `表示名を編集…` from the item context menu to add a Display Title. The title appears above the preview and does not change what gets copied.
- Enable queue mode from the action menu to add clicked items to the queue instead of copying immediately.
- Use the item context menu to select, favorite, queue, copy as plain text, move to a folder, or delete.
- In Dashboard, select an item to inspect it, use `コピー` or double-click to copy it, and use the pencil action or context menu to edit the Display Title. Dashboard does not currently edit folders, favorites, or deletes.
- Forkclip collapses repeated plain text captures from the same source into one history item and shows the repeated capture count as `コピー回数`.
- Forkclip counts explicit copies from saved history separately as usage. Passive clipboard captures are not counted as usage.
- The Dashboard `よく使うもの` section shows saved items with the highest usage counts, using last-used time as the first tie-breaker.

## Queue and Private Modes

- `キュー`: while on, clicking a history item adds it to the queue for sequential reuse. The toolbar shows the queued count when items are queued.
- `非公開`: while on, new clipboard changes are not saved to history. Existing saved history remains available.
- Private saved items can show a Display Title while the content preview remains hidden.

## Folders

- `すべて` shows every loaded item.
- `未整理` shows items not assigned to any folder.
- User folders can be created from the `+` chip and managed from each folder chip context menu.
- Deleting a folder does not delete the clipboard items inside it.

## Favorites

- Favorites persist across app launches.
- Favorites are not removed by automatic retention cleanup for count or age limits.
- Explicit delete still removes favorite items.
- Favorites still use the same folders as normal history items, so favorite-only filtering can combine with folder filters.

## Selection

Use the always-visible card action controls or item context menu to select items. Selected items can be moved or deleted from the selected-item action strip.
