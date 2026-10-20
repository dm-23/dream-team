# Workflow: Bug Fix

Read first: `learnings-check.md` (step 2) · `scope-gate.md` (step 3) · `quorum.md` (step 4) · `rework.md` (step 8) · `operations.md` (close)

1. Clarify (symptoms, reproduction, environment; ≤3 questions).
2. Learnings check.
3. Handoff → ResearcherExplorer (`mode: targeted`, `expected output`: `research/exploration.md`). Scope gate, from the `Scope Count` line of its pointer block — you do not read the report.
4. Brainstorm ×3 (`phase: diagnosis`); each handoff's `inputs` is the exploration **path** plus the learnings lines, never the exploration text. Quorum on root cause and fix. Then the evidence route and, if it fires, the reconcile round ("Quorum").
5. AskUserQuestion: "Problem: X. Cause: Y. Proposed fix: Z (files: ...)". The fix must be surgical — strip refactoring.
6. On approval: handoff → Developer (inline task plus the exploration **path** — never the notes themselves; you have not read them and do not need to). Then, when the approved fix needs a test — the user asked for one, `PROJECT-RULES.md` requires one, or the fix changes behaviour an existing test pins — handoff → Tester, one call, with the test cases from the approved fix in `inputs`; the Developer never writes tests, so a fix without this call ships untested or not at all. Its model is the cell `bug_fix.tester`. Record `Tests (Tester: run)` or `skipped — reason` in status.md → "Decisions log" either way.
7. Handoff → Reviewer (single pass, baseline attached). Reviewer classifies what the run taught (its Step 5).
8. Rework: `.claude/skills/team/references/rework.md`.
9. Report; close status.md.
