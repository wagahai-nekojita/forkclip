# ADR 0001: Multi-format Clipboard Data Model

## Status

Accepted

## Context

Forkclip currently models clipboard history as one `ClipboardItem` with encrypted text content, timestamp, optional source bundle ID, and a secret flag. SQLite persistence stores one row per history item in `clipboard_items`.

This model is intentionally narrow and works for the text-history MVP. It does not represent multiple pasteboard types from the same copy event, binary payloads, type-specific preview metadata, or future search/filter behavior by content type.

## Decision

Use a two-level model:

- `clipboard_items`: one row per clipboard event.
- `clipboard_payloads`: one row per stored pasteboard representation for that event.

`clipboard_items` owns event-level metadata:

- stable item ID
- copied timestamp
- source bundle ID
- primary display type
- user flags such as pinned/favorite when implemented
- secret/sensitive classification
- migration/version metadata

`clipboard_payloads` owns representation-level data:

- stable payload ID
- parent item ID
- pasteboard type or normalized content type
- encrypted payload bytes
- payload byte size
- preview text or preview metadata when safe
- ordering/preference rank for paste operations

Initial normalized content types:

- `plainText`
- `urlText`
- `fileURL`
- `rtf`
- `html`
- `image`
- `unknown`

The first implementation should preserve current text behavior by migrating existing `clipboard_items.content` into one `plainText` payload per item.

## Encryption Boundary

Payload bytes must be encrypted before persistence. Queryable metadata may remain unencrypted only when it is needed for app behavior and does not expose sensitive content directly.

Allowed unencrypted metadata:

- IDs
- timestamps
- source bundle IDs
- normalized content type
- byte size
- flags and migration version

Sensitive or content-derived metadata should be avoided by default. Preview text should be omitted or minimized for secret-classified items.

## Paste Behavior

Each item may have multiple payloads. Future paste behavior should choose the highest-ranked compatible payload for normal paste and use the `plainText` payload for plain-text paste when present.

If no compatible payload exists for a requested paste mode, the app should fail visibly and avoid writing partial or misleading data to the pasteboard.

## Migration Direction

The migration from the current text-only schema should be additive:

1. Keep existing item IDs and timestamps.
2. Add payload storage.
3. Convert each existing decrypted text item into one encrypted `plainText` payload.
4. Preserve source bundle ID and secret flag at item level.
5. Avoid destructive cleanup until the new model has been verified.

The exact migration script and fallback behavior must be implemented in a separate PR.

## Schema Versioning Implementation

Implementation PRs that add or change SQLite schema migration steps should use `PRAGMA user_version` as the durable schema version marker. The app should advance `user_version` only after all table creation, additive migration steps, and legacy backfills complete successfully.

Databases with a future `user_version` must be rejected rather than downgraded. If legacy rows cannot be decrypted or re-encoded during migration, setup should fail diagnostically, keep the previous `user_version`, and leave persistence unavailable until a recovery path handles the database explicitly.

## Consequences

Benefits:

- Supports multiple representations from one copy event.
- Keeps event metadata separate from encrypted payload bytes.
- Allows type filters and previews without forcing all data into text.
- Provides a path for future image, file, RTF, HTML, and URL handling.

Costs:

- Requires schema migration and more tests.
- Requires capture/paste code to handle multiple payloads.
- Requires careful preview policy to avoid leaking sensitive data.

## Deferred Decisions

- Whether large binary payloads stay in SQLite or move to encrypted files managed by SQLite metadata.
- Exact retention cleanup behavior for multi-payload items.
- Full-text search indexing strategy.
- Sync conflict model.
- External integration API shape.

## Validation

This ADR is design-only. Implementation PRs must add focused migration, persistence, and capture tests.
