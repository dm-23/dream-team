# Review Changes: a change above the size limits

Read from `review_changes.md` step 3 when the counts of `**Range:**` are above sixty changed files or three thousand changed lines, and again at its step 4 when the review ran in parts. Never read for a merge of branches (`merge-review.md` has no size gate).

## The question

The change is too large for one pull request. One AskUserQuestion, logged as a gate: "split into separate pull requests (recommended) / review in parallel parts / one pass with a focus: <security | correctness | tests | architecture> / stop here and report only the range". When it is reviewed anyway, the page's summary says it should have been split.

- **Split.** No call. Propose the split in chat: the parts as below, each a separate pull request with its paths and counts, in the order they can land. Then step 7 with `split proposed` in place of the recommendation and the counts, and without the fix-run options.
- **Parts.** Group the changed paths by top-level directory, then by layer (server side, interface, tests), each part under both limits where possible, together covering every changed path exactly once; give each part's paths as directory prefixes or path patterns git accepts (`git diff --stat=<width>` when paths are cut short). Name each part in lower case with hyphens (its file name carries it; `cross` is taken), and log `Parts: <name> (<N> files, +a/−d) · …` in the Decisions log. One change-reviewer call per part, all in one message so they run in parallel, each with the same range, intent and focus and its own paths; each part's handoff names the threads file, and the reviewer takes the threads whose location is in its paths.
- **One pass with a focus.** One call over the whole range, the chosen focus as its review focus: it says where the depth is spent, never which checklist items apply.
- **Range only.** No call. Answer in chat with the `**Range:**` line, the commit list and the `git diff --stat` summary, then step 7 with `range only` in place of the recommendation and the counts, and without the fix-run options.

## The cross-part pass

Parts are reviewed blind to each other, so what one part produces and another consumes is read by nobody. After every part call has returned, and before consolidation, one more change-reviewer call on the same cell as the parts: the same range, intent and focus, the paths line `all · part: cross`, the findings files of the parts in `inputs`, no threads file and no `ci:` line; `expected output`: `.dream-team-tracking/{context_id}/reports/review-findings-cross.md`. Log `Cross-part pass: <n> findings`. Its file is consolidated as the last part.

## Consolidate (step 4)

Two findings at the same `path:line` from two files are one: keep the higher severity and both explanations. Number the merged list `F-1…` by severity, Critical first, the parts in their logged order within a severity, `cross` last. Write the numbers into the files by Edit: each heading's `F-<k>` becomes its consolidated `F-<n>`; the lower-severity copy of a duplicate takes the kept one's `F-<n>` and the line `- Merged into: F-<n>` under its heading, and the page shows its explanation under that finding. The counts are the merged list's; the recommendation is the strictest of the files' (`Request changes` over `Approve with follow-ups` over `Approve`); the `Threads:` and `Exceptions:` counts are summed. Log `Consolidated: <total> findings from <p> parts, <d> merged`. From here on a finding's id is its consolidated number: in the Verifier handoff, on the page and in a fix run.
