# Accepted exceptions

Read when the developer keeps a decision at the final-pass gate (`final-pass.md`), or picks "record accepted exceptions" at the close of a Review Changes run (`review_changes.md` step 7).

A finding the developer consciously declined is true and stays declined. Without a record, the next review of the same code raises it again, the developer declines it again, and the review's findings lose their weight. The record is an inbox line; the change-reviewer reads it and lists a matching finding under `## Accepted earlier` instead of counting it.

## What may be recorded

Only a finding the developer declined in their own words or by their own choice at a gate: a decision to revisit answered **keep the decision**, or a finding they named after picking **record accepted exceptions**. Never a finding merely kept in the report, never one the Verifier rejected, never on your own judgement. A Critical finding is recorded like any other and still stands in every later review: the change-reviewer never moves a Critical.

## The line

Read the finding in full in its findings file. Write the one line below into a file in the run's tracking directory, then add it to the inbox with `bash .claude/tools/inbox.sh append review-exceptions.md <that file>`, never by a path. The tool creates `review-exceptions.md` when it is missing; the first time, write the file's first line above the entry, `# Review exceptions — an inbox; live entries become rule files of kind exception` (`bash .claude/tools/inbox.sh show review-exceptions.md` prints `(missing)` after the name when it is):

```
- <path> · "<the line of code the finding cites, verbatim, trimmed>" · <the finding's Section value> — accepted YYYY-MM-DD: "<the developer's words, or the option chosen>" (<context_id> F-<n>)
```

- `<path>` and the cited line come from the finding's heading location: open the file at that line with Read and copy the line. In a Review Changes run whose `Head checked out:` is `no`, copy it from the finding's `Explanation` instead; when the finding quotes no line, it cannot be recorded: say so in one line and record the others.
- A finding located `—` has no line and is never recorded.
- The quoted text is the key. The record holds while that text stays in that file, wherever it moves; once the text changes, the record is stale and applies to nothing, which is right: changed code is judged again.

Log `Exception recorded: F-<n> · <path>` in the Decisions log, and name the recorded findings in the final report.

## The shared copy

This file is one developer's. `/generate-knowledge` turns its live entries into rule files of kind `exception` in the knowledge dir's `rules/`, with the inbox triage and under its consent; from then on every developer's reviews read them.

**What you never do here:** write to `REVIEW-CHECKLIST.md` or any other knowledge file, record a finding the developer did not name, or reword the cited line.
