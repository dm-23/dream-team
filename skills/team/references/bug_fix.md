# Workflow: Bug Fix

Read first: `learnings-check.md` (step 2) · `scope-gate.md` (step 3) · `quorum.md` (step 4) · `rework.md` (step 8) · `operations.md` (close)

1. Clarify (symptoms, reproduction, environment; ≤3 questions).
2. Learnings check.
3. Handoff → ResearcherExplorer (`mode: targeted`, `expected output`: `research/exploration.md`). Scope gate, from the `Scope Count` line of its pointer block — you do not read the report.
4. Brainstorm ×3 (`phase: diagnosis`); each handoff's `inputs` is the exploration **path** plus the learnings lines, never the exploration text. Quorum on root cause and fix. Then the evidence route and, if it fires, the reconcile round ("Quorum").
5. AskUserQuestion: "Problem: X. Cause: Y. Proposed fix: Z (files: ...)". The fix must be surgical — strip refactoring.
6. On approval, when the approved fix needs a test — the user asked for one, `PROJECT-RULES.md` requires one, or the fix changes behaviour an existing test pins — handoff → Tester before the Developer, one call, with the test cases from the approved fix and the exploration **path** in `inputs`, `expected output`: the Tester's block; the Tester writes the test and runs it against the unfixed code. Its model is the cell `bug_fix.tester`. On `Run result (before fix): fail` or `compile error`, continue to the Developer. On `pass`, ask via AskUserQuestion: "The test does not reproduce the bug: adjust the test cases / continue without a reproducing test"; record the answer in status.md → "Decisions log"; on adjust, one more Tester call with the new cases, and a second `pass` continues without a reproducing test. Then handoff → Developer (inline task plus the exploration **path** — never the notes themselves; you have not read them and do not need to). The Developer never writes tests, so a fix without the Tester call ships untested or not at all. The Tester's block goes into the Reviewer's `inputs` at step 7. Record `Tests (Tester: run)` or `skipped — reason` in status.md → "Decisions log" either way.
7. Handoff → Reviewer (single pass, baseline attached). Reviewer classifies what the run taught (its Step 5).
8. Rework: `.claude/skills/team/references/rework.md`.
9. Report; close status.md.
