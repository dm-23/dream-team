# Team amendments

Read first: `review-comments.md` (candidates from review comments)

A team amendment is a lesson about the team itself, found in this project: a rule a role lacked, a recommendation that was wrong, a step that let a mistake through. The team is updated only by the lead, from a separate repository, and maybe rarely. So the lesson is kept here and applied by this project's team until an update absorbs it. The keys are in `team-manifest.json → amendments`: the collector `amendments.file`, the lead's resolution list `amendments.resolvedFile`, the entry format `amendments.template`, and the limits `maxActive` and `maxPerClose`. Write the collector only with Edit and Write.

An amendment enters only verified and adopted. A rule that reaches every role unproven is how one wrong sentence turns into code four runs in a row.

## Role files

A `Roles` value names a role prompt, and a `Proposal` names a team file. Hand the Verifier the deployed path:

- `<role>`, or `<role>:<lens or mode>` → `.claude/agents/<role>.md`
- `orchestrator` → `.claude/skills/team/SKILL.md`, plus the workflow reference the amendment is about
- a reference such as `skills/team/references/quorum.md` → `.claude/skills/team/references/<file>`
- a template such as `templates/status.md` → `.claude/templates/<file>`

## Step -1

1. No collector file → every handoff's `team amendments` field is `none`; nothing else here runs.
2. Compare its `Team version checked:` line with `team.version`. Equal → continue at "Active". Different → "Retirement" runs before the run's first workflow step, because a handoff needs the run's context id. For a new run that is right after Step 0 has created `status.md` and the marker. For `/team resume` it is right after the resumed `status.md` is read, before the phase it continues.

## Retirement

The team was updated since the collector was last checked.

1. In Bash, for each entry's id, `grep -F` `amendments.resolvedFile` for the id followed by a tab, so that `x-20261106-1` never matches the row of `x-20261106-10`. Remove every entry the list names, whatever its outcome (`adopted`, `declined`, `superseded`): the lead has decided it. List the removed ids in the run's Process notes.
2. If entries remain, one handoff → Verifier, `mode: retire`. `inputs`: the remaining entries verbatim, and for each the deployed path of its `Proposal` file ("Role files"). Model: the verifier floor, since no workflow is fixed yet. Remove the entries it reports `absorbed`. Keep `not absorbed` and `unclear`, and name the `unclear` ones in this run's final report.
3. Rewrite the `Team version checked:` line to `team.version`. A collector with no entries left keeps only its header.

## Active

Put into every handoff's `team amendments` field the `Rule` lines whose `Roles` name that role, or that role with its lens or mode, each with its id; otherwise `none`. Apply the `orchestrator` lines yourself. A role that finds its amendment in conflict with its own prompt follows its prompt and reports the conflict; that conflict becomes a candidate to revise the amendment.

## Candidates

During the run, write each lesson about the team into `status.md → ## Team amendment candidates`, in the entry format without `Added`, the `Evidence` lines pointing at this run's tracking files. Four sources:

- a team-amendment candidate from `review-comments.md` step 8;
- a finding of a Review Changes run with a `Missed:` line whose reason is a missing rule (`review_changes.md` step 6): another reviewer's thread held and the team's own review did not raise it;
- each item of a Reviewer's `Team issues` line;
- a Process notes deviation you recorded because a rule of the team did not fit the case.

First read the collector. When an active entry already says the same thing, write `seen again: <id> — <context_id>` instead of a new candidate.

## Seen again

At close, before anything below, add one to the `Seen` count of every entry a `seen again` line names, append this run's id to that line, and log `amendment <id>: seen again` in "Decisions log". It needs no question: the entry is already adopted, and the count is what tells the lead that a proposal keeps biting. It runs whether or not the run has new candidates.

## At close

After the closing question is answered, when there are candidates other than `seen again`:

1. One handoff → Verifier, `mode: amendment`. `inputs`: the candidates, numbered, and the deployed path of each role file their `Roles` name ("Role files"); the run's verifier cell, or the verifier floor in Analyze and Docs. Drop every REJECT and log it with its reason in "Decisions log".
2. With confirmed candidates, one AskUserQuestion, at most `maxPerClose` of them: "Adopt these team amendments in this project?". It is a single-select, "adopt / don't adopt", for one candidate, and a multi-select over the candidates for two or more. Each option shows the candidate's `Rule` and `Why`. Candidates past the limit stay in "Team amendment candidates", are named in the final report, and are offered again at the next run's close.
3. For each adopted one: if the collector is missing, create it from `amendments.template` with `Team version checked:` set to `team.version`. Append the entry with its id and `Added`. The id is `<project>-<YYYYMMDD>-<n>`: `<project>` is the repository directory's name in lower case with every run of other characters turned into one hyphen; `<n>` counts that day's entries in the collector from 1. Log each answer in "Decisions log", and fill the phase 9 line's `amendments:` part.

## Report

The final report names every amendment adopted in this run by id and title, and the number now active. It points to `amendments.file`: its `Proposal` lines are the proposals for the lead. When the active count is above `maxActive`, add one line: the collector is due to be sent to the lead.
