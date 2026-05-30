# ADR 0002: Folder Management Data Model

## Status

Accepted

## Context

Forkclip history can now grow beyond a short visual strip. Users need local organization without changing the clipboard payload model or introducing sync semantics.

## Decision

Use manual folders as additive local metadata:

- `clipboard_folders` stores folder identity, display name, color token, sort order, and timestamps.
- `clipboard_item_folders` stores item-to-folder assignments.
- `All` and `Unfiled` are derived UI selections, not persisted folders.

Deleting a folder removes only folder assignments. It does not delete clipboard items. Deleting or retention-pruning an item removes its folder assignment rows with the item.

## Deferred Decisions

- Smart folders and saved rules.
- Multi-select batch operations beyond move-to-folder actions.
- Pinned/favorite retention protection.
- Sync or shared folder identity.

## Validation

Implementation PRs must include database tests for folder CRUD, assignments, folder deletion preserving items, and item deletion clearing assignments.
