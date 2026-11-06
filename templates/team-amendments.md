# Team amendments

Team version checked: {team.version}

Each entry below is one amendment: a lesson about the team itself, found in a run of this project. Its `Rule` is applied by the roles its `Roles` line names, through the `team amendments` field of their handoffs, until the team absorbs it or the lead declines it. `Proposal` and `Why` are written for the lead and must stay generic: no project names, paths, symbols or code. Only the orchestrator adds an entry, after the Verifier confirmed it and the developer adopted it at the close of a run (`.claude/skills/team/references/amendments.md`). After a team update the orchestrator removes the entries the new version absorbed or the lead resolved, and rewrites the `Team version checked:` line.

## {id} — {title}
- Roles: {role, role:lens or role:mode, comma-separated; e.g. brainstorm:minimalism, reviewer, orchestrator}
- Rule: {one imperative sentence the named roles apply in this project}
- Proposal: {team file, e.g. agents/reviewer.md} — {the generic change, in English}
- Why: {one generic sentence: what went wrong without it}
- Evidence: {context_id} → {tracking path:line}; ...
- Seen: {N} — {context_id}, ...
- Added: {YYYY-MM-DD}, team {version}, adopted at the close of {context_id}
