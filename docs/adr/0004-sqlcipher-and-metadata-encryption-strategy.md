# ADR 0004: SQLCipher and Metadata Encryption Strategy

## Status

Accepted

## Context

Forkclip stores clipboard history in a local SQLite database under the user's Application Support directory. Clipboard item preview content and payload bytes are encrypted before persistence with AES-GCM. New encrypted rows bind ciphertext to row identity with authenticated data: item content is tied to its item ID, and payload bytes are tied to the item ID and payload ID.

The database still contains queryable metadata in plaintext. Current plaintext metadata includes row IDs, timestamps, source bundle IDs, favorite and secret flags, usage counts, content type, pasteboard type, byte size, rank, folder names, folder assignments, and schema version. Payload-row preview metadata is not persisted in v1 and existing preview values are cleared by migration.

This boundary keeps filtering, retention, folders, diagnostics, and migration checks simple, but it means a local process or backup with database access can still infer clipboard behavior from metadata even when payload content is encrypted. SQLCipher could encrypt the whole SQLite file, but adopting it changes build, migration, key-management, corruption-recovery, and release-validation surfaces.

## Decision

Do not adopt SQLCipher in the next implementation increment. Keep the current application-layer AES-GCM content and payload encryption boundary, and treat SQLCipher as a later hardening option that requires its own migration and release-readiness Issue.

Forkclip will minimize plaintext metadata before adding database-file encryption. New metadata columns must be classified before implementation:

- Content data and content-derived previews are encrypted or omitted.
- Query metadata may remain plaintext only when needed for local product behavior.
- Sensitive metadata should be avoided by default, especially user-entered preview text, raw pasteboard payload summaries, unbounded source labels, and secret-derived search material.
- Any future searchable index must have a separate design decision before persistence.

SQLCipher adoption is deferred until Forkclip has explicit answers for database migration rollback, key rotation, Keychain migration, sandbox storage migration, release signing, and local validation. If SQLCipher is later adopted, it must be implemented as an additive migration with backup or rollback behavior, old-database readability checks, and clear diagnostics for key or open failures.

## Options Considered

### Keep Application-Layer Encryption Only

This is the chosen near-term approach. It preserves the current SwiftPM and SQLite.swift setup, keeps existing migration tests relevant, and avoids changing the database-open path while rollback and release policies are still open.

The cost is that SQLite file metadata remains plaintext. This is acceptable only if future changes keep metadata small, intentional, and reviewed.

### Adopt SQLCipher Immediately

This would protect both encrypted payloads and database metadata at rest, but it is too broad for the current state. It introduces a new dependency and changes how the database is opened, backed up, repaired, migrated, and validated. It also intersects with Keychain lookup, sandbox storage paths, release signing, and future key rotation.

This option is rejected for the next increment because the migration and rollback prerequisites are not ready.

### Store More Metadata Encrypted in Application Tables

This can reduce plaintext leakage without changing SQLite itself, but it weakens queryability and can add ad hoc encrypted blobs that are hard to migrate. Forkclip should use this selectively for fields that are clearly sensitive and not needed for filtering, sorting, retention, or diagnostics.

### Add Search Indexes Before Encryption Strategy Is Settled

This is rejected. Search indexes can duplicate sensitive clipboard content or derived tokens. Any future full-text or keyword index needs an explicit privacy design before it is persisted.

## Consequences

Benefits:

- Avoids dependency, build, and database-open churn before migration policy exists.
- Keeps current encrypted payload and authenticated-data tests meaningful.
- Makes metadata minimization the default review standard for future schema work.
- Leaves SQLCipher available as a focused hardening project instead of a hidden side effect of unrelated persistence work.

Costs:

- The SQLite file still exposes metadata to a process or backup that can read the database file.
- Future feature work must justify each new plaintext metadata field.
- Stronger database-at-rest protection remains blocked on migration, key, sandbox, and release-readiness work.

## Required Follow-up Issues

- Define migration rollback policy before database-file encryption or broad metadata rewrites.
- Plan legacy ciphertext re-encryption before removing legacy ciphertext read support or changing envelope policy.
- Define encryption key rotation workflow before any planned key lifecycle or SQLCipher key transition.
- Plan sandbox storage migration before changing database paths or release sandbox defaults.
- Plan Keychain migration behavior before changing service, account, access group, or SQLCipher key lookup.
- Add a future SQLCipher implementation Issue only after those prerequisites define migration, rollback, and validation expectations.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs that change schema, encryption behavior, Keychain lookup, database paths, or release signing must run the relevant validation from `docs/developer/validation.md` and report skipped local-only checks with concrete reasons.
