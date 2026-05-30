# Build and Run

Forkclip is implemented as a Swift Package executable target named `Forkclip`. The app bundle and copied executable are named `Forkclip.app` and `Forkclip`.

## Requirements

- macOS 12 or later.
- Swift toolchain compatible with `swift-tools-version: 6.2`.
- Command Line Tools or Xcode.

## Build

```sh
cd Forkclip
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 \
  swift build --scratch-path /tmp/forkclip-validation-build
```

## Test

```sh
cd Forkclip
env CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache SWIFTPM_ENABLE_PLUGINS=0 \
  swift test --scratch-path /tmp/forkclip-validation-test-build
```

With Command Line Tools only, this is a test-target compile check. For actual XCTest execution, run from the repository root on a machine with full Xcode:

```sh
Forkclip/scripts/run-xcode-tests.sh
```

## Refresh the Local App Bundle

```sh
Forkclip/scripts/build-and-refresh-app.sh
```

The script creates the local `Forkclip.app` bundle structure when needed. It copies the built binary as `Contents/MacOS/Forkclip`, then copies `Info.plist`, app assets, and `docs/user` into `Contents/Resources/ForkclipUserDocs`.

If `/Applications/Forkclip.app` already exists, the script compares the installed bundle with the refreshed local bundle and updates the installed app when the binary, plist, assets, or bundled user docs are stale. For a refresh without launch or clipboard smoke side effects, run:

```sh
LAUNCH_APP=0 RUN_SMOKE=0 Forkclip/scripts/build-and-refresh-app.sh
```

## Auto Paste and Accessibility During Local Development

Auto Paste sends a synthetic Paste shortcut to the app that was active before the quick panel opened. That event-posting step requires macOS Accessibility permission for the exact Forkclip app bundle currently running.

Local development refreshes are ad hoc signed by default through `codesign --sign -`. For ad hoc signatures, the designated requirement can be tied to the binary cdhash. Rebuilding and refreshing `Forkclip.app` can therefore make a previously granted Accessibility entry stale, even when the bundle identifier and app name did not change.

When Auto Paste copies the item but does not paste into the target app after a rebuild:

1. Quit Forkclip.
2. Open System Settings > Privacy & Security > Accessibility.
3. Remove existing Forkclip entries.
4. Add the current app bundle, usually `<repo-root>/Forkclip.app` for repository builds.
5. Enable Forkclip and restart the app.

To avoid repeated Accessibility permission churn, sign local test bundles with a stable codesigning identity when one is available:

```sh
CODESIGN_IDENTITY="Apple Development: Example (TEAMID1234)" \
  RUN_SMOKE=0 \
  Forkclip/scripts/build-and-refresh-app.sh
```

The repository does not require a local signing identity for normal development. If `security find-identity -v -p codesigning` reports `0 valid identities found`, the default ad hoc path is expected and the Accessibility entry may need to be refreshed after rebuilds.

## Install to Applications

```sh
Forkclip/scripts/install-to-applications.sh
```

This copies the local app bundle to `/Applications/Forkclip.app`, touches the bundle, and refreshes the Launch Services registration.

## Release Signing Check

Local development refreshes stay ad hoc signed by default. Release signing uses the explicit entitlements file at `Forkclip/Release.entitlements` and Hardened Runtime signing through `Forkclip/scripts/check-release-signing.sh`. The current entitlements file is intentionally empty until sandbox or Keychain access-group migrations are implemented; Hardened Runtime is enabled by the signing option.

Build the local bundle without launching or running clipboard smoke checks:

```sh
LAUNCH_APP=0 RUN_SMOKE=0 Forkclip/scripts/build-and-refresh-app.sh
```

Then run the release signing check with a real signing identity:

```sh
RELEASE_CODESIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID1234)" \
  APPLY_RELEASE_SIGNING=1 \
  Forkclip/scripts/check-release-signing.sh
```

When `RELEASE_CODESIGN_IDENTITY` is missing, the script reports `SKIP` instead of treating unsigned local validation as a release-signing pass. Set `REQUIRE_RELEASE_SIGNING=1` in credentialed release automation when missing credentials should fail the run.
