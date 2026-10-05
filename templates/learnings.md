# Dream Team Learnings Inbox

Known traps in this project that have not yet earned a rule. The rules every agent follows live in `PROJECT-RULES.md`, `REVIEW-CHECKLIST.md`, `CODING-STANDARDS.md`, `TESTING-CONVENTIONS.md` and `TOOLCHAIN.md`; this file is consulted by matching a task or a finding against its index, never read for its own sake.

Written only by the `reviewer` subagent, and only when a run taught something a later run needs: a trap, or a mark asking for a rule or a fact to be written into a knowledge file. A run that taught nothing leaves nothing here. Emptied only by `/generate-knowledge all`, which writes marked rules and facts into the knowledge files and, with the user's consent and after a backup, removes entries that are covered, obsolete, or never belonged here. The index stays small because entries leave.

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

## Entry format

```markdown
## [YYYY-MM-DD] {short-title}
- **Workflow:** Bug Fix | Small Change | Change Set | Full Feature
- **Symptom:** one or two sentences
- **Root cause:** one paragraph max
- **Fix pattern:** reusable shape of the fix, max 5 lines
- **Files touched:** key paths
- **Tags:** comma-separated keywords, at most `learningsIndexRowMaxTags` of them, each one word or one hyphenated term
[PROMOTE] {knowledge file} — {the rule, one imperative sentence}   <- only for a rule, or a trap seen a second time
[STALE-CHECK] {knowledge file} — says "{quote}" | says nothing about {subject}; actually {claim} ({repo path})   <- only for a fact a knowledge file gets wrong or omits, after reading both
```

Entry length limit: `learningsEntryLines` in `team-manifest.json → knowledge.budgets`. Put long narratives into `.claude-tracking/{context_id}/status.md`, not here.

Two things are never entries. A summary of what a run did or what passed is the review report in `status.md`. A defect of the team itself — a role, a permission, a handoff, a subagent's report — goes to `status.md → Process notes` and the run's final report.

`[PROMOTE]` and `[STALE-CHECK]` lines are consumed by `/generate-knowledge all`, which rewrites them to `[PROMOTE RESOLVED YYYY-MM-DD]` / `[STALE-CHECK RESOLVED YYYY-MM-DD]` when it writes the rule or the fact, and then removes the entry unless it is still a trap worth keeping. Regenerating a named file resolves the `[STALE-CHECK]` lines that name it, as before.

---

Entries do not live in this file. Each one is a file in `learnings/`, named
`YYYY-MM-DD-{slug}.md`, holding exactly the entry and nothing else — no frontmatter,
no wrapper. The file's whole content is the entry, because that is what makes a
migration verifiable byte for byte.

`{slug}` is derived from the row's title by a fixed transform, so that whoever writes
the entry and whoever later looks it up compute the same path from the same row:

1. lower-case the title;
2. replace every run of characters that are not letters or digits with one hyphen;
3. drop a leading or trailing hyphen;
4. cut to 60 characters, then drop a trailing hyphen again.

If that file already exists — the same title on the same date — append `-2`, then
`-3`, and so on. A reader that computes the path and finds nothing tries those
suffixes before concluding the entry is missing. It does not list `YYYY-MM-DD-*` and
guess: a date carries as many entries as that day produced, and guessing picks the
wrong one silently.

This file is the index and only the index. It is read on every `/team` run, so a row
is held to the budget keys named above and the table to `learningsIndexMaxRows`.
