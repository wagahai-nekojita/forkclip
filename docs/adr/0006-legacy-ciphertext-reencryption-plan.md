# ADR 0006: Legacy Ciphertext Re-Encryption Plan

## Status

Accepted

## Context

Forkclip currently reads two encrypted row forms:

- legacy ciphertext: AES-GCM ciphertext without the `forkclip-aad-v1:` prefix;
- current ciphertext: AES-GCM ciphertext with the `forkclip-aad-v1:` prefix and row identity authenticated data.

Legacy ciphertext remains readable so existing history can load after the authenticated-data encryption change. Current item rows are tied to `clipboard_items/<itemID>/content`, and current payload rows are tied to `clipboard_payloads/<itemID>/<payloadID>/encrypted_data`.

Before removing legacy read support or changing encryption envelopes again, Forkclip needs a safe plan to rewrite legacy rows to the current authenticated form.

## Decision

Legacy ciphertext detection is deterministic: any encrypted item or payload value that does not start with `forkclip-aad-v1:` is treated as legacy for re-encryption planning. Values with the prefix must be opened only with the expected row context.

The first implementation should add a schema migration step that scans both encrypted item content and encrypted payload data. It should rewrite only legacy values:

- item content is decrypted through the legacy read path and re-encrypted with `.itemContent(itemID:)`;
- payload data is decrypted through the legacy read path and re-encrypted with `.payloadData(itemID:payloadID:)`;
- current prefixed ciphertext is left unchanged.

The migration must follow ADR 0005. It must run in a transaction for SQLite row rewrites and advance `user_version` only after every selected row is rewritten successfully. If any legacy row cannot be decrypted or re-encrypted, the migration must abort, keep the previous `user_version`, leave persistence unavailable, and leave existing data readable by the old app version or recoverable from backup.

Legacy read support must stay in place for at least one release after the rewrite migration ships. Removing legacy read support requires separate evidence that upgraded databases contain no legacy encrypted rows.

## Required Tests

The implementation PR must include mixed-data tests:

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
- Legacy read support remains temporarily even after rewrite migration ships.
- Rewriting every legacy encrypted row may be expensive for large histories, so the implementation should avoid unrelated cleanup in the same PR.

## Required Follow-up Issues

- Implement the dedicated legacy ciphertext rewrite migration with mixed-row tests.
- After release evidence, create a separate Issue to evaluate removing legacy read support.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs must run the relevant Swift tests from `docs/developer/validation.md`, including focused mixed legacy/current database migration tests.
