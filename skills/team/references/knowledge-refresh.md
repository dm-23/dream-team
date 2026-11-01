# Knowledge refresh (offered, never imposed)

Two moments.

**Step 0.** When the hook said `<TEAM-INBOX-DUE>` or `<TEAM-KNOWLEDGE-SCAFFOLD>`, when `learnings-check.md` found pending marks or an index over `learningsIndexMaxRows`, or when Step -1 found a `knowledge.required` file missing: before any research, one AskUserQuestion in the task's language — "Knowledge: {inbox due: N marks, R rows | scaffold knowledge on a project with content | missing: <files>}. Refresh now (a few minutes, then the run continues) / Continue without it." One question covers every reason present at once.

**Close.** The "Closing" question in SKILL.md carries the option "refresh knowledge now — N files, M marks" when the Reviewer's `Learning:` line wrote a `[STALE-CHECK]` or `[PROMOTE]` mark in this run, or when the inbox was due at Step 0 and the developer declined then.

## Running it

On yes: one Agent call, with no handoff envelope (the generator is a command, not a role) and `model` omitted. Prompt:

> You are the Knowledge Generator. Read `.claude/skills/generate-knowledge/SKILL.md` and follow it. Arguments: `{file names, or nothing}` `Consent: Go`. Answer in {language}. Ask no question; report the work list as done, the backup path and the size table.

Scope: at Step 0 no file names — the generator decides from its own checks; at close the files the run's marks name, or none when only the inbox is due. The marker stays as it is. At Step 0 the call is made **before** the marker is written, because a marker in `state=open` is the one case the generator refuses; at close the marker is already `state=closed`, which it accepts. Never run the generator while a marker says `state=open`, and never delete a marker to make room for it.

## Recording it

- `## Decisions log`: `{YYYY-MM-DD} — Knowledge refreshed by the team: {files | all}, {M} marks triaged; backup {path from the generator's report}`.
- `## Process notes`: `Inbox due: offered YYYY-MM-DD — refreshed | declined` or `Scaffold knowledge: offered YYYY-MM-DD — refreshed | declined`, one line, written once. A resumed session that finds the line says nothing more about it.

On no, the run continues; nothing is repeated on resume. Never block a run on knowledge.
