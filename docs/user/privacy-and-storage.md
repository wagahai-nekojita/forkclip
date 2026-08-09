# Privacy and Storage

Forkclip stores clipboard history locally and encrypts saved clipboard payloads before writing them to SQLite.

## Local Storage

- Database path: `~/Library/Application Support/Forkclip/forkclip.sqlite`
- Settings path: `~/Library/Application Support/Forkclip/app_settings.json`
- Custom secret patterns path: `~/Library/Application Support/Forkclip/custom_secret_patterns.json`
- Retention policy path: `~/Library/Application Support/Forkclip/retention_policy.json`
- Backups directory: `~/Library/Application Support/Forkclip/Backups`

Forkclip starts with its own local storage identity. It does not read, copy, migrate, or delete earlier local data from other app identities.

Forkclip creates its Application Support and backup directories with owner-only permissions where supported by the local filesystem. Newly created SQLite, settings, retention-policy, and recovery backup files are also set to owner read/write only. This reduces exposure to other local user processes, but it is not a substitute for App Sandbox, SQLCipher, metadata encryption, or full-disk protections.

## Encryption

Forkclip uses a symmetric key stored in the macOS Keychain under the Forkclip service. Text, URL, file URL, RTF, HTML, image payload bytes, and optional Display Titles are encrypted before persistence. New encrypted rows bind ciphertext to row identity with AES-GCM authenticated data, so item content and Display Titles are tied to the item ID, and payload bytes are tied to their item ID and payload ID. When an older database is opened, schema 12 rewrites legacy unbound rows in one transaction; normal reads do not accept unbound ciphertext after that migration. Queryable payload metadata is limited to content type, pasteboard type, rank, byte size, and the item's primary display type. If the key is missing or inaccessible, history may fail to decrypt. The diagnostics panel shows Keychain and decryption status.

Forkclip also stores local metadata for each history item: capture count and last-captured time for repeated external clipboard captures, plus usage count and last-used time for explicit copies from saved history. Usage metadata is updated only when a saved history item is explicitly copied through Forkclip. Display Title text is not stored as plaintext metadata.

## Likely Secret Masking

Forkclip masks high-confidence secrets in history previews, such as recognized API key prefixes, JWTs, private key blocks, explicit `token=` or `password=` assignments, short labeled `pin=`, `otp=`, and `verification_code=` values, Japanese credential labels such as `認証コード=`, and authorization bearer values. Recognized prefixes include common GitHub, GitLab, Anthropic, Stripe, Slack, Google, AWS, and Twilio-style credential identifiers. Normal prose, Markdown, Japanese text, and developer notes should remain visible unless they contain an explicit credential pattern. When Forkclip loads history, existing items are rechecked with the current masking policy and only the local `is_secret` flag is updated. A user-authored Display Title can be shown for a private item while the content preview remains hidden.

Custom secret patterns can add project-specific token formats. Store them as a JSON array at `~/Library/Application Support/Forkclip/custom_secret_patterns.json`:

```json
[
  {
    "name": "Internal deploy token",
    "pattern": "DEPLOY-[A-Z0-9]{16}"
  }
]
```

Patterns are regular expressions. Forkclip rejects invalid expressions, empty matches, overly long patterns, and patterns that match broad normal text samples such as regular prose or URLs.

## Supported Clipboard Formats

Forkclip saves plain text, URL text, file URLs, RTF, HTML, and common image pasteboard payloads such as PNG and TIFF. Unsupported pasteboard-only formats are ignored with diagnostics instead of being stored as unknown raw data.

For non-text-only items, Forkclip keeps a safe display label such as `画像`, `HTML`, or a file name in the encrypted item preview rather than exposing raw payload bytes as preview text. Payload-row preview metadata is not stored in v1.

Forkclip places limits on clipboard work before encryption and again before
database writes: plain text and URL/file URLs are limited to 1 MiB, RTF/HTML to
4 MiB, one image to 16 MiB, and one clipboard change to 20 MiB total. Images
also have dimension and decoded-pixel limits. Oversized content is skipped and
shown as a capacity-limited save result in diagnostics. If other
representations of the same clipboard change fit within the limits, those
representations are saved and diagnostics explicitly show a partial save.
Thumbnails use bounded ImageIO decoding and a bounded in-memory cache.

## Private Mode

Private mode temporarily stops saving new clipboard changes while `非公開` is on. Existing saved history remains available. When private mode is enabled, Forkclip skips the new clipboard change before reading text or payload bytes from the pasteboard.

## Application Blacklist

The blacklist prevents saving clipboard changes from sensitive apps. Forkclip checks the frontmost app before reading clipboard text or payload bytes. The default blacklist includes common password/keychain apps such as 1Password, Apple Keychain/Passwords, Bitwarden, Dashlane, and KeePassXC, and the local blacklist file can add more bundle identifiers.

Blacklist entries match complete bundle identifiers or child bundle identifier prefixes. For example, `com.example.SecretApp` matches `com.example.secretapp` and `com.example.secretapp.helper`, but not `com.example.notsecretapp`.

Forkclip also respects the pasteboard type marker `org.nspasteboard.ConcealedType` and skips those clipboard changes before reading payload data. The source application identity is captured with the change notification, then the allowed event is snapshotted before asynchronous processing; if the pasteboard changes during that snapshot, Forkclip skips the event. If macOS cannot identify the source, Forkclip skips the change rather than guessing. This prevents a later focus switch or copy from changing the blacklist decision for an earlier event.

## Retention

Retention settings limit stored items by count and age. The default keeps up to 100 items and removes items older than 14 days. Favorite items are protected from automatic retention cleanup, but explicit delete still removes them. Stored payloads also have a 256 MiB quota; when it is exceeded, the least recently captured non-favorite history is removed first, with creation time as a tie-breaker. Favorites are not quota-cleanup targets. Cleanup is transactional. If protected favorites already exceed the quota, the database remains available but a new save fails instead of deleting a favorite or partially deleting older history.
