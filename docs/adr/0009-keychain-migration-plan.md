# ADR 0009: Keychain Migration Plan

## Status

Accepted

## Context

Forkclip currently stores the encryption key as a generic password in the user's login Keychain with:

- service: `com.user.forkclip.encryption`;
- account: `symmetricKey`;
- accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

Local development builds use this default login Keychain lookup without access groups. ADR 0003 requires release Keychain access groups only after signed release identity is stable, and ADR 0007 blocks planned key rotation until Keychain migration behavior is explicit.

Changing service, account, access group, accessibility, or access-control policy can make existing encrypted history unreadable if the old key is not found.

## Decision

Do not change the Keychain service, account, access group, accessibility, or access-control policy until a dedicated Keychain migration implementation exists.

The first implementation must support read-old/write-new behavior:

- attempt the preferred new key descriptor first;
- fall back to the known old descriptor `com.user.forkclip.encryption` / `symmetricKey` when the preferred key is missing;
- verify that existing database rows decrypt before writing a migrated key;
- write the key to the preferred descriptor only after verification;
- keep the old descriptor readable during the first migration release.

If no descriptor can load a key, Forkclip must report an actionable missing-key diagnostic and must not silently create a new key for an existing database. New key creation remains valid only for fresh installs or explicit recovery/clean-start flows.

Access-group migration is release-profile-only. Ad hoc local development builds must continue to work without a Team ID or provisioning profile.

## Failure Behavior

If preferred-key write fails after old-key read succeeds, the app must keep using the old key and report a migration warning or diagnostic. It must not delete the old key.

If old-key read succeeds but database verification fails, the migration must abort and leave both Keychain and database state unchanged.

Deleting the old descriptor is a separate cleanup decision after release evidence proves migrated users can read history from the preferred descriptor.

## Required Tests

The implementation PR must use injected `KeyStorage`; it must not require the developer's real Keychain.

Required test states:

- fresh install creates only the preferred descriptor;
- preferred descriptor exists and old descriptor is ignored;
- preferred descriptor missing, old descriptor present, existing data verifies, and preferred descriptor is written;
- preferred descriptor missing, old descriptor present, but database verification fails and no new descriptor is written;
- no descriptor exists for an existing database and the result is an actionable missing-key state;
- old descriptor is not deleted during first migration.

## Options Considered

### Change Identifier And Create A New Key

This is rejected because it strands existing encrypted history.

### Read Old And Immediately Delete Old

This is rejected for the first migration because rollback and release evidence are not yet available.

### Read Old, Write New, Keep Old Temporarily

This is the chosen direction. It preserves encrypted-data continuity and keeps local development independent of release signing credentials.

## Consequences

Benefits:

- Existing history remains readable across Keychain identifier changes.
- Tests can cover migration behavior without global Keychain side effects.
- Release access-group work gets a concrete compatibility boundary.

Costs:

- Key lookup must support multiple descriptors during a migration window.
- Old-key cleanup requires a later explicit PR.
- Diagnostics need to distinguish missing key, failed migration write, and verification failure.

## Required Follow-up Issues

- Implement preferred/legacy key descriptor lookup with injected `KeyStorage` tests.
- Add release-profile access-group support only after signing profile work is ready.
- Create a later cleanup Issue to remove old descriptor fallback after release evidence.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs must run Swift tests from `docs/developer/validation.md` and include injected-key-storage tests for missing, migrated, and failed-migration states.
