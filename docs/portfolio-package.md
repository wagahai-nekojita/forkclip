# Forkclip Portfolio Package

Forkclip is a local-first macOS menu bar clipboard manager for personal use. It keeps recent clipboard items close to the menu bar, adds a larger Dashboard for review and reuse, and stores local history in encrypted SQLite.

This package describes Forkclip as a portfolio source repository. It includes source code, documentation, screenshots, build instructions, and design notes. Prebuilt app downloads are not provided at this stage; reviewers should build from source. The app is not currently signed or notarized for public distribution.

## Feature Summary

- Menu bar quick panel with horizontal, grid, and list layouts.
- Dashboard for dense history browsing, search, source filtering, detail inspection, and copy reuse.
- Clipboard history for plain text, URL text, file URLs, RTF, HTML, and common image payloads.
- Persistent Quick/Favorite items with retention protection.
- Manual folders, queue mode, and private mode.
- Appearance, panel placement, retention, launch, feedback, and privacy settings.
- Local encrypted persistence under `~/Library/Application Support/Forkclip`.

## Screenshot Checklist

Capture fresh screenshots from `Version 1.0 (10)` before publishing portfolio material.

- Quick panel:
  - Horizontal layout with representative text, image, and file history labels visible.
  - Grid layout showing visual density without exposing private clipboard content.
  - List layout or compact panel state if space allows.
- Dashboard:
  - History list, search field, filters, detail area, and copy action visible.
  - Representative labels for plain text, image, file URL, rich text, and URL text.
- Settings:
  - General app settings.
  - Appearance and panel placement controls.
  - Privacy or retention settings.
- Supported formats:
  - Include a representative capture set for plain text, URL text, file URL, image, and rich text/HTML.
  - Use synthetic sample data only; do not capture private clipboard contents.

## Portfolio Copy

Forkclip is a personal macOS clipboard history app built with SwiftUI and AppKit. It focuses on local-first clipboard reuse, fast menu bar access, a searchable Dashboard, and careful handling of multiple pasteboard formats without sending clipboard contents to external services.

## Distribution Caveats

- Forkclip 1.0 is presented as a portfolio source release built from this repository.
- It is not distributed through the App Store.
- It is not packaged as a signed or notarized third-party download.
- It does not provide a public zip, dmg, checksum, GitHub Release artifact, or auto-update channel.
- Basic GitHub Actions CI covers repository validation only. Do not present CI as coverage for local app refresh, clipboard-writing smoke, native UI smoke, signing, notarization, packaging, or install verification.

## Link Guidance

A personal website can link to this repository or this document as portfolio context. Public download wording should wait for a separate distribution decision and hardening pass.
