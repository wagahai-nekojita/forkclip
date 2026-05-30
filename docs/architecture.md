# Architecture

Forkclip is a local-first macOS menu bar clipboard manager. This page is a map for reviewers who want the shape of the system before reading code or ADRs.

## Architecture At A Glance

Forkclip runs as a Swift Package-built macOS app bundle. The SwiftUI app entry point delegates native app setup to AppKit so the app can live in the menu bar, own floating panels, interact with the system pasteboard, and present Settings, Dashboard, and diagnostic surfaces.

Clipboard data flows through four broad stages:

1. Capture from `NSPasteboard`.
2. Classify and filter according to content type and privacy rules.
3. Persist encrypted item and payload records in local SQLite.
4. Copy compatible payloads back to the pasteboard, optionally followed by Auto Paste.

## App Shell

`ForkclipApp` provides the SwiftUI app entry point. `AppDelegate` owns the AppKit integration:

- menu bar status item;
- quick history `NSPanel`;
- Dashboard, Settings, and About windows;
- app appearance application;
- clipboard monitoring lifecycle;
- local native smoke hook used by validation scripts.

The quick panel and Dashboard are separate UI surfaces over the same clipboard manager state. This keeps repeated operations fast in the menu bar while still offering a larger inspection surface for dense history work.

## Clipboard Pipeline

Clipboard capture starts from `NSPasteboard` through a small pasteboard abstraction used by tests and production code. `ClipboardCaptureSnapshot` normalizes supported pasteboard representations into typed payloads:

- plain text;
- URL text;
- file URL;
- RTF;
- HTML;
- image data for common pasteboard image types.

The pipeline skips unsupported pasteboard-only formats instead of storing unknown raw data. It also respects private mode, application blacklist rules, and the system concealed pasteboard marker before reading and saving new payload data.

Copy-back writes the saved compatible representations to the system pasteboard. Auto Paste is intentionally copy-first: Forkclip copies the selected item, then attempts to return focus to the previously active app and send Paste when macOS Accessibility permission allows it. If that paste attempt fails, the item remains copied for manual paste.

## Persistence

`DatabaseManager` owns local SQLite persistence. The schema separates event-level item metadata from typed payload rows:

- `clipboard_items` stores item identity, timestamps, source bundle ID, primary content type, favorite/private flags, usage metadata, and optional encrypted Display Title.
- `clipboard_payloads` stores per-format payload data, pasteboard type, content type, byte size, and rank.
- folder tables store manual organization metadata and item assignments.

`SchemaMigrator` owns additive schema changes and representative rollback behavior. Migrations use SQLite transactions where possible and keep future broad storage, Keychain, and database-file encryption changes behind explicit ADRs and validation requirements.

## Privacy Boundaries

Forkclip is local-first. Clipboard contents are not sent to external services by the app.

Before persistence, clipboard text, URL text, file URL data, RTF, HTML, image bytes, and Display Titles are encrypted with CryptoKit AES-GCM. The symmetric key is stored in the user's login Keychain. New encrypted rows bind ciphertext to row identity with authenticated data so item content, Display Titles, and payload bytes are tied to their expected item and payload IDs.

Queryable metadata remains plaintext only where the app needs it for local behavior, such as timestamps, content type, pasteboard type, byte size, flags, folder metadata, and schema version. This is not the same as whole-database encryption. SQLCipher, App Sandbox defaults, Keychain descriptor migration, and planned key rotation are documented as deferred hardening topics.

Private mode stops saving new clipboard changes while enabled. The blacklist prevents capture from configured sensitive apps. Likely-secret masking keeps high-confidence credential-like content out of previews while preserving the ability to recognize private items through optional Display Titles.

## UI Surfaces

Forkclip has three main user-facing surfaces:

- Quick Panel: a compact menu bar history panel with layout, folder, queue, private mode, search, and copy actions.
- Dashboard: a larger window for browsing, filtering, inspecting, and reusing history.
- Settings: controls for appearance, panel placement and sizing, retention, launch behavior, feedback, Auto Paste, and privacy.

Diagnostics surface monitor, database, Keychain, save, and recovery states so local failures are visible instead of silently hiding missing or unreadable history.

## Validation Boundaries

GitHub Actions CI validates source-level behavior: whitespace checks, script syntax, SwiftPM build, and SwiftPM test behavior on the configured macOS runner. It does not claim app distribution readiness.

Local validation covers side-effectful behavior that is inappropriate for normal CI, including app bundle refresh, clipboard-writing smoke checks, native UI smoke hooks, local SQLite inspection, and Accessibility-dependent Auto Paste checks.

Release signing and Hardened Runtime checks exist as explicit scripts, but missing signing credentials report `SKIP` by default. Signing, notarization, App Store distribution, `.zip` or `.dmg` artifacts, checksums, and public install verification are outside this portfolio source release.

## Related ADRs

- [ADR 0001: Multi-format Clipboard Data Model](adr/0001-multiformat-clipboard-data-model.md)
- [ADR 0003: Sandbox, Signing, and Keychain Policy](adr/0003-sandbox-signing-keychain-policy.md)
- [ADR 0004: SQLCipher and Metadata Encryption Strategy](adr/0004-sqlcipher-and-metadata-encryption-strategy.md)
- [ADR 0005: Migration Rollback Policy](adr/0005-migration-rollback-policy.md)
- [ADR 0007: Encryption Key Rotation Workflow](adr/0007-encryption-key-rotation-workflow.md)
- [ADR 0008: Sandbox Storage Migration Plan](adr/0008-sandbox-storage-migration-plan.md)
- [ADR 0009: Keychain Migration Plan](adr/0009-keychain-migration-plan.md)

Start with the [ADR index](adr/README.md) for implementation status and recommended reading order.
