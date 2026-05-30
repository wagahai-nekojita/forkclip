# ADR 0008: Sandbox Storage Migration Plan

## Status

Accepted

## Context

Forkclip currently stores local data under the unsandboxed user Application Support directory:

- database: `~/Library/Application Support/Forkclip/forkclip.sqlite`;
- settings: `~/Library/Application Support/Forkclip/app_settings.json`;
- retention policy: `~/Library/Application Support/Forkclip/retention_policy.json`;
- backups: `~/Library/Application Support/Forkclip/Backups`.

ADR 0003 defers App Sandbox until data and Keychain migration are implemented and validated. Once sandboxed, default app storage moves under the app container. Enabling sandbox without a migration path can make existing history, settings, retention policy, and backups appear missing.

## Decision

Do not enable App Sandbox by default until Forkclip has a storage migration implementation with old-path discovery, copy-then-verify behavior, and rollback evidence.

The first implementation must discover the unsandboxed Forkclip Application Support directory without creating or mutating it during discovery. Discovery must distinguish these states:

- fresh install: no old path and no container data;
- already migrated: container data exists and old path may remain;
- migration candidate: old path exists and container data does not;
- conflict: both old and container data exist and require an explicit policy before overwrite.

The migration must copy data into the container path and verify readability before the container path becomes authoritative. It must not delete the unsandboxed source in the first implementation. Existing files must remain available for rollback and user recovery.

The migration should include the database, settings, retention policy, blacklist file, and backups directory when present. The database must be opened and validated after copy. Settings and retention policy must decode or fail diagnostically. Owner-only permissions must be applied to copied directories and files where supported.

## Rollback And Failure Behavior

If migration fails, Forkclip must leave the old unsandboxed data untouched and report a diagnostic failure. It must not silently start with empty container data unless the user explicitly chooses a clean start or the implementation Issue scopes that behavior.

If a partially copied container destination exists after failure, the implementation must either remove the incomplete destination before retry or mark it as incomplete so it is not treated as authoritative on the next launch.

The first migration PR must follow ADR 0005 and must not combine storage migration with Keychain service/account/access-group migration.

## Required Tests

The implementation PR must test:

- fresh install with no old path;
- existing unsandboxed database copied to an empty container path;
- already migrated container data does not overwrite itself from old path;
- conflict where both old and container data exist;
- copy or validation failure leaves old data in place and container data non-authoritative.

Tests must use injected or temporary base directories. They must not read or mutate the developer's real Application Support directory.

## Options Considered

### Enable Sandbox And Start Clean

This is rejected as the default path because it silently strands existing clipboard history and settings.

### Move Old Data Into The Container

This is rejected for the first implementation because a failed move can lose the rollback source. Deletion or move cleanup can be a later explicit follow-up after migration evidence.

### Copy Then Verify

This is the chosen direction. It preserves old data, supports retry, and gives tests a clear success/failure boundary.

## Consequences

Benefits:

- Existing users keep a recoverable unsandboxed source during migration.
- Fresh installs and already-migrated installs can be handled deterministically.
- Sandbox rollout remains blocked until storage migration evidence exists.

Costs:

- Old data remains on disk after first migration and needs a later cleanup decision.
- Migration implementation needs temporary path injection and more filesystem tests.
- User-facing diagnostics or recovery copy may be needed before sandbox is enabled.

## Required Follow-up Issues

- Implement storage path abstraction and copy-then-verify migration tests.
- Add user/developer documentation when sandbox storage behavior is implemented.
- Decide cleanup policy for old unsandboxed data after release evidence.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs must run relevant Swift tests from `docs/developer/validation.md`, and script validation if build, install, refresh, or smoke scripts learn sandbox-specific paths.
