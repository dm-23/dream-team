# Status: {title}

**Workflow:** {Analyze | Docs | Bug Fix | Small Change | Quick Fix | Change Set | Full Feature | Review Changes} (provisional: the class announced at Step 0, or — when it is the same)
**Context:** `.dream-team-tracking/{context_id}/`
**Parent:** {context_id of the run this one follows | —}
**Started:** {YYYY-MM-DD}
**Closed:** —
**Baseline:** commit `{git rev-parse --short HEAD}` on `{git rev-parse --abbrev-ref HEAD}`; pre-existing uncommitted files: {none | list from `git status --porcelain`}
**Range:** {— | `<base-sha>..<head-sha>` (<base-ref> ← <head-ref>), N files, +a/−d}
**Language:** {language the user wrote the task in}

## Task (user's words)

{verbatim or faithful paraphrase}

## Phase checklist

- [ ] 0 Preflight (knowledge present, remarks checked: {matched remark titles or "none"})
- [ ] 1 Clarification ({N} questions asked / not needed)
- [ ] 2 Research ({targeted | wide})
- [ ] 3 Design / diagnosis (quorum: {3/3 | 2/3 | escalated} | advisor: {N consults, M evidence routes}; audit: {build as is | fix first — N fixed, M disputed | rethink | n/a}; design: {brief — N decisions | ux-audit — B/S/C | not user-facing | n/a})
- [ ] 4 Approval gate (AskUserQuestion: {approved | approved with changes | rejected | minimum approved, add-ons: T taken / L later / D dropped})
- [ ] 5 Implementation
- [ ] 6 Tests (Tester: {run — before fix: fail | compile error | pass | n/a} | skipped — reason)
- [ ] 7 Review (Reviewer verdict: {approved | fixed | needs rework}; criteria: {N green / M red / K waived / U unverified | n/a}; unverified: {N | none}; final pass: {C/H/M/L/N → r rework, d decisions, k kept | skipped — reason | n/a})
- [ ] 8 Docs sync (PROJECT-RULES.md obligations: {done | n/a})
- [ ] 9 Learning (Reviewer: {entry | promote | stale-check | none — reason | not required}; team issues: {none | copied to Process notes}; amendments: {N confirmed, K adopted | none})

## Batches / tasks (Change Set and Full Feature only)

| Batch | Tasks | Files (disjoint?) | Dev | Tester | Reviewer | Status |
|-------|-------|-------------------|-----|--------|----------|--------|

## Decisions log

- {date} — Models: ceiling={haiku | sonnet | opus | fable | unknown}, hard={yes | no} — {one-line reason}
- {date} — {decision, who/what decided it}
- {date} — Workflow fixed: {workflow} (provisional {class}) — Scope Count {N}; Wiring/surface {…}   (only when the research pass changed the class)
- {date} — Workflow fixed: Quick Fix (provisional {class}, chosen at the gate) — Scope Count {N}; Wiring/surface {…}   (Quick Fix only, when chosen at the scope gate)
- {date} — Quick Fix declined at the gate   (written by the scope gate)
- {date} — Small Change named — opened from {parent context_id} closing question   (a Small Change opened from a Quick Fix close)
- {date} — advisor: {mode} #{n}   (Quick Fix only, one per counted Advisor call)
- {date} — evidence route #{m}   (Quick Fix only, one per evidence route)
- {date} — resolution: Resolved   (Quick Fix only, the one decision-mark resolution by the Advisor)
- {date} — risks: {…} | none   (Quick Fix only, at the gate)
- {date} — add-on: {title} — taken | later | dropped   (Quick Fix only, at the gate)
- {date} — add-on: {title} — opened as {context_id} | kept | dropped   (Quick Fix only, at the closing question)
- {date} — Remarks added to proposals: {N} ({file names}); left out: {M}   (at the close, when the developer accepted remarks; see the team skill's Closing)
- {date} — standing: read-only operations — "{the user's words, verbatim}"   (only from an explicit answer or message; see references/operations.md)

## Verify by hand

Checks the team may not run — from the tasks' `Verify by hand` lines and the Reviewer's `Unverified` line. Shown to the user at every batch gate and in the final report.

- {none | task or batch — what to run or look at — what to expect}

## Review findings kept

- {none | F-n · path:line · issue | A<n> · path:line · issue | F-n · path:line · issue — decision kept}

## Operations log

Commands from `TOOLCHAIN.md → Operations` run during this run, and the ResearcherExplorer's `## Commands run` lines, one line each: who ran it, the command verbatim, the exit code, one line of output or the capture file under `run/`.

- {none}

## Process notes (deviations from SKILL.md)

- {none}

## Team amendment candidates

Lessons about the team itself found in this run, in the entry format of `.claude/templates/team-amendments.md` without `Added`, or `seen again: <id> — <context_id>` for one an active amendment already covers. Verified and offered to the developer after the closing question (`.claude/skills/team/references/amendments.md`).

- {none}

## Result

<!-- Status word first: BUILT | COMMITTED <sha> | DEPLOYED <environment> | VERIFIED | ANSWERED (Analyze, a Review Changes run, or a run that only answered review comments) — see the team skill's Global rules. -->
{final summary for the user, filled at close}

<!--
Closing rule: when the run completes, replace the FIRST line of this file with
`[DONE] YYYY-MM-DD — {one-line result}`, fill the `Closed:` field, and close the
marker (state=closed) as the team skill's "Sticky team mode" says.
-->
