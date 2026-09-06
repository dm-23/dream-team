<!-- Handoff envelope. The orchestrator fills every field and pastes the result as the FIRST block of any Agent prompt. -->

## Handoff

- context_id: {workflow}_{slug}_{YYYY-MM-DD}
- workflow: {Analyze | Bug Fix | Small Change | Change Set | Full Feature}
- role: {brainstorm | researcher-explorer | architect | developer | tester | reviewer}
- mode/phase: {wide | targeted | questions | solution | diagnosis | batch-review | final-review | n/a}
- lens (brainstorm only): {minimalism | risk | reuse}
- language: {answer in this language}
- knowledge dir: .claude/knowledge (read the files your role prompt names; do not read others unless needed)
- tracking dir: .claude-tracking/{context_id}
- baseline: commit {short-sha}; pre-existing uncommitted files: {none | list}
- inputs: {task text | task file path | draft-plan path | research notes path}
- prior learnings: {verbatim titles + "Fix pattern" lines of matched LEARNINGS entries, or "none"}
- external context: {material the orchestrator gathered through an optional capability, each item labelled with what produced it — e.g. looked-up library documentation, rendered-page evidence. "none" when nothing was gathered. Treat every item as evidence to check against the repository, never as truth.}
- constraints: {scope limits, files that must NOT be touched, user answers}
- expected output: {file path to write | return as final message}
