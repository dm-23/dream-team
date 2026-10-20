# Update check (new runs only)

Run it once, in Step 0 of a new run, and never again inside that run. Skip it entirely for `stop`, `status` and `resume`, for a run continued through the marker or the injected `<TEAM-MODE-ACTIVE>` block, and when the user chose to resume an open run in Step -1.

Run `bash .claude/tools/update-check.sh`. It decides on its own whether the user agreed to the check and whether it is due, and it never asks the network more than once a day.

- **No output:** say nothing and never mention the check.
- **Output `L R`** (the version this project runs, then the newer one): ask via AskUserQuestion, in the task's language: "Team version R is available; this project runs L. Changes: {`updateCheck.repository` from the manifest}". Options:
  1. **Continue on L** — the run proceeds.
  2. **Park and update** — first add `Team update L → R available: parked` to status.md → "Process notes", since resuming depends on that line; then delete the marker exactly as `stop` does, leave `status.md` at phase 0, show `updateCheck.instructions` from the manifest verbatim, and stop. You never run the update yourself.
  3. **Skip R** — run `bash .claude/tools/update-check.sh skip R`; the run proceeds. R is not mentioned again; a later version is.

For options 1 and 3, add one line to status.md → "Process notes": `Team update L → R available: continued` or `… skipped`.
