# Knowledge refresh (offered, never imposed)

Two moments.

**Step 0.** When the hook said `<TEAM-INBOX-DUE>` or `<TEAM-KNOWLEDGE-SCAFFOLD>`, or when Step -1 found a `knowledge.required` file missing or counted line citations: before any research and before the marker is written, one AskUserQuestion in the task's language — "Knowledge: {inbox due: N marks, R rows | scaffold knowledge on a project with content | missing: <files> | line citations: N in K files}. Refresh now (a few minutes, longer with hundreds of line citations; then the run continues) / Continue without it." One question covers every reason present at once. Two exceptions: with required files missing, "Continue without it" is not on offer — the run cannot start without knowledge, so the options are "Generate now" and "Stop", and on stop the missing files are named; and when `checks.knowledgeScaffold` prints `project: empty`, offer nothing — the generator's empty-project path asks the developer which stack is decided, which a subagent cannot answer — and name `/generate-knowledge` for the developer to run. A parked run whose marker is still `state=open` gets no offer either; the generator would refuse it. `learnings-check.md` runs after the marker is written, so it only records `deferred to close`; the closing question carries that offer.

**Close.** The "Closing" question in SKILL.md carries the option "refresh knowledge now — N files, M marks" when the Reviewer's `Learning:` line wrote a `[STALE-CHECK]` or `[PROMOTE]` mark in this run, when the inbox was due at Step 0 and the developer declined then, or when `learnings-check.md` recorded `deferred to close`. It is asked after `status.md` is `[DONE]` and the marker is `state=closed`, never before.

**Line citations.** When `.dream-team-tracking/.line-citations` exists, this project has had its line citations replaced: the count is not taken and nothing is offered for this reason, because whatever the command still matches there (a host and its port, a configuration key) is not a citation. Otherwise `checks.knowledgeLineCitations` prints one line per place where a knowledge file cites code by line number. Never read that list: run the two counting forms `checks.knowledgeLineCitationsRunFrom` gives, N the citations and K the files. Such a citation is wrong after any edit above it, and the refresh replaces it with a name. The developer may continue without it. With `resume`, or when the preflight resumes an open or parked run, the count is not taken and nothing is offered: that run's plan was made on the knowledge as it stands.

## Running it

On yes: one Agent call, with no handoff envelope (the generator is a command, not a role) and `model` omitted. Prompt:

> You are the Knowledge Generator. Read `.claude/skills/generate-knowledge/SKILL.md` and follow it. Arguments: `Consent: given`. Answer in {language}. Ask no question; report the work list as done, the backup path and the size table.

Scope: no file names at either moment. The generator's own staleness check and inbox classification find exactly the files and marks this run left behind, and a file-name run would skip the triage the option promises. The marker stays as it is. At Step 0 the call is made before the marker is written, because a marker in `state=open` is the one case the generator skips its shape work and triage for; at close the marker is already `state=closed`, which it accepts. Never run the generator while a marker says `state=open`, and never delete a marker to make room for it.

## Recording it

- `## Decisions log`: `{YYYY-MM-DD} — Knowledge refreshed by the team: {files | all}, {M} marks triaged; backup {path from the generator's report}`.
- `## Process notes`: `Inbox due: offered YYYY-MM-DD — refreshed | declined` or `Scaffold knowledge: offered YYYY-MM-DD — refreshed | declined` or `Line citations: offered YYYY-MM-DD — refreshed | declined`, one line per reason offered, written once. A resumed session that finds the line says nothing more about it.
- After a refresh that was offered for line citations and whose report came back: write `.dream-team-tracking/.line-citations` with the one line `refreshed YYYY-MM-DD`. Not when the refresh was declined, and not when the generator stopped before its report.

On no, the run continues; nothing is repeated on resume. Never block a run on knowledge.
