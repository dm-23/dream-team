# Workflow: Full Feature

Read first: `quorum.md` (Phases 1–3) · `learnings-check.md` (Phase 2) · `rework.md` (Phase 4) · `operations.md` (Phase 6)

Phase 1 — Intake: Brainstorm ×3 (`phase: questions`); quorum; ask 3–7 questions via AskUserQuestion.

Phase 2 — Research & design: learnings check. Write `plans/draft-plan.md` with the task and a `## User decisions (binding)` section holding the intake answers, nothing else. Handoff → ResearcherExplorer (`mode: wide`, draft-plan path); it appends `## Repository Analysis & Batch Suggestions`. Then Brainstorm ×3 (`phase: solution`); `inputs` is the draft-plan **path** plus the learnings lines. Quorum; append `## Approach` and the simplicity statement to the draft plan; evidence route, whose `inputs` also carries the files `## Approach` names; reconcile if it fires, each resolution appended to `## Approach`. The wide pass and every open-facts pass of this run take the cell `researcher-explorer:wide`.

Phase 3 — Architecture: handoff → Architect. Three outcomes: a plan; a block headed `Research needed:` listing files or facts → one open-facts pass with its list, `expected output`: the matching subsection of the draft plan (`### Neighbours in files that grow` for files, `### Answers to open facts` for facts), apply trigger 2 to its pointer block, then the Architect again, once per run, a second halt → AskUserQuestion with the list; or `Design decision needed:` → "Quorum" trigger 3. Verify `detailed-plan.md` has `## Public API Surface`, `## Simplicity Justification`, `## Documentation Obligations` and a `## Batching Strategy` with files per batch — if not, send the Architect back.

Then handoff → `plan-auditor` (mode `audit`; `inputs`: the plan path, every task path, the knowledge dir, the baseline; `expected output`: `plans/plan-audit.md`; its model from the cell `full_feature.plan-auditor`). Read only its pointer block. On `rethink`, skip the Architect response: the audit goes to the gate as it is, under `Decisions needed:`, with the auditor's verdict first. Otherwise, with any blocker or major: one handoff → Architect with `audit: <path>`; verify `## Audit response` exists and that `## Public API Surface`, `## Simplicity Justification`, `## Documentation Obligations` and `## Batching Strategy` still do, since the response edits the plan; a finding the Architect disputes goes into the gate question's `Decisions needed:` line. Exactly one audit and one response per run; a second disagreement is the user's at the gate. Record the verdict in status.md phase 3.

**Resumed runs designed under 4.1.0.** On resume at phase 2 or 3, open `plans/draft-plan.md`. Without `## Repository Analysis & Batch Suggestions` and with anything beyond `## User decisions (binding)`, it was designed before the research: run the wide pass now, then the Architect. With only the user decisions, or absent, continue Phase 2 from the wide pass. With the research section and no `## Approach`, continue from the Brainstorm quorum. Never recreate an existing draft plan.

**Resumed runs approved under 4.2.0.** A plan already approved before 4.3.0 is not audited.

**Stop & Approval Gate:** Present `detailed-plan.md` via AskUserQuestion. The question text carries, before the options, the plan's `## Public API Surface` section verbatim and the batch list (batch names, task titles), then the plan path for the rest. If the section runs past about forty lines, show type and member names only and name the section. Before the options it also carries the line "Audit: <verdict>, <B> blocker(s) and <M> major(s) fixed, <D> disputed (see `plans/plan-audit.md` and `## Audit response`)", then the line `Decisions needed: <each disputed finding as "#n — <claim> — Architect: <reason>">`, or `Decisions needed: none`. The options:
1. "Approve plan and PAUSE execution (recommended: execute in a fresh session to save context)"
2. "Approve plan and CONTINUE execution in current session"
3. "Approve with changes / Reject"

If Option 1 ("Approve and PAUSE") is selected:
- Update `status.md` and set `phase=3.5 (Plan Approved - Awaiting Implementation)` in `.team-mode`.
- Output the Pause Instruction Template (below) containing the exact prompt for resuming in a clean session.
- Stop execution here. Do NOT proceed to Phase 4 in this session.

