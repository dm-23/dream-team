# Per-role handoff contents

- **For Developers:** Include ONLY:
  1. The path to the assigned `task-{N}-*.md`.
  2. The path to the exploration report for that task, when one was written. When the research pass was skipped, put `plans/draft-plan.md → ## Repository Analysis & Batch Suggestions` here instead — that one section, named as a section, is the substitute the task file's `Insertion Points` lean on.
  3. The `prior learnings` lines (if matches exist).
  Do NOT include the rest of the draft plan, brainstorm outputs, or previous batch reviews.
- **For the Reviewer (Full Feature):** `inputs` also names `plans/detailed-plan.md → ## Public API Surface`, so a deviation the plan states can be told from one it does not. In Full Feature and Change Set it also names `design/brief.md` when the run wrote one.
- **For the change-reviewer:** `inputs` per `final-pass.md` → Handoff, or `review_changes.md` step 3 with what `merge-review.md`, `re-review.md` or `review-parts.md` adds; a review thread only as the path of its file, never its text; never the plan, a task file, the brief, the exploration or a Reviewer report.
- **For Brainstorm:** Include ONLY:
  1. The task text or the user's answers.
  2. The path to the exploration report.
  3. The `prior learnings` lines (if matches exist).
  4. Never a request to read a source file; a lens that lists `### Missing Evidence` gets it through the evidence route (`references/quorum.md`), in every workflow.

  Never the exploration text itself. Three instances run in parallel on opus or above, so pasted research is paid for three times over; the path costs one line.

The `knowledge dir` field of every handoff is always filled from the resolver's output (Step -1 item 1), never typed; the `authored rules` field is that directory followed by `/rules`, or `none` when the knowledge dir has no `rules/`; when the knowledge dir is `knowledge.legacyDir`, the field holds the lines `preflight.md → Authored rules` printed, verbatim, in place of the directory (the Grep tool skips that git-ignored path, and some roles have no Bash); the `knowledge drift` field is the drift tool's output from Step -1 (`preflight.md → Drift`), pasted verbatim, or `not computed` when the tool failed; the `learnings inbox` field is copied as the template gives it.
