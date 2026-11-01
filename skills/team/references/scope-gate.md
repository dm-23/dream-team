# Workflow fix (after the targeted research pass)

Step 0 announced a provisional class from the task's words. The research pass is where the evidence arrives: read the `Scope Count` and `Wiring/surface` lines of the ResearcherExplorer's pointer block — the report itself stays unread — and fix the workflow from them:

- total ≤ 3 files and `Wiring/surface: none` → **Small Change**, or **Bug Fix** when the task reports something broken (a symptom, an error, a failing behaviour) — the provisional class decides between the two.
- a task that is a list of independent items (each item's files disjoint from the others', per the exploration's files-per-item), whatever the count → **Change Set**.
- otherwise, total > 3 files or `Wiring/surface` names anything → **Full Feature**.

Announce the fixed workflow in one line. When it differs from the provisional class: set `**Workflow:**` in `status.md` and `workflow=` in the marker to the fixed one, keep the `context_id` and the directory as they are (renaming orphans the marker), log `Workflow fixed: {workflow} (provisional {class}) — Scope Count …; Wiring/surface …` in the Decisions log, and continue in the fixed workflow's file from the step after its research pass — the exploration is already written and is not redone. One exception: a fix to **Full Feature** enters `full_feature.md` at Phase 1, because its research is the wide pass appended to `plans/draft-plan.md`, which the Architect requires; that wide pass carries the targeted exploration's path under `inputs` as a starting point and takes the cell `researcher-explorer:wide`. Model cells from here on are the fixed workflow's; calls already made are not rerun.

Ask via AskUserQuestion only when the user's own words named a workflow ("as a Bug Fix", "switch to Change Set") and the evidence disagrees: "You asked for {X}; the research found {evidence}, which fits {Y}. Continue as {X} / switch to {Y}". Record the answer. Analyze and Docs are decided at Step 0 and never pass through here.
