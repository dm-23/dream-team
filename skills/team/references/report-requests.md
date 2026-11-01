# Report requests

Read when a message asks for a report, in any workflow and at any step.

A message asking for a report — "generate a report", "make a report", "I need a report on X", "write up the findings", in any language and any phrasing — means exactly one thing: a self-contained HTML file built from `.claude/templates/report-html.md`, written to `.dream-team-tracking/{context_id}/reports/{topic}.html`, handed to the user as that file path in chat. Read the template before writing; never reconstruct its structure or styles from memory.

This is the default. It does not depend on how long the findings are, on which workflow is running, or on the user saying "shareable". It changes only when the same message names a different form explicitly — "a short report in chat", "just answer in chat", "in Markdown", "put it in {path}". Such a request overrides the format and the location; it never cancels the report itself, and one given for an earlier report does not carry over to the next one.

Two prohibitions, both absolute. Never publish a report through the Artifact tool: the user rejected cloud publishing for this project, because reports can carry material covered by a non-disclosure agreement. And never hand back chat text, a Markdown file or a canvas in place of a report that was asked for.
