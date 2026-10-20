# Workflow: Change Set

Read first: `learnings-check.md` (step 2) · `quorum.md` (step 3) · `full_feature.md` (step 6, only on a `Plan conflicts with convention:` return: Phase 4 says how it is handled) · `rework.md` (step 8) · `operations.md` (step 10)

1. Turn the user's list into numbered items; clarify only items that are ambiguous (≤3 questions total).
2. Learnings check. Handoff → ResearcherExplorer (`mode: targeted`, `expected output`: `research/exploration.md`) once with all items — one file, files per item inside it.
3. Brainstorm ×3 (`phase: solution`) over the whole list; `inputs` is the exploration **path** plus the learnings lines. Quorum per item. Then the evidence route and, if it fires, the reconcile round ("Quorum").
4. Group items into batches by **disjoint file sets**. Write `plans/change-set.md`: per batch → items, files, acceptance criteria, verify by hand; and `tasks/task-{N}-*.md` per item (same format the Architect uses, including its split: `Test files` for every test the item creates or changes, `Acceptance Criteria` only what the diff or a TOOLCHAIN.md command confirms, everything else under `Verify by hand`) — fill each task's `Complexity` honestly: it selects the model tier under "Model routing".
5. AskUserQuestion: approve the change-set plan (approve / edit / reject).
6. Run all batches whose file sets are disjoint **in parallel**: per batch one Developer per item (sequential within a batch if two items share a file). An item whose files are all documentation goes to the DocWriter instead of a Developer, under the same batching rules — it still lands in the single combined final review at step 8, which reviews the whole diff from baseline anyway. A Developer's `Plan conflicts with convention:` return is handled as in Full Feature Phase 4.
7. Tester: one call for the whole change set; it triages per its own table.
8. Reviewer: one combined review of all batches; it judges the whole diff, and its model comes from the cell `change_set.reviewer`. The rework loop in `.claude/skills/team/references/rework.md`.
9. Docs sync: verify PROJECT-RULES.md obligations reported satisfied by the Reviewer.
10. Report; close status.md. Reviewer has classified what the run taught.
