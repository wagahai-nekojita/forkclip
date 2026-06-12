# Localization Strategy

## Decision

Keep the current Japanese visible copy as the primary product language for now. Issue #12 is the explicitly scoped start of localization infrastructure, so this repository now uses a narrow String Catalog before any non-Japanese locale is selected.

Use `Localizable.xcstrings` as the authoring catalog for the first coherent SwiftUI/AppKit UI surface while preserving the existing Japanese display text as the catalog's `ja` value, the checked-in SwiftPM runtime `.strings` value, and the Swift `defaultValue`. Keep domain formatting helpers as the API boundary for state-derived text.

## Current Inventory

User-facing strings currently live in these groups:

- app identity and descriptive copy in `AppInfo`
- menu bar, dashboard, history, folder, settings, about, and locked-history UI copy in `Forkclip/Sources/Forkclip/UI`
- diagnostics status, banner, recovery, and operation copy in `ClipboardStatusFormatter`
- diagnostics panel labels, fallback values, and recovery action copy in `DiagnosticsPanelStrings`
- capture preview fallback copy in `ClipboardMonitor`
- security and persistence error descriptions in `SecurityManager`, `ClipboardManager`, and `SchemaMigrator`
- developer/user documentation under `docs`

The most important formatter boundaries are:

- `ClipboardStatusFormatter` owns diagnostics-visible status text and date formatting.
- `DiagnosticsPanelStrings` owns the first String Catalog-backed UI surface: diagnostics panel labels, fallback values, and recovery action copy.
- `DashboardFormatters` owns dashboard type, usage, date, preview, and folder summaries.
- enum display helpers in settings and dashboard own short labels for controls and navigation.
- error types may keep developer-oriented failure detail, but UI should route final user-visible wording through UI or status formatter boundaries when practical.

## Scope Control

Do not mix localization infrastructure with copy review or behavior changes. Use separate PRs for:

- strategy documentation
- copy wording review
- adding new String Catalog-backed UI surfaces
- adding or updating translations
- moving scattered UI strings into formatter/helper boundaries

The issue #12 implementation is intentionally limited to a narrow diagnostics panel surface. It must not translate the whole app, rewrite product terminology, or redesign layouts.

## String Catalog Workflow

The authoring catalog lives at `Forkclip/Sources/Forkclip/Resources/Localizable.xcstrings`. `Forkclip/Package.swift` sets `defaultLocalization: "ja"` and processes the `Resources` directory for the executable target. Because SwiftPM currently copies `.xcstrings` as a raw resource in CLI builds, keep `Forkclip/Sources/Forkclip/Resources/ja.lproj/Localizable.strings` checked in as the runtime lookup file generated from the catalog.

When adding or updating visible strings:

1. Choose one coherent UI surface and a local helper boundary, such as `DiagnosticsPanelStrings`.
2. Add a stable dot-separated key to `Localizable.xcstrings`.
3. Preserve the current Japanese text in the catalog's `ja` localization unless a copy review or translation issue explicitly changes it.
4. Regenerate the runtime `.strings` file with:

   ```sh
   xcrun xcstringstool compile \
     Forkclip/Sources/Forkclip/Resources/Localizable.xcstrings \
     --output-directory Forkclip/Sources/Forkclip/Resources \
     --language ja \
     --serialization-format text
   ```

5. Use `String(localized:defaultValue:bundle:)` with `bundle: .module` and the same Japanese `defaultValue` in Swift so unsupported locales keep current behavior.
6. Keep state-derived strings in formatter/helper APIs rather than scattering logic through SwiftUI views.
7. Add focused tests when the moved copy represents user-critical state or recovery behavior.
8. Run the Swift validation and `git diff --check` commands from `docs/developer/validation.md`.

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

- Move the diagnostics menu open/close labels into the diagnostics localization boundary.
- Move `ClipboardStatusFormatter` diagnostics state values into catalog-backed helpers after deciding how to test state-derived localized text.
- Add String Catalog-backed helpers for settings section labels or dashboard labels as separate narrow surfaces.
- Scope the first non-Japanese locale before adding English translations.
- A future copy-boundary cleanup Issue can move remaining scattered UI strings into helper APIs when that improves testability.
