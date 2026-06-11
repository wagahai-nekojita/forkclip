# Validation

Use the smallest validation that proves the current change. Do not report checks as passed unless they were run after the final relevant change.

## Runtime Changes

```sh
cd Forkclip
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 \
  swift test --scratch-path /tmp/forkclip-validation-test-build
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 \
  swift build --scratch-path /tmp/forkclip-validation-build
cd ..
git diff --check
```

When `swift test` only shows build completion, treat it as a test-target compile check and do not report it as XCTest execution. Run `Forkclip/scripts/run-xcode-tests.sh` on a machine with full Xcode for an explicit XCTest-only validation path.

## GitHub Actions CI

Pull requests and pushes to `main` run the basic CI workflow in `.github/workflows/ci.yml`.

CI covers `git diff --check`, runtime script syntax, SwiftPM build, and SwiftPM tests on `macos-26` where the hosted runner toolchain supports the package Swift tools version. It does not claim coverage for clipboard-writing smoke checks, app bundle refresh, native UI smoke, signing, notarization, release artifacts, or GitHub Release publishing.

## Release Signing Check

```sh
RELEASE_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
  APPLY_RELEASE_SIGNING=1 \
  Forkclip/scripts/check-release-signing.sh
```

The check uses `Forkclip/Release.entitlements` and Hardened Runtime signing. The current entitlements file is intentionally empty until sandbox or Keychain access-group migrations are implemented. Missing signing credentials are reported as `SKIP` by default, not as a passed release-signing validation. Use `REQUIRE_RELEASE_SIGNING=1` when a credentialed environment must fail instead of skip.

## App Smoke

```sh
Forkclip/scripts/build-and-refresh-app.sh
```

The smoke check writes to the system clipboard, verifies the local SQLite database, and runs the native UI smoke hook for appearance, template menu icon, copy feedback enable/disable checks, and representative multiformat copyback checks. It is appropriate for runtime behavior changes when local side effects are acceptable.

SQLite uses WAL mode. When removing a local smoke database, remove the database file and the matching `-wal` and `-shm` sidecar files together.

The refresh script also creates or updates the local `Forkclip.app` bundle, bundles `docs/user` as `Contents/Resources/ForkclipUserDocs`, updates an existing `/Applications/Forkclip.app` when its bundled contents are stale, and verifies that the launched Forkclip process matches the refreshed binary hash before running smoke checks.

Use `FORKCLIP_SMOKE_MODE=image` or `FORKCLIP_SMOKE_MODE=mixedImageFileURL` with `Forkclip/scripts/smoke-check.sh` to exercise image-only or CleanShot-style image plus file URL capture through the real system pasteboard and running monitor.

If the app starts slowly, rerun `Forkclip/scripts/smoke-check.sh` after the monitor has started and report both results.

## Manual Auto Paste Smoke

CI and the scripted app smoke checks do not prove the user-granted Accessibility/TCC path required for direct Auto Paste. For Auto Paste changes, run this manual local smoke when side effects are acceptable:

1. Confirm the running app path with `pgrep -fl Forkclip`.
2. Confirm that the same `Forkclip.app` is enabled in System Settings > Privacy & Security > Accessibility.
3. If the app was rebuilt with an ad hoc signature and Auto Paste fails, remove the Forkclip Accessibility entry, add the current app bundle again, enable it, and restart Forkclip.
4. Open TextEdit or another editable target and place the cursor in an empty document or text field.
5. Open Forkclip, enable Auto Paste, and click a Clipboard Item.
6. Pass condition: the item is inserted into the target app.
7. Failure fallback: the item remains copied to the system pasteboard and can be pasted manually.

Report whether the app bundle was ad hoc signed or signed with a stable identity. Ad hoc local rebuilds can invalidate the previously granted Accessibility entry because macOS may treat the new binary as a different event-posting client.

The native UI smoke/XCUITest boundary is documented in [native-ui-smoke.md](native-ui-smoke.md).

Localization strategy and visible-copy testing expectations are documented in [localization.md](localization.md).

## Focused State Performance

```sh
Forkclip/scripts/measure-focused-state-performance.sh
```

Use this when measuring focused SwiftUI-observed state model updates. It does not measure full SwiftUI redraw or large-history rendering.

## Large History Performance

```sh
Forkclip/scripts/measure-large-history-performance.sh
```

Use this when measuring dashboard filtering and frequent-item ordering against the representative large-history fixture. It does not measure SwiftUI redraw, persistence fetches, or image thumbnail decoding.

## Internal Agent Workflow

```sh
bash -n scripts/check_agent_workflow.sh
bash scripts/check_agent_workflow.sh
```

This check is for the private development repository's agent workflow files. It is not part of the public portfolio source package.

## Script Changes

```sh
zsh -n Forkclip/scripts/build-and-refresh-app.sh \
  Forkclip/scripts/check-release-signing.sh \
  Forkclip/scripts/install-to-applications.sh \
  Forkclip/scripts/measure-focused-state-performance.sh \
  Forkclip/scripts/measure-large-history-performance.sh \
  Forkclip/scripts/run-xcode-tests.sh \
  Forkclip/scripts/smoke-check.sh
```

Use this document as the public validation reference. Private development workflow material is intentionally excluded from the portfolio source package.
