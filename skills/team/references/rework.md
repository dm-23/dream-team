# Rework loop

If Reviewer returns `manual` findings or `needs rework`: handoff → Developer with the findings, then Reviewer again (max 2 cycles, then escalate to the user).

Any change made after the batch review — a finding, a user decision — goes back through the Reviewer before the gate; the final review never stands in for it.

## Red criteria

A `Criteria:` line with a red count makes the verdict `needs rework` even with no `manual` finding. Before the rework handoff, when a red criterion carries `disputed — …`, ask via AskUserQuestion with the Reviewer's reason: rework as written / waive this criterion / edit the criterion. On waive, write the criterion line as `- [x] <criterion> — waived: "<the user's words>" (YYYY-MM-DD)` and log it in the Decisions log; on edit, correct the task file and send it to rework. A plain red criterion goes to rework without a question. At the escalation after the two cycles, list every still-red criterion and offer the same three options per criterion.
