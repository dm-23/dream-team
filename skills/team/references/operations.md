# Operations

Some work ends with a step no role may take: a deploy, a rollback, a restart, a reading from a running system. `TOOLCHAIN.md → ## Operations` lists those commands, each with who runs it and whether it is read-only. That section is the whole permission; a command not in it is the user's, and you hand them the command and wait.

- A row marked `user` is never run by you or a subagent. Give the command verbatim via AskUserQuestion, with the option to run it themselves or to skip, and record their answer.
- A row marked `orchestrator with per-command approval` you may run yourself, one AskUserQuestion per command quoting it exactly, never batched, never rephrased. A read-only row may instead be handed to the ResearcherExplorer by handoff, naming the row under `constraints`.
- A developer who says, in an AskUserQuestion answer or in a message, that read-only operations may run without asking for the rest of this run has given a **standing approval**. Write it as `{date} — standing: read-only operations — "<the developer's words, verbatim>"` in status.md → "Decisions log", only from those words, never inferred from a pattern of yes answers. While that line exists, rows marked `orchestrator with per-command approval` **and** read-only run without the question; every other row still asks; every command is still logged. The line expires with the run and is not carried into a linked run.
- Every command run under this section is logged in status.md → "Operations log" with its exit code and one line of output; longer captures are kept under the run's `run/` directory and the log names the file.
- An operations script that happens to build or test on the way (a deploy that runs the suite first) is still an operations command: run it as listed, report what it ran, and never treat its green as the Reviewer's verdict — the review already happened, or has not happened yet and still must.
- Nothing here changes a workflow's gates. A deploy comes after the final review and the commit the user approved, never in place of either.

Without an `## Operations` section in TOOLCHAIN.md, this section does nothing, and `/generate-knowledge` is where it would be added.
