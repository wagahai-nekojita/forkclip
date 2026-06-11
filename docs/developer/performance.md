# Performance Notes

Use focused, repeatable measurements before optimizing runtime or UI paths.

## Focused State Performance

Run from the repository root:

```sh
Forkclip/scripts/measure-focused-state-performance.sh
```

The script runs `FocusedStatePerformanceTests`, which measures the SwiftUI-observed state models introduced by the focused state split:

- `ClipboardSelectionState`: toggles 1,000 selected items on and off.
- `ClipboardFolderState`: resolves 120 folder selections by ID.
- `ClipboardDiagnosticsState`: applies 1,000 diagnostic snapshots and banner updates.

Baseline captured locally on 2026-05-10:

- Selection toggle: 0.005 seconds average.
- Folder lookup: 0.001 seconds average.
- Diagnostics update: 0.001 seconds average.

These measurements cover state mutation costs, not full SwiftUI redraw or large-history rendering. Treat regressions in these numbers as evidence to inspect the focused state models; use separate large-history benchmarks before optimizing filtering, dashboard sections, persistence, or image thumbnail caching.

## Large History Performance

Run from the repository root:

```sh
Forkclip/scripts/measure-large-history-performance.sh
```

The script runs `LargeHistoryPerformanceTests`, which measures dashboard paths against a 10,000-item mixed clipboard history fixture and persisted reload behavior against a 1,000-item encrypted SQLite fixture:

- `DashboardContentScope`: filters the fixture across all dashboard content scopes.
- `DashboardFrequentItems`: orders the fixture by usage and recency for the frequent-items strip.
- `PersistentHistoryReload`: loads encrypted item rows, fetches each item's persisted payloads, decrypts payload data, and builds the same item-to-payload cache shape used by history reload.

Baseline captured locally on 2026-05-10:

- Dashboard scope filtering: 0.056 seconds average.
- Frequent items ordering: 0.022 seconds average.

The dashboard measurements cover in-memory filtering and ordering costs. The persisted reload measurement covers local SQLite fetches plus AES-GCM item and payload decryption; it does not measure SwiftUI redraw, real pasteboard access, or image thumbnail decoding. Treat the printed persisted reload average as a local comparison point, not an absolute CI performance threshold.
