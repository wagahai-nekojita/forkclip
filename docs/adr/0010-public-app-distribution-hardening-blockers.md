# ADR 0010: Public App Distribution Hardening Blockers

## Status

Accepted

## Context

Forkclip is currently published as a portfolio source repository, not as a
public app download channel. The README and portfolio package deliberately
avoid promising a signed, notarized, packaged, or install-verified app.

Current source builds protect saved clipboard payloads with application-layer
encryption and a login Keychain item, but the local development profile is not a
complete public distribution security boundary. App Sandbox remains disabled by
default, release entitlements are intentionally empty, missing release signing
credentials are reported as `SKIP`, notarization is not wired into release
automation, and install verification does not yet prove a downloaded artifact.

Public distribution would turn those deferrals into user-facing guarantees. That
requires a separate hardening pass instead of a documentation-only portfolio
release.

## Decision

Do not present Forkclip as a public app download until the blockers below have
dedicated implementation, validation evidence, and documentation.

This ADR does not change runtime behavior, release artifacts, storage paths,
Keychain identity, or signing defaults. Local development remains ad hoc signed
by default, and release hardening remains opt-in until the follow-up work is
implemented.

## Distribution Blockers

| Blocker | Current boundary | Required follow-up candidate |
| --- | --- | --- |
| App Sandbox | The default app profile is unsandboxed so existing local build, refresh, smoke, storage, and Keychain behavior stay predictable. | Implement a release sandbox profile only after storage migration and Keychain migration can be validated together with local smoke coverage. |
| Hardened Runtime | `Forkclip/scripts/check-release-signing.sh` can sign with `codesign --options runtime`, but only when a real release identity and explicit apply flag are provided. | Promote Hardened Runtime signing into credentialed release automation and fail the release path when it is absent. |
| Signing identity | Normal development does not require a Team ID, provisioning profile, or Developer ID certificate. | Define the stable release signing identity, bundle identifier, Team ID, and certificate requirements before producing user-facing artifacts. |
| Notarization | No notarytool, stapling, ticket verification, or notarization credential flow is part of the current release path. | Add notarization, stapling, and post-staple verification to release automation after signed artifacts exist. |
| Keychain access behavior | Forkclip currently uses login Keychain service `com.user.forkclip.encryption` and account `symmetricKey` without release access groups. | Implement preferred and legacy Keychain descriptor lookup, access-group support for signed release builds, and migration tests before changing the descriptor. |
| Storage migration | User data is stored under the unsandboxed `~/Library/Application Support/Forkclip` path. | Implement copy-then-verify migration into the sandbox container, conflict handling, diagnostics, rollback behavior, and tests before enabling sandbox defaults. |
| Install verification | Current scripts can refresh or install a local build, but they do not prove that a public `.zip`, `.dmg`, App Store build, or GitHub Release artifact installs correctly. | Add artifact-specific install verification, bundle identity checks, signature assessment, notarization ticket checks, first-launch smoke, and documented rollback/recovery expectations. |
| Validation | CI validates source-level behavior and diff whitespace. Local smoke covers side-effectful app behavior, but neither proves public download readiness. | Define a distribution validation checklist that records source CI, credentialed signing, notarization, packaging, install verification, and local smoke evidence separately. |

## Required Follow-up Candidates

- Sandbox rollout: implement release entitlements with App Sandbox, storage
  container behavior, and smoke/script updates behind an explicit release
  profile.
- Signing profile: define the stable bundle identifier, Team ID, Developer ID or
  Apple Distribution certificate class, provisioning requirements, and
  credentialed failure behavior.
- Notarization pipeline: add notary submission, stapling, ticket verification,
  and post-notarization assessment for each published artifact format.
- Keychain migration: implement preferred/legacy descriptor lookup and
  release-profile access-group behavior without breaking existing encrypted
  history.
- Storage migration: copy existing unsandboxed data into the sandbox container,
  verify readability, and leave the old source available for rollback in the
  first migration release.
- Install verification: define and automate checks for `/Applications`
  installation, Launch Services registration, signature assessment, notarization
  ticket presence, first launch, and representative smoke behavior.
- Distribution documentation: update README, portfolio notes, user docs, and
  developer docs only after artifacts, checksums, notarization, and install
  evidence exist.

## Consequences

Benefits:

- Public app distribution has an explicit blocker list instead of relying on
  scattered caveats.
- The portfolio source repository remains honest about what reviewers can build
  and what users cannot download yet.
- Future implementation PRs can be scoped to one blocker while preserving the
  local development path.

Costs:

- No public app downloads should be advertised until the blocker list is closed.
- Release automation needs credentialed paths that normal contributors cannot
  run.
- Migration, signing, notarization, and install verification evidence must be
  reported separately because source CI alone is not enough.

## Validation

This ADR is design-only. No runtime validation is required for this PR.

Documentation-only changes must run:

```sh
git diff --check
```

Implementation PRs that close any blocker must run the relevant validation from
`docs/developer/validation.md` and must report skipped local-only or
credentialed checks explicitly.
