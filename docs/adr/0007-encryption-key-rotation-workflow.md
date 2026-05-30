# ADR 0007: Encryption Key Rotation Workflow

## Status

Accepted

## Context

Forkclip stores one symmetric encryption key in the user's login Keychain under service `com.user.forkclip.encryption` and account `symmetricKey`. Current recovery behavior handles a missing key by archiving the database and creating a new key, which is a clean-start recovery path rather than a planned rotation workflow.

Future hardening may need planned key rotation for release key lifecycle changes, Keychain access-policy changes, SQLCipher key transitions, or user-initiated security maintenance. Rotation can make all encrypted history unreadable if the old key is discarded before every encrypted row is re-encrypted and validated.

## Decision

Do not force encryption key rotation on existing users until a dedicated implementation satisfies ADR 0005 rollback requirements and the Keychain migration policy is defined.

The first planned rotation implementation must be explicit and user-visible. It must not reuse the missing-key recovery path because recovery intentionally archives the old database and starts clean. Planned rotation must preserve readable history.

The rotation workflow must use these states:

- `notNeeded`: current key remains valid and no rotation is pending;
- `ready`: old key is readable, new key can be generated, and database backup or dual-key boundary is available;
- `rotating`: encrypted rows are being rewritten from old key to new key;
- `verifying`: rewritten rows are opened with the new key before commit or final swap;
- `succeeded`: new key is active and rotated data is readable;
- `failed`: old key/data remains the active readable path or a backup is available for recovery.

The implementation must keep old-key readability until verification succeeds. Acceptable safety boundaries are:

- backup the database and keep the old Keychain item until all rows verify with the new key;
- write rotated data to a new database and swap only after verification;
- support dual-key lookup during a bounded migration window.

Deleting the old key or cleanup data is a separate follow-up after release evidence. It must not happen in the first rotation PR.

## Validation Requirements

The implementation PR must prove:

- existing item and payload rows decrypt after rotation;
- mixed current and legacy ciphertext forms follow ADR 0006 before rotation or are blocked with a diagnostic;
- a simulated rewrite failure leaves old data readable or backed up;
- failed rotation reports an observable diagnostic state;
- no old key deletion happens before successful verification.

Local Keychain side effects must remain isolated through injected key storage in tests. Tests must not require mutating the user's real Keychain.

## Options Considered

### Reuse Missing-Key Recovery

This is rejected for planned rotation. It protects the app from an unrecoverable missing key but intentionally does not preserve readable history under the old key.

### In-Place Re-Encrypt and Delete Old Key Immediately

This is rejected. A partial rewrite or verification failure would make history unreadable.

### Backup or Dual-Key Rotation

This is the chosen direction. It adds implementation complexity but preserves provenance and gives reviewers concrete rollback evidence.

## Consequences

Benefits:

- Planned rotation remains distinct from destructive recovery.
- Future SQLCipher and Keychain migration work has a safe key lifecycle boundary.
- Users are not forced into data-loss risk by a background key change.

Costs:

- Rotation needs UI/diagnostics copy before it is exposed.
- Implementation requires test-only key storage fixtures and database rewrite fixtures.
- Old key cleanup is delayed until successful rotation evidence exists.

## Required Follow-up Issues

- Keychain service/account/access-group migration must be defined before rotation changes key lookup identifiers.
- A future implementation Issue must add the rotation state model, diagnostics, and database rewrite tests.
- A separate cleanup Issue may remove old-key fallback only after release evidence.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs must run Swift tests from `docs/developer/validation.md` and include injected-key-storage tests for successful rotation, rewrite failure, and old-key preservation.
