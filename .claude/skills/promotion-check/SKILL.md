---
name: promotion-check
description: Verify AI-delivered findings before they drive an edit,
  commit, PR, or decision. Trust-collapse grading.
---

Run this before promoting any worker findings.

1. Classify claims.
   Critical: permission boundaries, security, secrets/private paths,
   validation pass/fail, scope boundaries, "safe to delete/change",
   model or config bindings.
   Anything ambiguous is critical.

2. Check every critical claim's anchor. Never sample these.
   Do not clear a minefield by stepping on 20% of it. Walk every row.

3. Sample normal claims: K = min(3, ceil(0.2 × n)),
   biased toward highest consequence and lowest confidence,
   plus one random pick when possible.

4. Check anchors only, not the whole task:
   the file:line says what the claim says;
   the command re-runs with the same exit code;
   the SHA exists; the doc section exists.

5. Trust collapse: if any checked anchor fails,
   reject the entire delivery. Do not cherry-pick survivors.
   Retry with a better prompt, or escalate.

6. Promote only if all critical claims verify, all samples pass,
   and the unknowns are acknowledged in whatever you write next
   (commit body, PR body, or decision).
