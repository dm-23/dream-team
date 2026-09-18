# Dream Team Learnings Log

Compounding knowledge for `/team`. Append-only. Written by the `reviewer` subagent after every Bug Fix, Change Set and Full Feature (and after a Small Change when a real defect was found). Read by the `/team` orchestrator at preflight (index first, full entries on match).

## Index

| Date | Title | Tags |
|------|-------|------|

<!-- INDEX: one row per entry, newest last. The reviewer adds the row AND the entry in the same edit.
     This table is read in full on every /team run, so every row is a cost. Hard limits:
       Title — max 80 characters, no parenthetical asides.
       Tags  — max 6, each one word or one hyphenated term.
     Workflow, symptom, cause and file paths belong in the entry below, never in this table. -->

## Entry format

```markdown
## [YYYY-MM-DD] {short-title}
- **Workflow:** Bug Fix | Small Change | Change Set | Full Feature
- **Symptom:** one or two sentences
- **Root cause:** one paragraph max
- **Fix pattern:** reusable shape of the fix, max 5 lines
- **Files touched:** key paths
- **Tags:** max 6 comma-separated keywords, each one word or one hyphenated term
[STALE-CHECK] {knowledge file} — {why it may be outdated}   <- only if a knowledge claim is contradicted
```

Entry length limit: 25 lines. Put long narratives into `.claude-tracking/{context_id}/status.md`, not here.

`[STALE-CHECK]` lines are consumed by `/generate-knowledge`, which rewrites them to `[STALE-CHECK RESOLVED YYYY-MM-DD]` after regenerating the affected file.

---

<!-- Entries below this line. -->
