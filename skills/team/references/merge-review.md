# Review Changes: a merge of branches

Read from `review_changes.md` step 1 when a merge signal holds. A pull request that merges one long-lived branch into another (a release into the next release, a release back into the main line) carries commits that were reviewed in pull requests of their own. Reading them again finds nothing those reviews did not, and its size alone would send it to the "too large" question. What such a pull request can break is what the merge itself decided: how each conflict was resolved, what was edited by hand inside the merge, what was lost.

## Is it a merge

Two signals, both read at step 1:

- **Commits.** `git log --merges --oneline <base-sha>..<head-sha>` prints at least one line.
- **Words.** The pull request title, the head branch name or the developer's task says it merges one branch into another.

Both hold → merge mode; log `Mode: merge — <the merge commits' count>, "<the words>"`. Exactly one holds → the run is in doubt, and the developer decides: one AskUserQuestion, "a merge of branches: carried commits are not reviewed again / an ordinary change: everything in the range is reviewed", neither recommended, logged as a gate; follow the answer. A long-lived feature branch that merged the base into itself to stay current shows the first signal alone, which is why one signal never decides. Neither holds → an ordinary change; this file is closed.

## The run in merge mode

- **Source.** The branch merged in: from the merge commit's subject in the `git log --merges` output, else from the developer's words. Unknown → the handoff says `source: unknown` and the change-reviewer finds it.
- **No size gate, no parts.** Step 3's limits do not apply and `review-parts.md` is not read: the carried commits are the bulk and are not read line by line. Log `Size gate: n/a — merge`.
- **One call.** Handoff → change-reviewer, `mode/phase: merge`, on the same cell as step 3 names, with step 3's `inputs` and `source: <branch>` beside the range. The intent is the pull request title and description; the reviewer reports `Intent coverage: n/a — merge`.
- **Steps 4 to 7** run as written, with one file. The Verifier votes on the blocking findings as on any others. The page's summary card shows the `Merge:` pointer line where intent coverage would be, and its section 3 is left out.
- **Fix run.** A finding in a conflict resolution is fixed in the merge branch like any other; the fix-run options of step 7 stay.

A merge reviewed again after new pushes (`re-review.md`) runs in merge mode in full, with the earlier findings' statuses added.

**What you never do here:** decide alone on one signal, split a merge into parts, or ask the change-reviewer to read the carried commits.
