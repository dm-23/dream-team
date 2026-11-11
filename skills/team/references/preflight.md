# Preflight

The orchestrator runs this at Step -1, in this order.

## Directories

Run `bash .claude/{knowledge.resolver} project` and `… operative` from the project root: the knowledge dir and the operative dir of this run, written into every handoff.

If `LEARNINGS.md` is missing from the operative dir, create it there from `knowledge.persistentTemplates`.

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
