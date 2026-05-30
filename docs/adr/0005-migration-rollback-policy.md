# ADR 0005: Migration Rollback Policy

## Status

Accepted

## Context

Forkclip has schema migrations, encrypted legacy row migrations, Keychain-backed encryption, recovery backup behavior, and future hardening work queued for SQLCipher, key rotation, sandbox storage migration, and Keychain migration.

The current database migrator already uses SQLite transactions and `PRAGMA user_version` as the durable schema marker. Existing tests cover representative failure behavior: future schema versions are rejected without downgrade, unreadable legacy item migration does not advance `user_version`, and unreadable legacy payload rewrite does not advance `user_version`. Key recovery also archives the existing database before replacing a missing key.

Future migration work must not rely on ad hoc rollback decisions because failed migration can make clipboard history unreadable or strand data across storage, Keychain, or encryption boundaries.

## Decision

Forkclip migrations must be fail-closed and non-destructive by default.

Schema migrations must run inside a transaction whenever SQLite can roll the change back. `user_version` must advance only after every schema change, data backfill, rewrite, and validation step for that version completes. A failed migration must leave the previous `user_version` in place, mark persistence unavailable, and surface an observable diagnostic failure instead of partially serving migrated data.

Data or crypto migrations that cannot be fully protected by one SQLite transaction must create a recoverable boundary before destructive changes. Acceptable boundaries are:

- copy or move the database to an owner-only backup before modifying it;
- write migrated data to a new destination and swap only after validation;
- keep old key/data lookup readable until the new path is verified.

Destructive cleanup is a separate step after successful validation. It must not be combined with first-write migration, key rotation, storage relocation, SQLCipher adoption, or Keychain identifier changes unless the Issue explicitly scopes cleanup and rollback evidence.

Future migration PRs must define:

- migration trigger and preconditions;
- backup, transaction, or dual-read boundary;
- abort behavior and user-visible diagnostic state;
- validation that old data remains readable or explicitly recoverable;
- tests for at least one failure path that proves no silent downgrade, cleanup, or `user_version` advance.

## Options Considered

### Best-Effort In-Place Migration

This is rejected. It is simpler to implement but can leave partial schema/data changes when decryption, encoding, file movement, or Keychain lookup fails.

### Transaction-Only Rollback

This is required for normal SQLite schema and row rewrites, but it is not sufficient for file moves, Keychain changes, SQLCipher adoption, or cross-database migrations.

### Backup or Dual-Read Boundary for Broad Migrations

This is the chosen policy for migrations that cross storage, crypto, or Keychain boundaries. It adds implementation work but gives users an explicit recovery path and gives reviewers concrete evidence to inspect.

## Consequences

Benefits:

- Failed migrations keep a visible failed state instead of hiding partial success.
- Future schema and crypto PRs have a clear review checklist.
- SQLCipher, key rotation, sandbox storage, and Keychain migration work cannot silently discard history.

Costs:

- Some migrations require extra disk space for backups or temporary destinations.
- Broad migrations need more tests and diagnostics before merge.
- Cleanup of obsolete data may require follow-up PRs after migration evidence exists.

## Required Follow-up Issues

- Legacy ciphertext re-encryption must follow this rollback policy.
- Key rotation must preserve old-key readability or backup behavior.
- Sandbox storage migration must define old-path discovery and rollback.
- Keychain migration must preserve old service/account fallback.
- SQLCipher implementation must remain blocked until backup, open-failure diagnostics, and old-database readability checks are specified.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Existing representative tests that enforce this policy include:

- `testFutureSchemaVersionIsRejectedWithoutDowngrade`
- `testUnreadableLegacyItemMigrationDoesNotAdvanceUserVersion`
- `testUnreadableLegacyPayloadRewriteDoesNotAdvanceUserVersion`

Implementation PRs that alter migration behavior must run the relevant Swift tests from `docs/developer/validation.md` and include focused tests for the new failure path.
