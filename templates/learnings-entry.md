# Learnings entry format

The index is printed by `team-manifest.json → knowledge.learningsIndex` from the entry files, and what it shows of an entry is the heading's title and the Tags line, within `learningsIndexRowTitleChars` and `learningsIndexRowMaxTags`; this file defines what an entry is. It is read by the `reviewer` subagent before it writes one and by `/generate-knowledge` when it triages or restructures the remarks dir. It is never deployed into the knowledge dir.

## Entry format

```markdown
## [YYYY-MM-DD] {short-title}
- **Workflow:** Bug Fix | Small Change | Quick Fix | Change Set | Full Feature
- **Symptom:** one or two sentences
- **Root cause:** one paragraph max
- **Fix pattern:** reusable shape of the fix, max 5 lines
- **Files touched:** key paths
- **Tags:** comma-separated keywords, at most `learningsIndexRowMaxTags` of them, each one word or one hyphenated term
- **Reachable:** sequence of events, each step with path:line   <- required for a risk (race, stale value, ordering, read after it should be cleared); omit otherwise
- **Same as:** {file name of an existing remark in the remarks dir}   <- optional; only in a "Same as" entry (below)
[PROMOTE] {knowledge file} — {the rule, one imperative sentence}   <- only for a rule, or a trap seen a second time
[STALE-CHECK] {knowledge file} — says "{quote}" | says nothing about {subject}; actually {claim} ({repo path} | environment: {what was observed})   <- only for a fact a knowledge file gets wrong or omits, after reading both
```

Entry length limit: `learningsEntryLines` in `team-manifest.json → knowledge.budgets`. Put long narratives into `.dream-team-tracking/{context_id}/status.md`, not here.

Two things are never entries. A summary of what a run did or what passed is the review report in `status.md`. A defect of the team itself — a role, a permission, a handoff, a subagent's report — goes to `status.md → Process notes` and the run's final report, and becomes a team-amendment candidate (`.claude/skills/team/references/amendments.md`).

An entry is written only when a run taught something a later run needs: a trap, or a mark asking for a rule or a fact to be written into a knowledge file. A run that taught nothing leaves nothing.

`[PROMOTE]` and `[STALE-CHECK]` lines are consumed by `/generate-knowledge`. While the knowledge is not committed, its triage rewrites them to `[PROMOTE RESOLVED YYYY-MM-DD]` / `[STALE-CHECK RESOLVED YYYY-MM-DD]` when it writes the rule or the fact, and then deletes the remark unless it is still a trap worth keeping; regenerating a named file resolves the `[STALE-CHECK]` lines that name it, as before. Once the knowledge is committed, `/generate-knowledge refresh` deletes every remark it consumes or rejects and names it in its commit body; a remark it keeps stays as it is.

## Two short forms

A **"Same as" entry** records a second sighting of a lesson an existing remark already
describes, since a remark is never edited or appended to. It is an ordinary entry — the
heading and the `Tags` line as above — whose body is the `- **Same as:**` line, naming the
existing remark's file name in the remarks dir, and the mark line:

```markdown
## [YYYY-MM-DD] {short-title}
- **Tags:** {keywords}
- **Same as:** {file name in the remarks dir}
[PROMOTE] {knowledge file} — {the rule, one imperative sentence}
```

An **exception entry** records a finding the developer accepted as an exception
(`.claude/skills/team/references/accepted-exceptions.md`). It is two lines, in the file
`.dream-team-tracking/{context_id}/learnings/YYYY-MM-DD-exception-{slug of the path}.md`, the
slug being what the transform below makes of the finding's path; a name already taken there
(another finding in the same file, the same day) gets the first free `-2`, `-3`, as for any
entry ("Where an entry lives"), and each one is accepted before the next is written. Its two
lines:

```markdown
## [YYYY-MM-DD] exception {path}
[EXCEPTION] {the exception line of accepted-exceptions.md, without "- "}
```

## Where an entry lives

Each entry is a file named `YYYY-MM-DD-{slug}.md`, holding exactly the entry and nothing
else — no frontmatter, no wrapper. The file's whole content is the entry, because that is
what makes a copy verifiable byte for byte.

A role writes it into the run's tracking directory,
`.dream-team-tracking/{context_id}/learnings/`; a name already taken there — the same title
on the same date — gets the first free `-2`, `-3` and so on. It waits there. Only when the
developer accepts it — at the close of the run, or at the gate for an exception entry —
does the orchestrator copy it into the remarks dir (what `team-manifest.json → knowledge.resolver`
prints for `remarks`, a `proposals/` directory) with `bash .claude/tools/remarks.sh accept`,
which names the copy `YYYY-MM-DD-{slug}-{hash6}.md`, `{hash6}` the first six characters of
the content's `git hash-object`, and never overwrites a file. An entry the developer
declines stays in the tracking directory and goes no further. In the remarks dir the entry
is a **remark**: read with Read, never edited by a role.

`{slug}` is derived from the entry's title by a fixed transform:

1. lower-case the title;
2. replace every run of characters that are not letters or digits with one hyphen;
3. drop a leading or trailing hyphen;
4. cut to 60 characters, then drop a trailing hyphen again.

A reader finds a remark by the `File` cell of its index row (`knowledge.learningsIndex` run
on the remarks dir), never by computing the path or listing `YYYY-MM-DD-*`: the copy's name
carries the `-{hash6}` suffix.
