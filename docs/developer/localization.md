# Localization Strategy

## Decision

Keep the current Japanese visible copy as the primary product language for now. Do not introduce `Localizable.strings`, String Catalogs, or translation infrastructure until a first non-Japanese locale is explicitly scoped.

When localization starts, prefer a String Catalog (`Localizable.xcstrings`) for SwiftUI/AppKit visible copy and keep domain formatting helpers as the API boundary for state-derived text.

## Current Inventory

User-facing strings currently live in these groups:

- app identity and descriptive copy in `AppInfo`
- menu bar, dashboard, history, folder, settings, about, and locked-history UI copy in `Forkclip/Sources/Forkclip/UI`
- diagnostics status, banner, recovery, and operation copy in `ClipboardStatusFormatter`
- capture preview fallback copy in `ClipboardMonitor`
- security and persistence error descriptions in `SecurityManager`, `ClipboardManager`, and `SchemaMigrator`
- developer/user documentation under `docs`

The most important formatter boundaries are:

- `ClipboardStatusFormatter` owns diagnostics-visible status text and date formatting.
- `DashboardFormatters` owns dashboard type, usage, date, preview, and folder summaries.
- enum display helpers in settings and dashboard own short labels for controls and navigation.
- error types may keep developer-oriented failure detail, but UI should route final user-visible wording through UI or status formatter boundaries when practical.

## Scope Control

Do not mix localization infrastructure with copy review or behavior changes. Use separate PRs for:

- strategy documentation
- copy wording review
- introducing String Catalogs
- adding or updating translations
- moving scattered UI strings into formatter/helper boundaries

The first localization implementation PR should only add infrastructure for a narrow surface, such as diagnostics copy or settings section labels, and should not translate the whole app at once.

## Testing Expectations

Visible copy that represents state should be tested at the formatter/helper boundary rather than through rendered SwiftUI whenever possible.

Add or update focused tests when changing:

- diagnostics labels or status text
- operation, banner, recovery, or error copy
- date/time formatting
- dashboard classification labels
- settings enum labels

Do not snapshot broad UI copy as the default strategy. Prefer small tests that prove stable wording for user-critical states and keep non-critical layout text covered by review.

## Follow-up Candidates

- Diagnostics wording should be reviewed without adding localization infrastructure.
- A future localization infrastructure Issue can introduce String Catalogs after one target locale and one scoped UI surface are chosen.
- A future copy-boundary cleanup Issue can move remaining scattered UI strings into helper APIs when that improves testability.
