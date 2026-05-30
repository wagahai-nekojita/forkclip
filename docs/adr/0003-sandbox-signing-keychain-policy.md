# ADR 0003: Sandbox, Signing, and Keychain Policy

## Status

Accepted

## Context

Forkclip is a local macOS menu bar utility built from SwiftPM and wrapped into `Forkclip.app` by shell scripts. The current bundle is signed ad hoc by default, has no entitlements file, does not request Hardened Runtime, stores SQLite data under `~/Library/Application Support/Forkclip`, and stores the encryption key in the user's login Keychain with the service `com.user.forkclip.encryption`.

Clipboard history is sensitive. Enabling App Sandbox, Hardened Runtime, stricter signing, and Keychain access control is desirable, but turning those on without a plan can break local development builds, `/Applications` refresh scripts, Launch Services behavior, launch-at-login behavior, existing local data, and existing Keychain lookup.

## Decision

Forkclip will use separate security profiles for development and release.

Local development builds remain ad hoc signed by default and do not enable App Sandbox by default. This keeps `swift build`, local app refresh, smoke checks, and agent validation fast and predictable. The build scripts may add an opt-in sandbox/release profile for validation, but the default developer path should stay low-friction.

Local release builds will use an explicit entitlements file, Hardened Runtime signing, and a stable bundle identifier. The release signing command should use `codesign --options runtime --entitlements <file>` instead of only `codesign --deep --sign`. The release profile should be validated by build scripts before it is used for user-facing artifacts.

App Sandbox should be enabled only after data and Keychain migration are implemented and validated. Once sandboxed, Forkclip's default storage moves from the unsandboxed Application Support path to the app container path. The implementation must not silently abandon existing history or keys. It must either migrate existing local data before the sandbox boundary is enabled for an installed app, or start clean with an explicit user-facing migration/recovery path.

Keychain access groups will be used only for signed release builds with a stable Team ID and bundle identifier. Ad hoc local development builds should continue to use the default login Keychain lookup so contributors do not need a provisioning profile. Key lookup must support old and new service/account/access-group forms during migration.

`SecAccessControl` with user presence will not be applied directly to the always-on clipboard encryption key in the first hardening implementation. A menu bar clipboard manager needs to encrypt new captures while running in the background; requiring user presence for every key read would either prompt too often or fail under `interactionNotAllowed`. Instead, user-presence protection requires a separate locked-history design: explicit unlock UI, bounded in-memory key caching for the session, lock/relock behavior, and clear diagnostics when capture or history reveal is unavailable. That design should be implemented as a follow-up before user-presence becomes the default storage key policy.

The first implementation PR after this ADR should therefore add release entitlements and signing-script support behind an explicit profile, not silently change the default local development behavior.

## Options Considered

### Keep Current Behavior

This preserves local development speed and avoids migration risk, but it leaves the app without a declared sandbox/signing policy and keeps sensitive clipboard data exposed to more local process access than necessary.

### Enable Sandbox and Hardened Runtime Immediately

This maximizes near-term hardening but has high breakage risk. It changes the storage path, can strand existing SQLite data, can change Keychain lookup behavior, and can break current refresh/smoke scripts without giving users a migration path.

### Separate Development and Release Profiles

This is the chosen approach. It lets development stay predictable while creating a concrete path to hardened release artifacts. The cost is maintaining a small amount of build-script branching and validating both profiles.

### Put User Presence on the Existing Key Immediately

This improves protection if an attacker can access Keychain items, but it conflicts with background capture and the current noninteractive Keychain load path. It is rejected for the first implementation because the UX and failure modes are not ready.

### Add Locked-History UX Before User-Presence Key Protection

This is the chosen direction for user-presence protection. It adds product and implementation work, but it allows prompts to happen at clear user actions instead of during background capture.

## Consequences

Benefits:

- Release artifacts get a clear route to App Sandbox, Hardened Runtime, and explicit entitlements.
- Local development remains fast and does not require a Team ID or provisioning profile.
- Existing data and Keychain migration are treated as release blockers instead of accidental side effects.
- User-presence protection is deferred until the app can present understandable unlock and failure states.

Costs:

- Development and release signing paths diverge.
- Sandbox rollout requires migration work before it can be made default.
- Keychain migration must support old and new lookup policies.
- User-presence protection remains a follow-up security improvement rather than part of the first entitlements PR.

## Required Follow-up Issues

- Implement release entitlements and signing-script profile.
- Implement storage migration from the unsandboxed Application Support path to the sandbox container path, or an explicit clean-start/recovery flow.
- Implement Keychain service/account/access-group migration with old-key fallback.
- Design and implement locked-history UX before enabling user-presence protection on the encryption key path.
- Update user and developer docs after the release profile behavior is implemented.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Implementation PRs that touch scripts must run:

```sh
zsh -n Forkclip/scripts/build-and-refresh-app.sh Forkclip/scripts/install-to-applications.sh Forkclip/scripts/run-xcode-tests.sh Forkclip/scripts/smoke-check.sh
```

Implementation PRs that touch runtime behavior must also run the standard Swift build and test validation from `docs/developer/validation.md`.
