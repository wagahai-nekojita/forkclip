# Release Notes

These are local development release notes for repository-built Forkclip app bundles. They are not public app distribution release notes and do not imply signed, notarized, or downloadable release artifacts.

## 1.0

- Renamed the Swift package, executable target, app bundle, user-facing identity, local scripts, active docs, CI paths, and repo-local agent workflow to `Forkclip`.
- Set the runtime app version to `1.0 (10)`.
- Reset the local persistence identity to `~/Library/Application Support/Forkclip/forkclip.sqlite` and the Keychain service to `com.user.forkclip.encryption`.
- Removed automatic legacy data and Keychain lookup from production startup; earlier local data remains untouched but is not imported by Forkclip.
- Rebuilt app icons, `AppIcon.icns`, and the menu bar template icon from `Forkclip/Assets/forkclip-icon.png`.
- Added clipboard resource bounds, bounded image thumbnails, immutable change-bound snapshots, source-identity and Auto Paste race checks, transactional non-favorite payload-quota cleanup, retention-policy normalization, and schema 12 legacy-ciphertext re-encryption.

## 0.4.0

- Added multiformat clipboard v1 capture and copy-back for plain text, URL text, file URLs, RTF, HTML, and common image payloads.
- Added Dashboard type labels for image, file, and rich clipboard history so non-text captures are not shown as plain text.
- Added encrypted payload persistence for multiformat clipboard rows while keeping queryable metadata limited to type, pasteboard type, rank, byte size, and primary display type.
- Tightened multiformat validation with real pasteboard image smoke modes and stale app launch detection.
- Added System/Light/Dark appearance mode control.
- Refreshed app and menu bar icons, including a 36x36 template menu bar icon.
- Added successful save/copy feedback with a quiet bundled sound, menu bar cushion animation, and Settings toggles to disable each feedback channel.
- Added quick panel placement settings for bottom, top, left, and right screen-edge layouts.
- Lowered the default compact quick panel height and made top/bottom panels responsive to visible screen width.
- Simplified the bottom quick panel with a single slim toolbar, folder chips, overflow actions, and larger horizontal history cards.
- Polished the menu bar quick panel with a richer dark glass surface, grouped controls, and Dashboard-aligned history cards.
- Added a separate Dashboard window for high-density history browsing, filtering, inspection, and copy reuse.
- Added persistent Quick/Favorite history items with favorite-only filtering and retention protection.
- Bumped the local release version to `0.4.0 (4)`.

Known local release limits:

- This release is intended for personal local use from the repository-built `Forkclip.app`.
- App Store distribution, signed/notarized packaging, zip/dmg release artifacts, checksums, and GitHub Release publishing are not part of this local 0.4.0 release.
- At release cut, GitHub Actions CI was not configured; release confidence relied on the recorded local build, test, Xcode test, app refresh, and smoke validation evidence. Basic repository CI was added afterward as a development follow-up and does not replace local app refresh, clipboard-writing smoke, native UI smoke, signing, notarization, or packaging validation.

## 0.3.1

- Improved main panel usability with new storage defaults, Horz wheel scrolling, and clearer Queue/Private controls.
- Preserved existing retention-disabled settings when local retention policy files are missing or corrupt.
- Updated the local app refresh script so installed development builds update when bundle contents change, even if the version string is unchanged.

## 0.3.0

- Renamed the user-facing app identity to `Forkclip`.
- Refined the main menu bar history panel.
- Added a polished Settings window.
- Added layout and panel size customization.
- Added manual folder organization for history items.
- Added launch-at-login settings for macOS 13 or later.

## Compatibility Notes

- The Swift package target is `Forkclip`.
- The local development app bundle is `Forkclip.app`.
- The bundle identifier is `com.user.forkclip`.
- The local Application Support directory is `~/Library/Application Support/Forkclip`.

Forkclip uses its own Application Support directory and Keychain service. Earlier local data and Keychain entries from other app identities are not read, migrated, copied, or deleted.
