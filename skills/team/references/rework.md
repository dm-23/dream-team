# Rework loop

If Reviewer returns `manual` findings or `needs rework`: handoff → Developer with the findings (after the Verifier vote below, when there is a `manual` finding), then Reviewer again (max 2 cycles, then escalate to the user).

Any change made after the batch review — a finding, a user decision — goes back through the Reviewer before the gate; the final review never stands in for it.

## Red criteria

A `Criteria:` line with a red count makes the verdict `needs rework` even with no `manual` finding. Before the rework handoff, when a red criterion carries `disputed — …`, ask via AskUserQuestion with the Reviewer's reason: rework as written / waive this criterion / edit the criterion. On waive, write the criterion line as `- [x] <criterion> — waived: "<the user's words>" (YYYY-MM-DD)` and log it in the Decisions log; on edit, correct the task file and send it to rework. A plain red criterion goes to rework without a question. At the escalation after the two cycles, list every still-red criterion and offer the same three options per criterion. In Bug Fix and Small Change, where there is no task file, the waived form is written under the `Criteria:` entry in `status.md → Decisions log`, and an edited criterion is restated there.

An unverified criterion (`— unverified: <what would check it>`) is not red: it never enters this loop, and it reaches the user through "Verify by hand".

## Verifier vote

When a Reviewer report's verdict is `needs rework` and it lists at least one `manual` finding, one handoff → `verifier` (mode `verify`; `inputs`: the baseline, the change set, every `manual` finding to vote on, verbatim with its id and its `path:line`, the task or plan path, the REVIEW-CHECKLIST path; its model from the cell `<workflow>.verifier`). Then: CONFIRMED findings enter the Developer rework handoff; REJECTED ones are logged in the Decisions log as `downgraded to advisory: <verifier's reason>` and not sent; when nothing is confirmed, no finding was passed on unvoted, no criterion is red and the toolchain is green, record the verdict as `approved — N advisory` and run no rework and no second Reviewer pass. When the Reviewer's report also listed unverified criteria, the verdict is `approved — N advisory, K unverified`; when the Reviewer fixed `safe_auto` items, `fixed` stays the base word (`fixed — N advisory`). A `manual` finding whose path field is `—`, and a `manual` finding that is a toolchain failure (critical-zone mode), are not voted on: they enter the Developer rework handoff as they are, and the Decisions log says so. A `needs rework` with no `manual` finding (red criteria only, or a failing toolchain) runs no verifier. In critical-zone mode (the report starts with `Critical zone:`) a REJECTED finding is not downgraded: ask the user via AskUserQuestion with the Reviewer's claim and the verifier's reason, rework / drop. The `rework` count of `routing.log` counts confirmed reworks only.
