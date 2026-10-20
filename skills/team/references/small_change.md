# Workflow: Small Change

Read first: `learnings-check.md` (step 2) · `scope-gate.md` (step 2) · `quorum.md` (step 3) · `rework.md` (step 6) · `operations.md` (close)

1. Clarify if ambiguous (≤3).
2. Learnings check. Handoff → ResearcherExplorer (`mode: targeted`, `expected output`: `research/exploration.md`). Scope gate, from the pointer block's `Scope Count` line.
3. Brainstorm ×3 (`phase: solution`); `inputs` is the exploration **path** plus the learnings lines. Quorum. Then the evidence route and, if it fires, the reconcile round ("Quorum").
4. Present a 2–5 bullet plan (concrete actions, files) via AskUserQuestion for approval.
5. Handoff → Developer (1–2 inline tasks, disjoint files if 2). Then, under the same condition as Bug Fix step 6 — the plan names a test, a rule requires one, or an existing test pins the changed behaviour — handoff → Tester, one call, model from the cell `small_change.tester`. Record the decision in status.md.
6. Handoff → Reviewer (single pass). The rework loop in `.claude/skills/team/references/rework.md`.
7. Report; close status.md.
