# Review Changes: a change reviewed before

Read from `review_changes.md` step 1 when an earlier Review Changes run reviewed the same two refs. The author has usually pushed fixes since; the developer wants to know which findings are closed and whether the fixes broke anything, not a second review from nothing.

## Find the earlier run

In Bash, `ls -d .dream-team-tracking/review_changes_*/`, and `head -12` of each `status.md`: a run is a match when its first line is closed (`[DONE`) and its `**Range:**` line names the same `<base-ref> ← <head-ref>` as this run. With several, the latest by its date. A run closed as `split proposed` or `range only` wrote no findings and is no match.

- **The head moved** (its head sha differs from this run's). This run is a re-review: write `**Parent:**` and the marker's `parent=`, log `Re-review of <context_id> (<old-head> → <new-head>)`, and say it in chat in one line.
- **The head did not move.** One AskUserQuestion: "open the earlier page (recommended) / review again in full". On the first, give the earlier page's path and close this run as `ANSWERED` with no call. On the second, this run is an ordinary review and this file is closed.

## The range of a re-review

Run `git merge-base --is-ancestor <old-head> <head-sha>` (read-only; exit 0 means yes), logged like the other commands of step 1.

- **Yes.** The reviewed range is `<old-head>..<head-sha>`: only what was pushed since. `**Range:**` keeps the whole change; add the line `**Re-review range:** <old-head>..<head-sha>, N files, +a/−d`, counted as step 1 counts. The size gate of step 3 reads this line.
- **No** (the history was rewritten). The reviewed range is the whole change, and the handoff says `history rewritten` beside it.

## The call

Handoff → change-reviewer, `mode/phase: re-review` (or `merge`, with the two additions below, when the earlier run logged `Mode: merge`), on the same cell as step 3 names. Step 3's `inputs`, the range replaced by the reviewed range, plus: `earlier findings:` the paths of the earlier run's findings files, `earlier head: <old-head>`, and `earlier run: <context_id>`. The threads file and the `ci:` line are today's.

Its file opens with `## Earlier findings`, and its pointer block carries `Earlier: <f> fixed, <n> not fixed, <p> partially, <o> obsolete`. A finding not fixed, or fixed in part, is in `## Findings` again with a `Previously:` line and counts as any other; steps 4 to 7 need nothing more to treat it right.

## Report and close

The page shows the earlier findings as a table before the findings (`report-html.md`). The `[DONE]` line of step 7 ends `; earlier: <f> fixed, <n> not fixed, <p> partially, <o> obsolete`. The earlier run's files are never edited: its page stays what was true at its head.

**What you never do here:** set a status yourself, review only the earlier findings without the pushed range, or reuse the earlier run's vote for a finding carried over; it is voted again at the new head.
