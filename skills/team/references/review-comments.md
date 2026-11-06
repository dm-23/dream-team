# Review comments and complaints about delivered code

Read first: `amendments.md` (step 8) · `quorum.md` (step 4)

A reviewer's comment on a pull request is a claim to verify, not a defect by definition. So is the developer's complaint about code the team delivered ("over-engineered", "why a poller", "this is not what was needed"). Its author may lack context, a question asks for an answer, and a suggestion ("maybe X") is not a requirement. This file runs before any design: it decides which items need code at all, and it turns every item that holds into a lesson about how the code came to be.

**When it runs.**
- `follow-up.md` class 6: one comment or complaint about a closed run. The linked Bug Fix enters here instead of at its steps 3–4.
- A new task that quotes or lists reviewer comments on a pull request, in any code-changing workflow. It runs after the workflow's research step and before its design step (the step a workflow file names when it points here). Turn the task into numbered items first, one per comment.

**1. The delivered change.** For a follow-up it is the parent run's change, as `follow-up.md` class 2 names it. For a new task it is the pull request's diff. When the task does not name the base branch of the pull request, ask for it with the workflow's clarification step; the question counts toward its limit. Put the base branch under `constraints` of the research handoff; its pointer block returns `Merge base:`. That sha is the baseline of step 3.

**2. Candidate runs.** The runs whose decisions may have produced the code. List the tracking directory (`ls -d .dream-team-tracking/*/`) and read the first lines of each `status.md` with `head -12`. Candidates are the parent run of a follow-up and every run on its `**Parent:**` chain, plus, for a new task, every run whose `**Baseline:**` line names the same branch. Older runs without a branch on that line are candidates only through a `**Parent:**` link.

**3. Diagnose.** One handoff → Reviewer, `mode: diagnose`, for all items at once. Model from the cell `{workflow}.reviewer:diagnose`. `inputs`: every item verbatim with its number; the baseline (the parent's sha, or `Merge base:`); each candidate run's `status.md` path, its task files or plan, and its `research/exploration.md`. `expected output`: `.dream-team-tracking/{context_id}/research/diagnosis.md`. Read only its pointer blocks. Record per item in `## Decisions log`: `comment <n>: Valid <v>, Severity <s>, Reachable <first step | not shown | n/a>, Attribution <a>`.

**4. Outcome per item.**
- `Valid: no`, `Valid: question`, or `Reachable: not shown` → **reply only**, offered first and marked recommended. Code stays an option at the gate.
- `Valid: partially` with `Severity: low` → reply only first, code second.
- Otherwise → **code**, from the diagnosis's `Proposed fix`.

Only the code items enter the workflow's design step: the quorum, the Advisor, the plan. A reply-only item gets a reply and nothing designed. When every item is reply only, the design step does not run at all.

**5. Gate.** The workflow's own approval question, asked once. Its text carries a table: `#`, the item in one line, `Valid`, `Severity`, the first step of `Reachable` (or `not shown`), and the proposed outcome. "Approve" approves every row as proposed. The workflow's edit option flips a row from reply to code or back. A flip to code runs the design step for that row alone, then asks the gate again. Log one line per item, `Gate {phase}, comment <n>: offered reply (recommended) / code; chosen <X>`, or `offered code (recommended) / reply` when code was proposed.

**6. Replies.** Write `.dream-team-tracking/{context_id}/plans/pr-replies.md` with the plan or the inline fix, so the gate can show it. One section per item, `## #<n> — <file or subject>`. The reply text, in the language of the pull request, comes first. Then `Evidence:`, which is never posted: one bullet per factual claim of the reply, `<claim> — <path:line>`, or `<claim> — (planned) task-<k>` / `(planned) fix bullet <k>` for code not yet written. A reply states only what a line shows. "Would be read as valid if …" without the line that reads it is not a claim you may make. Name the file in the `inputs` of the PlanAuditor (Change Set, Full Feature) and of the Reviewer, in every workflow.

**7. A run that only answers.** When the gate approves no code row, there is no plan and no audit: no Developer and no Tester run, and no plan file, task file or PlanAuditor call is written for it. Handoff → Reviewer with an empty change set and the replies path; it checks the replies and runs Step 5. Close the run with the status word `ANSWERED`.

**8. Lessons.** For every item with `Valid: yes` or `partially`, or a `no` or `question` the team provoked:

| Attribution | Lesson |
|---|---|
| developer chose against the recommendation | none for the team; one Decisions log line |
| developer chose the recommended option | team-amendment candidate: the recommendation was wrong |
| team decided | team-amendment candidate |
| not traced | none; one Decisions log line |

A `no` or `question` item is a candidate only when it was provoked by a false claim of the team, such as a pull request reply, a code comment or a commit message. Its attribution then names that claim. A complaint by the developer becomes a candidate only once the diagnosis shows it holds. Write candidates as `amendments.md` says. A fact about the project itself, not about the team, is the Reviewer's Step 5, as in every run.
