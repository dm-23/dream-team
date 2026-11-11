# Preflight

The orchestrator runs this at Step -1, in this order.

## Directories

Run `bash .claude/{knowledge.resolver} project` from the project root: the knowledge dir of this run, written into every handoff.

Run `bash .claude/tools/inbox.sh where` once, from the project root. Its second line goes to status.md → "Process notes" as `Learnings inbox: <line>` once status.md exists (Step 0; a resumed run that already has the line gets no second one). A `note:` line it prints is said once, as `learnings-check.md` says. Its first line, the inbox's directory, is never written into a handoff, a file or a command: every reader reaches the inbox through the tool. Nothing is created here; `inbox.sh add` creates `learnings/` with the first entry.

## Drift

Run `bash .claude/{knowledge.drift}` once per run, from the project root, after the directories. Its output, one line or a block, is pasted verbatim into the `knowledge drift` field of every handoff. Once status.md exists (Step 0), write its first line to Process notes as `Knowledge drift: <line>`; a resumed run that already has the line gets no second one. A failure of the tool — it cannot be run, or prints nothing — is written as `Knowledge drift: not computed`, the field reads `not computed`, and the run continues. Never block the run on drift: a run that lags still runs. A knowledge refresh accepted in this preflight rewrites what the tool measures: run it once more after the refresh, before the first handoff, and use that output.

## Required files

Read `.claude/team-manifest.json`. For every file in `knowledge.required`, check it exists under the knowledge dir. If any is missing: offer to generate them now as `.claude/skills/team/references/knowledge-refresh.md` says (one question, naming the missing files); on no, stop and name the files. Never write a knowledge file yourself.

## Scaffold

Run `checks.knowledgeScaffold` as `checks.knowledgeScaffoldRunFrom` spells out. Exit 3: tell the user once, in one line, that the knowledge files are scaffolds written on an empty project on the date it prints, and that `/generate-knowledge` is due once the code exists. Exit 1: the project now has content — offer the refresh as `knowledge-refresh.md` says; the user may continue without it. Either way, once the run's `status.md` exists (Step 0), write `Scaffold knowledge: told YYYY-MM-DD` (exit 3) or `Scaffold knowledge: offered YYYY-MM-DD — <answer>` (exit 1) to its Process notes. With `resume`, or when item 4 resumes an open run, say nothing here: that run's Process notes already carry the line, or item 4's resumed status.md gets it then. Never block the run on it. The hook injects the same notice as `<TEAM-KNOWLEDGE-SCAFFOLD>` on the prompt that starts a run when the project has content; it is the same offer, not a second one.

## Toolchain

Read `knowledge.toolchainMissingFile` if it exists; if it lists tools (the one line `none` lists nothing), warn the user once (they may continue). When an agent reports that a `TOOLCHAIN.md` command failed because its tool is absent, write `- <tool> — <the row's Purpose>` to that file: in place of a `none` line, else appended.

## Capabilities

Read `CAPABILITIES.md` from `knowledge.capabilitiesDir` if it exists; when it does, read `.claude/skills/team/references/capabilities.md` and follow it. Note which are available; if the file is absent, run with none. Never install anything and never suggest a run is blocked by a missing capability.

## Tools you may run

- The resolver (`knowledge.resolver`), run from the project root.
- The drift tool (`knowledge.drift`), `bash .claude/tools/knowledge-drift.sh`, run from the project root: once, in "Drift".
- The inbox tool (`knowledge.inbox`), `bash .claude/tools/inbox.sh`, run from the project root: `where` here, `index`, `show` and `check` in `learnings-check.md`, `show` and `append` in `accepted-exceptions.md`.
