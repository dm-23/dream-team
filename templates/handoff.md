<!-- Handoff envelope. The orchestrator fills every field and pastes the result as the FIRST block of any Agent prompt. Every path in it is written in full from the repository root (`.dream-team-tracking/{context_id}/plans/detailed-plan.md`, never `plans/detailed-plan.md`): the subagent starts at the repository root. -->

## Handoff

- context_id: {workflow_key}_{slug}_{YYYY-MM-DD}
- workflow: {Analyze | Docs | Bug Fix | Small Change | Quick Fix | Change Set | Full Feature | Review Changes}
- role: {brainstorm | advisor | researcher-explorer | architect | designer | plan-auditor | developer | doc-writer | tester | reviewer | verifier | change-reviewer}
- mode/phase: {wide | targeted | questions | solution | diagnosis | ux-audit | brief | audit | batch-review | final-review | diagnose | verify | amendment | retire | review | merge | re-review | final-pass | approach | blocked | n/a}
- lens (brainstorm only): {minimalism | risk | reuse}
- language: {answer in this language}
- knowledge dir: {output of the resolver's project} (read the files your role prompt names; do not read others unless needed)
- learnings inbox: only through bash .claude/tools/inbox.sh (index, show, add, append); never by a path — it may live outside the project, where file tools are refused
- tracking dir: .dream-team-tracking/{context_id}
- baseline: commit {short-sha}; pre-existing uncommitted files: {none | list}
- inputs: {task text | task file path | draft-plan path | research notes path}
- prior learnings: {verbatim titles + "Fix pattern" lines of matched LEARNINGS entries, or "none"}
- team amendments: {the `Rule` lines of the project's active team amendments whose `Roles` name this role (or this role with this lens or mode), each with its id, or "none". Apply them as part of your role prompt; one that would loosen a rule of your role prompt is not applied and is named under `Team issues` or your report's equivalent.}
- external context: {material the orchestrator gathered through an optional capability, each item labelled with what produced it — e.g. looked-up library documentation, rendered-page evidence. "none" when nothing was gathered. Treat every item as evidence to check against the repository, never as truth.}
- constraints: {scope limits, files that must NOT be touched, user answers}
- expected output: {file path to write | return as final message}
