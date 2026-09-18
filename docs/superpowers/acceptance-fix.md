# Acceptance: `/generate-knowledge fix` on a real knowledge base

Run this from a session opened in the deployed project, not from the team repository.
The team repository has no `.claude/knowledge/` of its own, and a session that reaches
into another project to migrate it is the access pattern this project deliberately
stopped relying on.

## Before

    t(){ echo $(( $(cat "$@" 2>/dev/null | wc -c) / 4 )); }
    cd .claude/knowledge
    t CODING-STANDARDS.md TOOLCHAIN.md PROJECT-RULES.md BACKEND-ARCHITECTURE.md
    awk '/^```/{f=!f} !f && /^## \[/{exit} {print}' LEARNINGS.md | wc -c

Record both numbers. The first is what a Developer on a task in the server language
reads; the second, divided by four, is the index a run pays on every invocation.

The second command measures everything above the first entry, which is the index
region in both shapes: before the run it stops at the first entry body, after the run
there are none and it measures the whole file — exactly what the orchestrator then
reads. Bounding it by a heading instead would break on the After run, because `fix`
may remove the headings a migrated index no longer needs. The fence test is there for
the same reason the integrity check has one: the template documents the entry format
inside a fenced block that opens with a literal entry heading, and that example is
not an entry.

## Run

    /generate-knowledge fix

Accept both change classes. Note the backup path it reports.

## Verify

    bash .claude/checks/verify-knowledge-integrity.sh \
      .claude-tracking/knowledge-backup-<stamp> .claude/knowledge

Expected: a line starting with `knowledge integrity: ok`. Do not require an exact
match — most required files are classified `whole` in the manifest, which this
script never checks (rewrites are consented separately and are not byte-for-byte),
so a normal pass reads
`knowledge integrity: ok (not checked, classified whole in <manifest path>: <file names>)`
rather than the bare four words. That parenthetical is the script telling you what it
skipped, not a warning.

A failure — the line starts with `FAIL:` and the command exits non-zero — means `fix`
broke its own contract: restore `.claude/knowledge/` from the backup path it named and
report the defect. Do not repair the output by hand; doing so hides the bug this check
just found.

Run `/generate-knowledge fix` once more: it must report everything inside budget and
write nothing (no new backup directory under `.claude-tracking/`).

## After

Re-run the "Before" commands, reading the index plus the topics a task in the server
language selects. `BACKEND-ARCHITECTURE.md` and `CODING-STANDARDS.md` are indexes now;
their content lives under sibling directories such as `backend-architecture/`, so
include the specific topic files a server-language task would actually open, not just
the index files, if you want the after-number to reflect a real task's read cost.

Report the real numbers including a miss. The design predicts a large reduction on
both; a number that lands elsewhere is the finding, not an embarrassment, and it
belongs in the report either way.

## If something looks wrong rather than merely unshaped

`fix` never re-reads your repository — it restructures what `.claude/knowledge/`
already says, nothing more. If a file's *content* looks stale or wrong rather than
badly split, `fix` cannot repair that (it has no way to notice). Say so and run
`/generate-knowledge all`, or name the specific file, instead.
