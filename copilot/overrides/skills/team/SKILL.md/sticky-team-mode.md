## Sticky team mode
## Sticky team mode

While a run is open, a marker file records it, so the run outlives the session that started it; after the run closes, the same marker keeps the developer's feedback on it inside the team. Copilot lets no hook add context to every prompt, so the hook declared in `team-manifest.json → hooks` runs once, when a session starts: it reads the marker and tells the new session which run is open, or which run just closed. Inside one session, keeping later messages inside the run is your job. After a compaction, or when the reminder did not arrive (bash missing, or hooks turned off in VS Code), the user picks the run up with `/team resume`.

Marker path: `.dream-team-tracking/.team-mode` (plain text, one `key=value` per line).

```
context_id={workflow_key}_{slug}_{YYYY-MM-DD}
workflow={Analyze | Docs | Bug Fix | Small Change | Quick Fix | Change Set | Full Feature}
phase={number and name of the phase just entered}
state={open | closed}
language={language the user wrote the task in}
started={YYYY-MM-DD}
parent={context_id of the run this one follows}        (only in a linked run)
closed={YYYY-MM-DD}                                       (closed form only)
result={BUILT | COMMITTED <sha> | DEPLOYED <environment> | VERIFIED | ANSWERED}
verify_open={number of Verify by hand lines not yet confirmed}
```

`workflow_key` is the manifest's key for the workflow: lower case, spaces as underscores (`analyze`, `docs`, `bug_fix`, `small_change`, `quick_fix`, `change_set`, `full_feature`). `slug` is the task in at most forty characters: lower case, every run of characters that are not letters or digits replaced by one hyphen, no leading or trailing hyphen. The same string names the run directory; older runs used other spellings of the workflow, which changes nothing about how they are read.

- **Write** it in Step 0 with `state=open`, immediately after creating `status.md`; `parent=` when `follow-up.md` or the user named the run this one follows.
- **Update** the `phase` line at every phase change, in the same edit as `status.md`.
- **Close** it when the run closes (`[DONE]`): rewrite it whole with Write — `state=closed`, `closed=`, `result=` (the status word of `## Result`; `ANSWERED` for Analyze), `verify_open=` (the count of bullet lines, `- `, under `## Verify by hand` that are not `none` and carry no `— confirmed` suffix). The marker stays: the next session hears `<TEAM-MODE-CLOSED>` and `follow-up.md` decides what each message is; inside this session, treat the messages that follow the close the same way. The final report ends with one line in the task's language: "Your next message here is taken as feedback on this run until a new run starts or you say it is verified."
- **Delete** it with `rm -f .dream-team-tracking/.team-mode` (confirm with `ls -a`) only when the user asks to stop team mode, or when `follow-up.md` records that every Verify by hand line is confirmed (`VERIFIED`). A new run's marker simply replaces a closed one (Write overwrites it).
- If the marker names a run whose `status.md` is missing, delete the marker and say so in one line. The session hook announces a marker without reading its `status.md`, so this check is yours; after it, the user's messages are standalone requests.

Arguments that manage the mode, handled without any workflow ceremony:

| Argument | Action |
|----------|--------|
| `stop` | Delete the marker, open or closed. Reply in one line: which run was left open and that it can be resumed with `/team resume`, or which closed run stopped collecting feedback. Do not close or modify `status.md`. |
| `status` | Read the marker and its `status.md`; report the run, its state, workflow, phase or result, its parent chain (follow the `**Parent:**` lines) and what happens next. Change nothing. |
| `resume [context_id]` | Resume as described in Step -1, item 4. |

When a session starts with the injected `<TEAM-MODE-ACTIVE>` block, treat the messages that follow as input to the named run: read that run's `status.md` first, then continue from its first unchecked phase; if the marker says `state=closed` while that first line is open, rewrite it `state=open` before continuing. When it starts with `<TEAM-MODE-CLOSED>`, read the run's `status.md` first line yourself: closed (`[DONE` or `Complete —` anywhere) → `.github/skills/team/references/follow-up.md` decides what each message is; still open → treat the marker as open and continue the run. When it starts with `<TEAM-MODE-ACTIVE>` and the run's first line is closed (`[DONE` or `Complete —`) — a marker from before 4.5.0, or a close interrupted between the `[DONE]` edit and the marker rewrite — rewrite the marker to the closed form and follow `follow-up.md` instead of continuing a run that has no unchecked phase. Never start a second run while a marker says `state=open` — finish, stop, or explicitly replace the current one.
