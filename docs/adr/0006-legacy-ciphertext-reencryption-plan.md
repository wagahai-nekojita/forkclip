# ADR 0006: Legacy Ciphertext Re-Encryption Plan

## Status

Accepted — implemented in schema 12 migration

## Context

Forkclip previously had two encrypted row forms:

- legacy ciphertext: AES-GCM ciphertext without the `forkclip-aad-v1:` prefix;
- current ciphertext: AES-GCM ciphertext with the `forkclip-aad-v1:` prefix and row identity authenticated data.

Legacy ciphertext was readable after the authenticated-data encryption change, but it was not bound to a SQLite row. Current item rows are tied to `clipboard_items/<itemID>/content`, and current payload rows are tied to `clipboard_payloads/<itemID>/<payloadID>/encrypted_data`.

Before removing legacy read support or changing encryption envelopes again, Forkclip needs a safe plan to rewrite legacy rows to the current authenticated form.

## Decision

Legacy ciphertext detection is deterministic: any encrypted item or payload value that does not start with `forkclip-aad-v1:` is treated as legacy for re-encryption planning. Values with the prefix must be opened only with the expected row context.

Schema migration 12 scans every encrypted item, Display Title, and payload row and rewrites only legacy values:

- item content is decrypted through the legacy read path and re-encrypted with `.itemContent(itemID:)`;
- Display Title is decrypted through the legacy read path and re-encrypted with `.itemDisplayTitle(itemID:)`;
- payload data is decrypted through the legacy read path and re-encrypted with `.payloadData(itemID:payloadID:)`;
- current prefixed ciphertext is left unchanged.

The migration must follow ADR 0005. It must run in a transaction for SQLite row rewrites and advance `user_version` only after every selected row is rewritten successfully. If any legacy row cannot be decrypted or re-encrypted, the migration must abort, keep the previous `user_version`, leave persistence unavailable, and leave existing data readable by the old app version or recoverable from backup.

The compatibility API is migration-only: normal context-bound reads reject unprefixed ciphertext. Removing `decryptLegacy` requires separate evidence that upgraded databases contain no legacy encrypted rows.

## Required Tests

The implementation includes mixed-data tests:

- a database with legacy item content and current payload data;
- a database with current item content and legacy payload data;
- a database with both legacy and current rows across multiple items;
- a failure case where one legacy row cannot decrypt, proving `user_version` does not advance and no destructive cleanup occurs.

The tests must verify that rewritten rows gain the `forkclip-aad-v1:` prefix and still decrypt with the expected row context, while already-current rows remain readable and are not rewritten unnecessarily.

## Options Considered

### Keep Legacy Read Support Forever

This avoids migration risk but keeps the encryption boundary harder to reason about and makes future envelope changes depend on old compatibility behavior indefinitely.

### Rewrite Opportunistically During Fetch

This is rejected for the first implementation. Opportunistic writes during normal history loading make failures harder to observe, mix read and migration behavior, and complicate rollback evidence.

### Dedicated Schema Migration Rewrite

This is the chosen path. It keeps the rewrite tied to `user_version`, allows focused mixed-row tests, and gives reviewers one migration boundary to inspect.

## Consequences

Benefits:

- Future encryption changes can eventually rely on one authenticated row-bound ciphertext form.
- Mixed legacy/current databases get a deterministic upgrade path.
- Failure behavior is reviewable through the migration rollback policy.

Costs:

- The next implementation needs careful fixture setup for mixed ciphertext rows.
- Legacy decryption is isolated to the migration path; normal reads no longer accept unbound ciphertext.
- Rewriting every legacy encrypted row may be expensive for large histories, so the implementation should avoid unrelated cleanup in the same PR.

## Required Follow-up Issues

- After release evidence, create a separate Issue to evaluate removing legacy read support.

## Validation

The implementation PR ran the relevant Swift tests from `docs/developer/validation.md`, including focused mixed legacy/current database migration tests and rollback cases. Future changes must preserve those tests.
