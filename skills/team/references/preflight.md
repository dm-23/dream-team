# Preflight

The orchestrator runs this at Step -1, in this order.

## Directories

Run `bash .claude/{knowledge.resolver} project` from the project root: the knowledge dir of this run, written into every handoff.

Run `bash .claude/{knowledge.resolver} remarks` once, from the project root: the remarks dir, a project-root-relative directory written into the `remarks dir` field of every handoff. It is read with Read; nothing writes into it during a run but `remarks.sh accept` (SKILL.md → "Closing", `accepted-exceptions.md`). Nothing is created here; `remarks.sh accept` creates the directory with the first accepted remark.

## Drift

Run `bash .claude/{knowledge.drift}` once per run, from the project root, after the directories. Its output, one line or a block, is pasted verbatim into the `knowledge drift` field of every handoff. Once status.md exists (Step 0), write its first line to Process notes as `Knowledge drift: <line>`; a resumed run that already has the line gets no second one. A failure of the tool — it cannot be run, or prints nothing — is written as `Knowledge drift: not computed`, the field reads `not computed`, and the run continues. Never block the run on drift: a run that lags still runs. Its first line also gives the knowledge mode, as `knowledge-refresh.md` → "The mode" reads it. A knowledge refresh accepted in this preflight (private mode only) rewrites what the tool measures: run it once more after the refresh, before the first handoff, and use that output.

## Required files

Read `.claude/team-manifest.json`. For every file in `knowledge.required`, check it exists under the knowledge dir. If any is missing: offer to generate them now as `.claude/skills/team/references/knowledge-refresh.md` says (one question, naming the missing files); on no, stop and name the files. In committed mode, or with the mode unknown, there is no offer: stop, naming the files and the command `knowledge-refresh.md` names. Never write a knowledge file yourself.

## Authored rules

When `<knowledge dir>/rules` exists, run `grep -r '^- Rule:' "<knowledge dir>/rules"` once, in Bash (the knowledge dir may be git-ignored, and the Grep tool skips ignored paths), and keep the lines: they are the `Rule:` lines in the authored rules that the workflows' test decision reads, each after its file's path, cited as `rule:<file name without .md>`. When the knowledge dir is `knowledge.legacyDir`, run `grep -r '^- ' "<knowledge dir>/rules"` once instead: each `- ` line of each rule file, after the file's path. Its `- Rule:` lines are the ones kept here, and all its lines fill the `authored rules` field of every handoff in place of the directory (`handoffs.md`). No directory, no rules.

## Scaffold

Run `checks.knowledgeScaffold` as `checks.knowledgeScaffoldRunFrom` spells out. Exit 3: tell the user once, in one line, that the knowledge files are scaffolds written on an empty project on the date it prints, and that `/generate-knowledge` (in committed mode `/generate-knowledge refresh`) is due once the code exists. Exit 1: the project now has content — offer the refresh as `knowledge-refresh.md` says (in committed mode, or with the mode unknown, a command is named, not offered); the user may continue without it. Either way, once the run's `status.md` exists (Step 0), write `Scaffold knowledge: told YYYY-MM-DD` (exit 3, and exit 1 when nothing is offered) or `Scaffold knowledge: offered YYYY-MM-DD — <answer>` (exit 1) to its Process notes. With `resume`, or when item 4 resumes an open run, say nothing here: that run's Process notes already carry the line, or item 4's resumed status.md gets it then. Never block the run on it. The hook injects the same notice as `<TEAM-KNOWLEDGE-SCAFFOLD>` on the prompt that starts a run when the project has content; it is the same notice, acted on once as `knowledge-refresh.md` says, not a second one.

## Toolchain

Read `knowledge.toolchainMissingFile` if it exists; if it lists tools (the one line `none` lists nothing), warn the user once (they may continue). When an agent reports that a `TOOLCHAIN.md` command failed because its tool is absent, write `- <tool> — <the row's Purpose>` to that file: in place of a `none` line, else appended.

## Capabilities

Read `CAPABILITIES.md` from `knowledge.capabilitiesDir` if it exists; when it does, read `.claude/skills/team/references/capabilities.md` and follow it. Note which are available; if the file is absent, run with none. Never install anything and never suggest a run is blocked by a missing capability.

## Tools you may run

- The resolver (`knowledge.resolver`), run from the project root.
- The drift tool (`knowledge.drift`), `bash .claude/tools/knowledge-drift.sh`, run from the project root: once, in "Drift".
- The learnings index (`knowledge.learningsIndex`), `bash .claude/tools/learnings-index.sh "<remarks dir>"`, run from the project root, in `learnings-check.md`; and, in private mode, the due check `checks.learningsInbox` as `checks.learningsInboxRunFrom` spells out, there too.
- The remarks tool (`knowledge.remarks`), `bash .claude/tools/remarks.sh`, run from the project root: `pending` and `accept` in SKILL.md → "Closing", `accept` in `accepted-exceptions.md`.
