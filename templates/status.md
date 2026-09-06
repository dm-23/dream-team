# Status: {title}

**Workflow:** {Analyze | Bug Fix | Small Change | Change Set | Full Feature}
**Context:** `.claude-tracking/{context_id}/`
**Started:** {YYYY-MM-DD}
**Closed:** —
**Baseline:** commit `{git rev-parse --short HEAD}`; pre-existing uncommitted files: {none | list from `git status --porcelain`}
**Language:** {language the user wrote the task in}

## Task (user's words)

{verbatim or faithful paraphrase}

## Phase checklist

- [ ] 0 Preflight (knowledge present, LEARNINGS checked: {matched entry titles or "none"})
- [ ] 1 Clarification ({N} questions asked / not needed)
- [ ] 2 Research ({targeted | wide})
- [ ] 3 Design / diagnosis (quorum: {3/3 | 2/3 | escalated})
- [ ] 4 Approval gate (AskUserQuestion: {approved | approved with changes | rejected})
- [ ] 5 Implementation
- [ ] 6 Tests (Tester: {run | skipped — reason})
- [ ] 7 Review (Reviewer verdict: {approved | fixed | needs rework})
- [ ] 8 Docs sync (PROJECT-RULES.md obligations: {done | n/a})
- [ ] 9 LEARNINGS entry ({appended | not required})

## Batches / tasks (Change Set and Full Feature only)

| Batch | Tasks | Files (disjoint?) | Dev | Tester | Reviewer | Status |
|-------|-------|-------------------|-----|--------|----------|--------|

## Decisions log

- {date} — {decision, who/what decided it}

## Process notes (deviations from SKILL.md, for the next retrospective)

- {none}

## Result

{final summary for the user, filled at close}

<!--
Closing rule: when the run completes, replace the FIRST line of this file with
`[DONE] YYYY-MM-DD — {one-line result}` and fill the `Closed:` field.
-->
