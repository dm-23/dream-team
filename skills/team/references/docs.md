# Workflow: Docs

Read first: none.

Documentation-only work. No Brainstorm, no research pass, no Tester, no Reviewer, no LEARNINGS entry — the DocWriter has its own search tools and verifies its own claims, and there is no toolchain to run against prose. What does not move is the approval gate: nothing is written until the user agrees.

1. Clarify only when the target files or the intent are genuinely ambiguous (≤2 questions).
2. Establish the file list: which documentation files this touches, by name. Look for yourself if the request does not say.
3. AskUserQuestion: the files you will touch and a one-line plan per file — approve / edit the list / reject.
4. On approval: handoff → DocWriter. `inputs` carries the request and the agreed file list; `constraints` says that no other file may change and that source files are out of bounds.
5. Verify it yourself — this is the step that replaces the Reviewer:
   - `git diff` against the baseline. Every changed file is on the approved list; nothing else moved.
   - Every line under "Claims verified" names a source path you can open. Spot-check the ones that carry weight.
   - "Gaps / could not verify" is empty, or you tell the user what is in it.
   - Anything under "Code change required": do not act on it. Ask the user via AskUserQuestion whether to open a Small Change or a Bug Fix for it, as a separate run.
   - A diff that does not match the block, or a claim that does not hold: one handoff back to the DocWriter with the specifics, then escalate to the user. There is no second rework cycle here.
6. Close status.md. Tick phases 0, 1, 4 and 5; mark 2, 3, 6, 7, 8 and 9 as `n/a — Docs`. Delete the marker.

The learnings check is skipped: nothing in this workflow consumes it, and the Reviewer who would write the entry never runs. Doc-only items inside a code run are a different matter — see Change Set step 6 — and documentation obligations that `PROJECT-RULES.md` attaches to a code change stay with the Developer, in the same change as the code.
