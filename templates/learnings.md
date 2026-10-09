# Dream Team Learnings Inbox

Known traps in this project that have not yet earned a rule. The rules every agent follows live in `PROJECT-RULES.md`, `REVIEW-CHECKLIST.md`, `CODING-STANDARDS.md`, `TESTING-CONVENTIONS.md` and `TOOLCHAIN.md`; this file is consulted by matching a task or a finding against its index, never read for its own sake.

Written only by the `reviewer` subagent, in the format `templates/learnings-entry.md` defines: one file per entry under `learnings/`, one row here. Emptied only by `/generate-knowledge all`, with the user's consent and after a backup. The index stays small because entries leave.

Read by the `/team` orchestrator at preflight (index first, full entries on match), and by the reviewer before it writes, to find the entry it would otherwise write a second time.

## Index

| Date | Title | Tags |
|------|-------|------|

<!-- INDEX: one row per entry, newest last. The reviewer adds the row and the entry file in the same edit.
     The header above defines the row: those columns, that order. An index carrying other
     columns predates this template, and /generate-knowledge fix reconciles it.
     This table is read in full on every /team run, so every row is a cost. The limits live in
     team-manifest.json -> knowledge.budgets, which owns every number the team applies:
       whole row — learningsIndexRowTokens
       Title     — learningsIndexRowTitleChars, no parenthetical asides
       Tags      — learningsIndexRowMaxTags, each one word or one hyphenated term
       the table — learningsIndexMaxRows rows; past it, the orchestrator asks for
                   /generate-knowledge all, which empties the inbox
     Workflow, symptom, cause and file paths belong in the entry file, never in this table. -->
