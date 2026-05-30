# Development Process

Forkclip uses an AI-assisted, human-owned engineering workflow. The important part is not the tooling implementation; it is the discipline around scope, design decisions, validation, and review.

## Working Principles

- Keep changes small enough to review.
- Define a single goal before implementation.
- Separate scope from non-goals.
- Record validation commands and their actual results.
- Treat docs impact as part of the work, not an afterthought.
- Keep follow-up work classified instead of leaving it only in chat or prose.
- Do not present unrun validation, release readiness, or distribution readiness as complete.

## Issue-Scoped Work

Implementation work starts from an Issue or an Issue draft. The Issue defines:

- problem or motivation;
- goal;
- scope;
- non-goals;
- acceptance criteria;
- validation expectation;
- docs impact expectation;
- review focus;
- follow-up classification.

This keeps a PR from mixing unrelated feature work, bug fixes, refactors, agent workflow changes, and release decisions.

## Decision Records

Forkclip uses Architecture Decision Records for decisions that are durable, surprising without context, and based on real trade-offs. ADRs are used for topics such as:

- multi-format clipboard data modeling;
- sandbox, signing, and Keychain policy;
- application-layer encryption versus SQLCipher;
- migration rollback behavior;
- key rotation and Keychain migration boundaries.

The ADRs are not a replacement for code. They explain why the code has the current shape and where future hardening work remains deferred.

## Validation Evidence

Validation is selected to match the change:

- documentation-only changes use documentation scans and whitespace checks;
- runtime changes use SwiftPM build/test validation;
- script changes use shell syntax validation;
- app behavior changes may use local smoke checks that intentionally touch the clipboard and local app bundle;
- release signing checks are explicit and do not pass silently when credentials are missing.

The rule is simple: do not claim a check passed unless it was run after the final relevant change. If a check is skipped, the reason is stated.

## AI Assistance

AI is used as an accelerator for investigation, drafting, implementation, and review preparation. Human ownership stays with the project maintainer:

- the human defines goals and accepts or rejects trade-offs;
- generated changes are checked against repo files, Issues, ADRs, and validation output;
- implementation is constrained by existing architecture and local docs;
- final claims are based on evidence, not chat momentum.

Detailed automation and internal workflow files are maintained separately and are outside this portfolio source release.

## Review And Closeout

Each PR should make it easy to answer:

- what changed;
- why it belongs in one PR;
- what did not change;
- what validation ran;
- what docs changed;
- what risks remain;
- what follow-up work is tracked.

Merge and publicization decisions remain human-controlled.
