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

The script runs `LargeHistoryPerformanceTests`, which measures dashboard paths against a 10,000-item mixed clipboard history fixture:

- `DashboardContentScope`: filters the fixture across all dashboard content scopes.
- `DashboardFrequentItems`: orders the fixture by usage and recency for the frequent-items strip.

Baseline captured locally on 2026-05-10:

- Dashboard scope filtering: 0.056 seconds average.
- Frequent items ordering: 0.022 seconds average.

These measurements cover in-memory dashboard filtering and ordering costs, not SwiftUI redraw, persistence fetches, or image thumbnail decoding. Treat regressions in these numbers as evidence to inspect dashboard classification and sorting before optimizing storage or UI rendering.
