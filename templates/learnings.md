# Dream Team Learnings Log

Compounding knowledge for `/team`. Append-only. Written by the `reviewer` subagent after every Bug Fix, Change Set and Full Feature (and after a Small Change when a real defect was found). Read by the `/team` orchestrator at preflight (index first, full entries on match).

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
[STALE-CHECK] {knowledge file} — {why it may be outdated}   <- only if a knowledge claim is contradicted
```

Entry length limit: 25 lines. Put long narratives into `.claude-tracking/{context_id}/status.md`, not here.

`[STALE-CHECK]` lines are consumed by `/generate-knowledge`, which rewrites them to `[STALE-CHECK RESOLVED YYYY-MM-DD]` after regenerating the affected file.

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
is held to the budget keys named above.
