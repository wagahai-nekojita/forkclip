# Native UI Smoke Decision

## Decision

Keep native UI coverage on the existing local smoke path for now. Do not add XCUITest as the next increment.

The first useful UI workflow is the current `Forkclip/scripts/build-and-refresh-app.sh` plus `Forkclip/scripts/smoke-check.sh` path:

- build and refresh a local `Forkclip.app` bundle
- verify the launched process matches the refreshed binary
- write representative clipboard payloads through the real macOS pasteboard
- verify the local SQLite database records the capture
- run the app's native smoke hook with `FORKCLIP_NATIVE_SMOKE_REPORT`
- check menu bar app identity, appearance behavior, copy feedback enable/disable behavior, and representative multiformat copyback

## Why Not XCUITest Yet

Forkclip is a menu bar app with clipboard, SQLite, Keychain, app launch, and native status item side effects. Broad XCUITest would add setup cost and flake risk before there is one missing UI behavior that cannot be covered by the existing local smoke hook.

Keep XCUITest deferred until a workflow needs true user-level automation, such as:

- menu bar click and popover/window placement assertions that cannot be validated through unit tests or the native smoke report
- settings navigation and persistence across app relaunches
- Dashboard selection or copy behavior that depends on rendered SwiftUI hierarchy rather than manager state

## Current Coverage Boundary

`Forkclip/scripts/smoke-check.sh` is local-only validation. It writes to the system clipboard, reads the user's local Forkclip Application Support database, checks Keychain availability, and can launch the app binary for native smoke reporting. It should not be treated as GitHub Actions CI coverage.

Use this path for runtime changes where local side effects are acceptable. Skip it for docs-only, agent-workflow-only, and isolated unit-test or benchmark harness changes, and report the skip reason.

Use `RUN_NATIVE_UI_SMOKE=0 Forkclip/scripts/smoke-check.sh` only when capture/database validation is needed but native smoke is intentionally out of scope.

## First Follow-up If Needed

If UI gaps remain after local smoke, add one narrow XCUITest workflow rather than a broad suite. The first candidate should be:

1. launch the app from a clean test fixture
2. open the menu bar UI
3. verify the primary history surface appears
4. close without mutating the user's clipboard or persistent database

That work should be a separate Issue and PR because it changes validation infrastructure and may require deterministic app fixture setup.