Phase 4 — Implementation: 
Execute batches according to the Batching Strategy. For each batch:
1. Per task, run ResearcherExplorer (`mode: targeted`) **only when the task needs it**: when its `Complexity` is `medium` or `high`, or when its `Insertion Points` line reads `not established`. A `Complexity: low` task with both `Files` and `Insertion Points` filled goes straight to the Developer, whose handoff then carries the task path plus `plans/draft-plan.md → ## Repository Analysis & Batch Suggestions` in place of an exploration path — the wide pass already verified those paths. List the tasks you skipped it for in status.md → "Process notes". Then: Developers in parallel → Tester → Reviewer. The Reviewer's toolchain run is the first batch-wide check; nothing before it is one. A task whose files are all documentation goes to the DocWriter instead of a Developer; the Batching Strategy has already placed it after the code it describes, so the DocWriter checks its claims against that code. Its model is the cell `full_feature.doc-writer`; a documentation-only task gets no Tester call.
   Rework: if the Reviewer returns `manual` findings or `needs rework`, the rework loop in `.claude/skills/team/references/rework.md` inside this batch. A Developer that returns `Plan conflicts with convention:` has not coded: ask via AskUserQuestion — keep the contract as planned, or adopt the file's convention — record the answer in "Decisions log", correct every task file whose `Contract` or `Description` names that member, then hand the task to the Developer again. A `⚠️ Convention note:` in a task file is not a conflict; the Reviewer judges it. Any change made after the batch review — a finding, a user decision — goes back through the Reviewer before the gate; the final review never stands in for it.
   Batches the Batching Strategy marks parallel-safe with each other may run as one wave; the gate below then comes once, after every batch of the wave is approved. Record the wave in "Process notes".
2. **Batch Completion Gate (STOP between batches):** When Reviewer approves Batch {N}, **DO NOT** automatically start the next batch. If status.md → "Verify by hand" holds items for this batch, list them in the question text before the options. Ask via AskUserQuestion:
   - **Option 1 (Commit & Continue):** Commit Batch {N} changes and execute the next batch directly in THIS session.
   - **Option 2 (Commit & Fresh Session - Recommended):** Commit Batch {N} changes, pause execution, and output the command to start the next batch in a fresh session.
   - **Option 3 (Custom):** Wait for user instructions.

3. **If Option 2 is selected:**
   - Run `git commit` for Batch {N}.
   - Update `status.md` and `.team-mode` (`phase=4.{N} Batch {N} Complete - Awaiting the next batch`).
   - Output the fresh session prompt:
     ```text
     Batch {N} completed and committed!
     To execute the next batch in a fresh session:
     1. Run /clear or open a new terminal session.
     2. Run: /team resume {context_id}
     ```
   - Stop execution here.

Phase 5 — Final review: Reviewer reviews ALL changes against baseline, runs the full toolchain, confirms documentation obligations, classifies what the run taught. Build/test failures → Reviewer fixes (max 2) → escalate to the user.

Phase 6 — Close: summarize, update status.md, mark `[DONE]`, delete the marker. Offer (do not perform) a commit via AskUserQuestion: "Commit now with message '...' / I'll commit myself". The question names every item from the Reviewer's `After commit:` line, or says there are none. If `TOOLCHAIN.md → Operations` has a deploy row, offer it next, under "Operations"; never before the commit.

### Pause Instruction Template

When the user approves the plan and selects Option 1 (PAUSE for a fresh session), output the following response (synthesized in the user's task language):

```markdown
Implementation plan approved and saved to:
`.dream-team-tracking/{context_id}/plans/detailed-plan.md`

To run the implementation phase in a **clean session** (recommended to optimize context size and token limits):

1. Clear current context or open a new session (`/clear` or start a new CLI instance).
2. Paste and run the following command:

`/team resume {context_id}`
```
