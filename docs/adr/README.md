# Architecture Decision Records

This directory records durable architecture decisions for Forkclip. The ADRs are kept in the portfolio source repository because they explain why the app handles clipboard formats, local storage, encryption, migration safety, and release hardening the way it does.

Implementation status below is portfolio-facing status for the current repository snapshot. It is intentionally separate from each ADR's decision status so the public README does not overstate deferred release-hardening work.

| ADR | Topic | Decision status | Current implementation status |
| --- | --- | --- | --- |
| [0001](0001-multiformat-clipboard-data-model.md) | Multi-format Clipboard Data Model | Accepted | Implemented. Forkclip stores clipboard events with typed payload rows for text, URL, file URL, RTF, HTML, and image data. |
| [0002](0002-folder-management-data-model.md) | Folder Management Data Model | Accepted | Implemented. Manual folders and item assignments are part of the local data model and UI. |
| [0003](0003-sandbox-signing-keychain-policy.md) | Sandbox, Signing, and Keychain Policy | Accepted | Partially implemented. Release entitlements and a Hardened Runtime signing check exist; App Sandbox, Keychain access groups, and user-presence key policy remain deferred. |
| [0004](0004-sqlcipher-and-metadata-encryption-strategy.md) | SQLCipher and Metadata Encryption Strategy | Accepted | Implemented as a deferral. Forkclip uses application-layer AES-GCM for clipboard content and does not include SQLCipher in this portfolio source release. |
| [0005](0005-migration-rollback-policy.md) | Migration Rollback Policy | Accepted | Partially implemented as an active policy. Current schema migrations use transactional boundaries and tests for representative failure behavior; future storage, Keychain, or database-file encryption migrations must provide separate evidence. |
| [0006](0006-legacy-ciphertext-reencryption-plan.md) | Legacy Ciphertext Re-Encryption Plan | Accepted | Partially implemented. Current migrations and tests cover legacy text/payload upgrade paths; full removal of legacy read support remains deferred. |
| [0007](0007-encryption-key-rotation-workflow.md) | Encryption Key Rotation Workflow | Accepted | Deferred. Planned key rotation is documented but not implemented. |
| [0008](0008-sandbox-storage-migration-plan.md) | Sandbox Storage Migration Plan | Accepted | Deferred. Sandbox storage migration is documented but not implemented, and App Sandbox is not enabled by default. |
| [0009](0009-keychain-migration-plan.md) | Keychain Migration Plan | Accepted | Deferred. Keychain descriptor migration is documented but not implemented; the current app still uses the existing service/account descriptor. |

## Reading Order

For a quick technical review, start with:

1. [0001: Multi-format Clipboard Data Model](0001-multiformat-clipboard-data-model.md)
2. [0004: SQLCipher and Metadata Encryption Strategy](0004-sqlcipher-and-metadata-encryption-strategy.md)
3. [0005: Migration Rollback Policy](0005-migration-rollback-policy.md)

For release-hardening boundaries, read ADRs 0003, 0007, 0008, and 0009 together. Those decisions explain why this repository is a portfolio source repository and not a public app distribution channel.
