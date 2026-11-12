# Accepted exceptions

Read when the developer keeps a decision at the final-pass gate (`final-pass.md`), or picks "record accepted exceptions" at the close of a Review Changes run (`review_changes.md` step 7).

A finding the developer consciously declined is true and stays declined. Without a record, the next review of the same code raises it again, the developer declines it again, and the review's findings lose their weight. The record is a remark in the remarks dir; the change-reviewer reads it and lists a matching finding under `## Accepted earlier` instead of counting it.

## What may be recorded

Only a finding the developer declined in their own words or by their own choice at a gate: a decision to revisit answered **keep the decision**, or a finding they named after picking **record accepted exceptions**. Never a finding merely kept in the report, never one the Verifier rejected, never on your own judgement. A Critical finding is recorded like any other and still stands in every later review: the change-reviewer never moves a Critical.

## The line

Read the finding in full in its findings file. Its exception line is:

```
- <path> · "<the line of code the finding cites, verbatim, trimmed>" · <the finding's Section value> — accepted YYYY-MM-DD: "<the developer's words, or the option chosen>" (<context_id> F-<n>)
```

- `<path>` and the cited line come from the finding's heading location: open the file at that line with Read and copy the line. In a Review Changes run whose `Head checked out:` is `no`, copy it from the finding's `Explanation` instead; when the finding quotes no line, it cannot be recorded: say so in one line and record the others.
- A finding located `—` has no line and is never recorded.
- The quoted text is the key. The record holds while that text stays in that file, wherever it moves; once the text changes, the record is stale and applies to nothing, which is right: changed code is judged again.

Write the exception entry with Write to `.dream-team-tracking/{context_id}/learnings/YYYY-MM-DD-exception-<slug of path>.md`, the slug as `templates/learnings-entry.md` derives it; a name already taken in the tracking directory (another finding in the same file, the same day) gets the first free `-2`, `-3`, as `templates/learnings-entry.md` says. Two lines and nothing else:

```
## [YYYY-MM-DD] exception <path>
[EXCEPTION] <the exception line above, without "- ">
```

Then run `bash .claude/tools/remarks.sh accept <that file>` at once, from the project root: the developer's choice at the gate is the consent, so this entry does not wait for the closing question. Write and accept one finding at a time: the next finding's entry is written only after this one is accepted, so no entry is overwritten before it is accepted. Log `Exception recorded: F-<n> · <path> → <the tool's line>` in the Decisions log, the tool's `added:` or `already there:` line verbatim, and name the recorded findings and those lines in the final report.

**In a Review Changes run**, the accepted-exception entries are the only files of the repository that run writes, and only when `Head checked out:` is `yes`, so that they land on the branch whose code they are about. Otherwise write nothing, run nothing, and print in the report each entry's two lines and its file name, for the author of the change to add under `<remarks dir>` on that branch; log `Exception recorded: F-<n> · <path> → not written — head not checked out`.

## The shared copy

The entry is a remark like any other: from the remarks dir every later review on a working copy that has it reads it, and the private-mode triage of `/generate-knowledge` or the refresh turns it into a rule file of kind `exception` in the knowledge dir's `rules/`; from then on every developer's reviews read it there.

**What you never do here:** write to `REVIEW-CHECKLIST.md` or any other knowledge file, record a finding the developer did not name, or reword the cited line.
