# ADR 0011: Clipboard Resource and Identity Bounds

## Status

Accepted — implemented

## Context

Clipboard input is supplied by other applications. A pasteboard can therefore
contain unusually large text, rich data, or image bytes, and the frontmost app
can change while Forkclip is processing a change notification. A clipboard
manager must bound work before encryption and persistence, and it must not use a
newly focused app as the identity of an earlier clipboard event.

The same boundary applies to local retention settings and stored payloads.
Malformed JSON must not become an unbounded fetch or deletion request, and a
payload quota must not delete a user's explicitly favorited history.

## Decision

Forkclip applies shared resource limits at capture, persistence, and thumbnail
boundaries:

| Resource | Limit |
| --- | ---: |
| Plain text, URL text, and file URL | 1 MiB each |
| RTF and HTML | 4 MiB each |
| One image payload | 16 MiB |
| One clipboard capture | 20 MiB total |
| Stored payloads | 256 MiB total |
| Image dimensions | 16,384 pixels per side and 40 million pixels total |
| In-memory thumbnail cache | 128 entries |

Oversized or over-dimensioned payloads are skipped before encryption. If a
capture still has valid payloads after that filtering, Forkclip saves the valid
payloads and reports a partial, capacity-limited result in diagnostics instead
of claiming an unqualified success. Image thumbnails use ImageIO thumbnail
decoding after the same checks and are kept in a bounded cache. SQLite
persistence checks both each payload and the aggregate 20 MiB capture budget
again, so callers other than the pasteboard monitor cannot bypass either
boundary.

When the stored payload quota is exceeded, Forkclip removes the least recently
captured non-favorite items first, using the original timestamp only as a tie
breaker. The item currently being saved is protected from that cleanup.
Favorite items are never removed by automatic quota or age cleanup. Startup and
manual retention cleanup run in a transaction. If protected favorite payloads
still exceed the quota, the database remains available and a new over-quota
save fails rather than deleting a favorite or partially deleting other history.

The clipboard monitor captures the source bundle identifier in the same poll as
the pasteboard change count. Before scheduling asynchronous processing, the
manager takes an immutable, change-count-bound pasteboard snapshot after the
source passes the blacklist check. If the pasteboard changes during that
snapshot, the event is discarded. If the source app cannot be identified,
Forkclip fails closed before reading payload bytes. Auto Paste stores the target
process ID, bundle ID, and launch date, then verifies all three before focus
activation and again immediately before sending Command-V. A missing bundle ID
cannot form an Auto Paste target.

Retention policy decoding calls the normalizing initializer explicitly and
clamps fetch count, item count, and age to safe ranges. JSON decoding cannot
bypass those bounds.

## Migration and rollback

Schema 12 rewrites legacy unbound AES-GCM ciphertext for item content, Display
Titles, and payload rows to row-bound authenticated ciphertext in one SQLite
transaction. Normal reads reject unprefixed ciphertext; only the migration path
may call the legacy compatibility decryptor. A failed rewrite leaves
`user_version` unchanged and keeps the database unavailable instead of exposing
partially migrated rows.

## Required Tests

- oversized text and image captures are skipped without persistence;
- a mixed capture saves valid payloads while reporting the dropped
  capacity-limited formats;
- unknown source identity fails closed without reading payload bytes;
- a source identity and immutable pasteboard snapshot captured before a focus or
  clipboard switch remain bound to the saved row;
- Auto Paste target matching rejects a different process, bundle, launch, or
  unknown bundle identity;
- retention JSON with extreme integers is clamped;
- quota cleanup removes the least recently captured non-favorite while
  preserving favorites;
- an over-quota favorite database opens, rejects a new over-quota save, and
  leaves failed cleanup atomic;
- persistence rejects an aggregate payload set above the 20 MiB capture budget;
- legacy item, Display Title, and payload ciphertext are rewritten with the
  expected row context, and a failed rewrite does not advance `user_version`;
- WAL and busy-timeout pragmas remain enabled for every database connection.

## Consequences

Benefits:

- Pasteboard-controlled memory, CPU, thumbnail decode, and disk growth are
  bounded at multiple layers.
- Sensitive history cannot be reclassified using a later frontmost app, and
  Auto Paste cannot blindly send input to a replacement process.
- Favorites survive automatic retention and quota cleanup.
- Legacy ciphertext loses its row-swap weakness after migration.

Costs:

- Very large clipboard content is intentionally not saved.
- A database whose favorite payloads alone exceed the quota cannot accept a new
  payload until the user removes data or raises the quota in a future setting.
- Accessibility/TCC behavior for real Auto Paste still needs manual macOS smoke
  validation.

## Validation

The implementation PR ran the SwiftPM test suite and SwiftPM build described in
`docs/developer/validation.md`. The app bundle and Accessibility-dependent
smoke path remain local-only checks and are reported separately.
