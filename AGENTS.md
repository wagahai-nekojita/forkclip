## Delivery Contract

Bulk investigation is delegated to a read-only worker
(built-in Explore or a read-only subagent). Small reads stay inline.
Implementation may be delegated to a cheaper model only after the
strong model has fixed a precise spec; it is verified by tests,
never by trust.

Findings produced by any AI worker are delivered as:

- claims, each citing at least one re-checkable anchor:
  `path:line`, commit SHA, `command + exit code`, or doc URL + section;
- unknowns, stated explicitly — missing evidence is never
  converted into a claim;
- no verdicts: workers report, they do not decide.

Implementation is delivered as the diff plus green mechanical checks
against the spec. A deviation from spec rejects the diff.

A claim without an anchor is not used. There is no partial credit.
Before findings drive an edit, commit, PR, or decision,
run the promotion-check skill (.claude/skills/promotion-check/SKILL.md).
