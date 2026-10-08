## Sticky team mode
## Sticky team mode

While a run is open, a marker file records it, so the run outlives the session that started it. Copilot lets no hook add context to every prompt, so the hook declared in `team-manifest.json → hooks` runs once, when a session starts: it reads the marker and tells the new session which run is open. Inside one session, keeping later messages inside the run is your job. After a compaction, or when the reminder did not arrive (bash missing, or hooks turned off in VS Code), the user picks the run up with `/team resume`.

Marker path: `.dream-team-tracking/.team-mode` (plain text, one `key=value` per line).

```
context_id={workflow_key}_{slug}_{YYYY-MM-DD}
workflow={Analyze | Docs | Bug Fix | Small Change | Change Set | Full Feature}
phase={number and name of the phase just entered}
language={language the user wrote the task in}
started={YYYY-MM-DD}
```

`workflow_key` is the manifest's key for the workflow: lower case, spaces as underscores (`analyze`, `docs`, `bug_fix`, `small_change`, `change_set`, `full_feature`). `slug` is the task in at most forty characters: lower case, every run of characters that are not letters or digits replaced by one hyphen, no leading or trailing hyphen. The same string names the run directory; older runs used other spellings of the workflow, which changes nothing about how they are read.

- **Write** it in Step 0, immediately after creating `status.md`.
- **Update** the `phase` line at every phase change, in the same edit as `status.md`.
- **Delete** it when the run closes (`[DONE]`), when the user asks to stop or pause team mode, and before starting a different run — with `rm -f .dream-team-tracking/.team-mode`, the one shell write this skill allows on a tracking file, and confirm with `ls -a`.
- If the marker names a run whose `status.md` is missing or whose first line contains `[DONE]`, delete the marker and say so in one line. The session hook announces a marker without checking its run, so this check is yours; after it, the user's messages are standalone requests.

Arguments that manage the mode, handled without any workflow ceremony:

| Argument | Action |
|----------|--------|
| `stop` | Delete the marker. Reply in one line: which run was left open and that it can be resumed with `/team resume`. Do not close or modify `status.md`. |
| `status` | Read the marker and its `status.md`; report the run, workflow, phase and what happens next. Change nothing. |
| `resume [context_id]` | Resume as described in Step -1, item 4. |

When a session starts with the injected `<TEAM-MODE-ACTIVE>` block, treat the messages that follow as input to the named run: read that run's `status.md` first, then continue from its first unchecked phase. Never start a second run while a marker exists — finish, stop, or explicitly replace the current one.
