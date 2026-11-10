# Final pass

After the Reviewer has approved the run's whole change set, the change-reviewer reviews the same change from outside, without the plan: the toolchain and the criteria are green, so the pass judges finished code. It changes nothing. Its findings are voted and reworked, or put to the developer at the gate below; they never change the run's verdict. The Reviewer's verdict stays the verdict, and the `Recommendation` line of the change-reviewer's pointer block is not used.

## When it runs

- After the Reviewer's verdict on the whole change set is an approval (`approved`, `fixed`, or one with advisory or unverified counts, as `rework.md` writes them), and after the rework of that review when one ran. Never between a rework handoff and its Reviewer pass, and never while a `needs rework` is open.
- Full Feature, Phase 5, after the final review, and Change Set, step 8, after the combined review: always.
- Bug Fix, Small Change and Quick Fix: only when the developer asked for it in the task, or when the run is hard (`hard=yes` in the last `Models:` or `Models revised:` line of the Decisions log). Otherwise the pass is skipped: no handoff, no gate, and the Reviewer's `advisory` items reach the developer through the final report only.
- The Decisions log says `Final pass: run` or `Final pass: skipped — <reason>`; a skipped pass writes `final pass: skipped — <reason>` on the phase 7 line.
- Once per run: the fixes of the gate, and a rework after them, do not start it again.

## Handoff

One handoff → change-reviewer, `mode/phase: final-pass`, model from the cell `<workflow>.change-reviewer`. `inputs`:

- `range: <baseline-sha>..working tree`, the sha of `status.md → Baseline`;
- the change set paths, from the `Change set:` line of the approving Reviewer report;
- the task in the user's words (`status.md → ## Task`);
- the `status.md` path, for its Decisions log;
- the knowledge dir;
- `.claude/templates/review-baseline.md`;
- the prior learnings lines;
- `toolchain: run by the Reviewer at <sha> — <the Reviewer's Toolchain line>`, `<sha>` from `git rev-parse --short HEAD` and the line copied from the approving report.

The envelope's `baseline:` names the run's baseline sha and the run's pre-existing uncommitted files. `expected output`: `.dream-team-tracking/{context_id}/reports/review-findings.md`. Never the plan, a task file, the brief, the exploration or a Reviewer report, not even as a path.

Read the pointer block, then of each finding only its `### F-` heading and its `Issue:` and `Decision:` lines. The rest of a finding is read when it is sent to be fixed.

## Findings

A finding keeps its `F-<n>` from the file. The `advisory` items of this run's Reviewer reports take `A1`, `A2`, … in the order the reports gave them.

- **Critical, High or Medium with `Decision: none`** → the Verifier vote of `rework.md`, each written as a `manual` finding `M<n> <path:line> — [<severity>] <issue>`: `<n>` is the finding's own number (`F-3` is voted as `M3`), `<issue>` its `Issue:` line. CONFIRMED ones enter the Developer rework handoff, split by owner as `rework.md` says, each with its finding verbatim from the file; then the Reviewer's rework pass over the whole change set. This is a rework loop of its own, under the two-cycle cap of `rework.md`, then the escalation. REJECTED ones are logged `downgraded to advisory: <the Verifier's reason>` and join the gate list as Low, the reason beside them. With nothing to vote on, no Verifier call.
- **Critical, High or Medium with a `Decision:` line quoting a decision** → no vote and no rework on their own: they open the gate as `Decisions to revisit:`.
- **Low and Nit**, whatever their `Decision:` line → the gate list.
- **The Reviewer's `advisory` items** of this run → the gate list, after the Low and Nit items.

## The final-pass gate

One AskUserQuestion of its own, asked after the vote and the rework it started (when any) and before the run closes. It is neither the batch gate of Full Feature, already asked, nor the closing question of `SKILL.md → Closing`, which comes only once `status.md` is `[DONE]`.

- **Nothing to ask.** With an empty gate list and no decision to revisit, no question is asked, and the Decisions log says `Final-pass gate: nothing to ask`.
- **Text**, before the options, in this order: the line `Decisions to revisit:` and under it one line each, `F-n · path:line · issue — "<the quoted decision>"`; then the Low and Nit items, `F-n · path:line · issue`, a rejected one with `— Verifier: <reason>`; then the advisory items, `A<n> · path:line · issue`. A text past about forty lines shows `F-n · path:line` and `A<n> · path:line` only and names `.dream-team-tracking/{context_id}/reports/review-findings.md` for the rest.
- **Question 1**, over the list: **fix all now** / **fix selected** (the developer names the ids) / **keep in the report**. Keep in the report is recommended when every item is Nit; otherwise no option is. A fix selected that names no id is asked once more, the items listed in the question text. Logged `Final-pass gate: offered fix all / fix selected / keep; chosen <X>`. With an empty list there is no question 1.
- **Then one question per decision to revisit**, in the same AskUserQuestion, `F-n — "<the quoted decision>"`: **fix now** / **keep the decision**. When they do not fit the four questions it carries, the decisions share one multi-select "fix now" instead, four options at most; an unselected decision is kept, and one past the fourth is named in the question text and kept. A kept decision is logged with the developer's words: `F-n decision kept — "<words>"`.
- **The fix.** On fix all now, fix selected or a fix now: one Developer handoff per owner (test files to the Tester, split as `rework.md` splits them) with the chosen findings verbatim from the file, an advisory item as the Reviewer wrote it, each call on the cell of the call it repeats; then one Reviewer pass over the whole change set, its `inputs` those of a rework pass. It is not a rework cycle and counts toward no cap; the Decisions log says `Low findings fixed: <ids>`, every id fixed in it, decisions included.
- **After the fix.** An approving verdict ends the gate. A `needs rework` runs one rework cycle of its own through `rework.md` (the Verifier vote, the Developer, the Reviewer), then, when the verdict is still not an approval, escalates to the developer. That cycle neither consumes nor resets the cap of the earlier rework. The gate is not asked again.
- **Kept.** Every item not fixed goes into `status.md → ## Review findings kept`, one line each, `F-n · path:line · issue` or `A<n> · path:line · issue`, in place of `none`.

## Critical zone

When the approving Reviewer report starts with `Critical zone:`, every fix of this pass (a confirmed finding, a decision fixed now, a list item the developer picked, even a Low or a Nit) goes to the Developer, a test file to the Tester, never to the Reviewer; the Reviewer fixes nothing in the passes after them. The vote keeps the critical-zone rule of `rework.md`: a REJECTED finding is asked, rework / drop, never downgraded.

## Report

- The phase 7 line gains `; final pass: C/H/M/L/N → <r> rework, <d> decisions, <k> kept`: the counts of the pointer block's `Findings:` line, `<r>` the confirmed findings sent to rework, `<d>` the decisions to revisit, `<k>` the items kept.
- The final report to the user names the pass's counts, each decision revisited with its answer, and, under `Review findings kept`, every kept item with its location, as `status.md` has them.
- The status word does not change for the pass: `BUILT` rests on the Reviewer's verdict.
