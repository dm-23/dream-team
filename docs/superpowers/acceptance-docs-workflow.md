# Acceptance: the Docs workflow and the leak fixes

Run this from a session opened in a project the team is deployed into, not from the
team repository. The team repository has no `.claude/knowledge/` of its own, so a run
started here stops at preflight and proves nothing.

Reopen the session first. A session holds the role and command prompts it loaded at
startup, so a run begun before the update measures the previous version.

## 1. A doc-only task routes to Docs

    /team update the readme so the install section matches what the setup command actually does

Expected, in order:

- The announced workflow is **Docs**.
- One question at most, and only if the target file is ambiguous.
- An approval question naming the files and a one-line plan per file, before anything
  is written.
- No brainstorm, no research pass, no tester, no reviewer, no toolchain run, no
  learnings entry.
- A final summary naming the changed files and saying what was verified against which
  source path.

Then check the run's own record:

    cat .claude-tracking/Docs_*/status.md

Phases 2, 3, 6, 7, 8 and 9 read `n/a — Docs`. The first line starts with `[DONE]`.
`.claude-tracking/.team-mode` no longer exists.

## 2. The gate holds

Repeat with a task whose file list you then **reject** at the approval question.
Expected: nothing is written, and the run closes or re-asks. A repository diff after a
rejection is a failure of the one thing the Docs workflow does not cheapen.

## 3. A doc task that needs code stops

Ask for documentation of behaviour the project does not have:

    /team document the offline mode in the readme

Expected: the run reports that the behaviour could not be verified in the code, writes
nothing claiming it exists, and asks whether to open a different workflow. Prose
describing a feature that is not there is the failure this rehearsal exists to catch.

## 4. A report request is still a report

With no run open:

    /team write up a report on how the run state is stored

Expected: a self-contained HTML file under `.claude-tracking/{context_id}/reports/`,
handed over as a path. Not a documentation edit, not chat text, whichever workflow the
run picks.

## 5. The research report is a file, not a message

Run any bug fix or small change. Then:

    ls .claude-tracking/*/research/exploration.md

Expected: the file exists. During the run the three parallel proposals were handed its
path; if the orchestrator pasted the exploration text into them instead, the leak is
still open, and this file is the evidence that it did not need to.
