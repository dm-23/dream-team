# Dream Team

A multi-agent development team for Claude Code: twelve subagents, three commands, one manifest.

It knows nothing about your technology and nothing about your project. Everything specific is generated from your repository on first run: the project knowledge is committed once for everyone who works on the branch, and what concerns one developer or one machine stays on that machine. The same repository plugs into any codebase unchanged.

---

# Part 1 — Onboarding

## Install into a project

The team's contents are placed directly in your project's `.claude/`. That is the directory Claude Code already scans for agents and commands, so nothing has to be linked, duplicated or registered afterwards. The commands below are bash; on Windows run them from Git Bash, which the hooks need anyway.

The supported install is a clone in place: `.claude/` is a checkout of this repository, and updating it is a pull.

```bash
cd <your project>
git clone https://github.com/dm-23/dream-team.git .claude
```

Your project's own repository sees `.claude/` as a nested repository and does not commit its contents; every developer clones it the same way. A `git add .` in the project would still record the clone as a bare gitlink (an empty `.claude/` for whoever clones the project next), so `/team-setup` adds `.claude/` to your `.git/info/exclude` on this machine; add it to the project's `.gitignore` if you prefer one line for everyone. When `.claude/` must not be a repository of its own (it already exists, or your tooling objects), copy the contents over it instead:

```bash
git clone --depth 1 https://github.com/dm-23/dream-team.git /tmp/dream-team
cp -r /tmp/dream-team/. .claude/ && rm -rf .claude/.git .claude/.github /tmp/dream-team
```

Either way you end up with `.claude/agents/`, `.claude/skills/`, `.claude/templates/`, `.claude/hooks/` and `.claude/team-manifest.json`. Commands keep their short names: `/team`, `/generate-knowledge`, `/team-setup`.

## First run

Open Claude Code in the project and run three commands in order.

| Step | Command | What it does |
|------|---------|--------------|
| 1 | `/team-setup` | Checks the install, hides generated files from version control, wires the sticky-mode hook and the guard, and asks one question at most: which of the missing optional capabilities to install. Nothing to answer when nothing is missing |
| 2 | `/generate-knowledge` | Explores your repository and writes the ten knowledge files the team reads. In an empty folder it asks whether the stack is decided and writes the ten files as scaffolds, each marked on its first line, to be regenerated once there is code |
| 3 | `/team <task>` | Runs the workflow |

Step 2 takes a few minutes and is the only step that reads your whole codebase. When your branch already has the project's knowledge committed under `.dream-team/knowledge/`, skip it: the knowledge is there, and from then on the refresh keeps it current, run by whoever maintains the knowledge (see "The shared knowledge and the branches"). While the knowledge is not committed, repeat step 2 after major architecture changes.

## Daily use

```
/team fix the crash on an empty service response
/team add a reports page with filters and export
/team status      — where the current run stands
/team stop        — leave the run parked and return to normal chat
/team resume      — pick it back up
```

`/team` picks the workflow itself and announces it, and on a small task may offer you Quick Fix before settling the workflow. You approve the plan before anyone writes code.

The two task lines above are not decoration. The team answers in whichever language you wrote the task in and records that language in the run's status file, so a run resumed days later still answers the way it started.

## What to expect

- You are asked up to a handful of clarifying questions, then shown a plan.
- Nothing is written until you approve.
- A Full Feature run stops at gates you control: once when the plan is ready (the plan comes with an HTML page under the run's `reports/`, built after an auditor has attacked it against your code), and again after every batch. At each one you choose to carry on here, or to park the run, commit what is done, and pick it up in a clean session with `/team resume`. Splitting a long run that way is the recommended path, not a fallback.
- Every run leaves a diary in `.dream-team-tracking/`. In runs that change code the reviewer also classifies what the run taught, and a trap worth keeping becomes an entry in the learnings inbox; `Analyze` has no reviewer and so leaves none.
- An `Analyze` run answers in chat, or writes a Markdown file under the run's `reports/` when the findings are long.
- A task about the interface itself — audit it, review it, say what is wrong with a page — is an `Analyze` run with a designer in it: findings ranked by what they cost a person, with the pages to change in order. A user-facing feature gets a design brief before anyone designs the code, and a change to one of your interface conventions is asked, never assumed.
- Ask for a report, in any wording, and you always get the same thing: a self-contained HTML file under the run's `reports/`, built from the report template, with its path given to you in chat. Nothing is published to the cloud. Say you want it some other way — a short answer in chat, Markdown, a particular path — and that message gets what you asked for; the next report request starts from the default again.
- A review of a finished change — a pull request, or a branch against a base — is a Review Changes run. The team resolves the range from your words and the local repository, never reads from or writes to a git remote (read-only `gh` calls on a named pull request are its only contact with the host), and asks one question only when the base or head is missing or the change is larger than sixty files or three thousand changed lines, when it recommends splitting it into separate pull requests. A reviewer that never saw the plan reads the change, the blocking findings are voted on, and you get an HTML page under the run's `reports/` with the counts per severity and a recommendation. It changes no code; afterwards you may open a fix run for the blocking findings or for findings you choose, which needs the reviewed head checked out.
- Three kinds of change are reviewed in their own way. A pull request that merges one long-lived branch into another is not read commit by commit: the team reads how each conflict was resolved, what the merge branch changed itself and what no carried commit explains; when it is unsure whether a pull request is such a merge, it asks you. A change the team reviewed before gets the status of every earlier finding (fixed, not fixed, partially, obsolete) and a review of what was pushed since. A change reviewed in parallel parts gets one more pass over what one part produces and another consumes.
- The reviewer forms its findings before it reads the pull request's existing threads. A thread that holds and that the review did not raise on its own is shown as missed by review, and becomes a proposal to improve the team. The pull request's own checks are named on the page, and a failing one keeps the recommendation from being an approval.
- A finding you consciously decline can be recorded as an accepted exception, at the end of a review or when you keep a decision at the final-pass question. Later reviews list it apart and count it nowhere while the cited line stays as it was; `/generate-knowledge` shares your exceptions with the other developers as rule files in the knowledge; once the knowledge is committed, it submits each one as a remark, which the refresh turns into a rule file. A Critical finding is never set aside this way.
- When the Reviewer approves a Full Feature or a Change Set, an independent reviewer reads the same change without the plan (a Bug Fix, Small Change or Quick Fix only when you ask or the run was judged hard). Its serious findings are voted on and reworked; the rest, and any decision of yours it would revisit, come to you in one question: fix all, fix selected, or keep in the report. It never changes the Reviewer's verdict.
- The team reports the build and test results it actually ran, not a promise.
- A message from the team that ends with something it needs from you — a commit, a confirmation, access — ends with `Waiting on you: …`; a message that needs nothing ends without it. The result is named with one of four words: built, committed, deployed to a named environment, or verified by you.
- When a run closes, the team stays listening. Commit, deploy, check, then write what you found in the same session: a confirmation updates the run's result, a defect opens a linked fix that starts from the delivered change, a new task starts a new run, and a question about something else is just answered. `/team stop` ends the listening.
- While the knowledge is not committed in your branch, a run offers to refresh it first when the learnings inbox is due or the knowledge is a scaffold on a project that now has code, and the closing question offers it when the run reported stale knowledge. Once the knowledge is committed, a run never rewrites it: it offers to triage your inbox when the inbox is due, and the closing question offers to pass on what the run met as remarks to the release branch. You can always say no, and the run goes on without it.
- Deploys, rollbacks and readings from a running system are not a workflow step. When your repository documents such commands, `/generate-knowledge` lists them in an Operations section of `TOOLCHAIN.md`, and the orchestrator runs only the ones marked for it, one approval per command, logging each in the run's status file. Say in so many words that read-only operations may run without asking for the rest of the run, and the orchestrator records your words in the Decisions log and stops asking for those; every other command still asks, every command is still logged, and the approval ends with the run. Everything else there is yours to run.

## Requirements

Claude Code, a version-controlled project, and a bash shell (Git Bash or WSL on Windows). Bash runs the sticky-mode hook, the guard, the neutrality check and the scripts under `checks/`. Without it those are unavailable: a run does not follow you across sessions and the guard denies nothing. The workflows themselves still run.

---

# Part 2 — How it works

## Four layers

| Layer | Where | Committed | Who owns it |
|-------|-------|-----------|-------------|
| Team core | `.claude/agents`, `.claude/skills`, `.claude/templates`, `.claude/hooks`, `.claude/team-manifest.json` | in this repository; a clone of it inside the project, which the project's own repository sees as nested and does not commit | team maintainer |
| Run state | `.dream-team-tracking/` | never | written during runs, shared by every edition of the team |
| Project knowledge | `.dream-team/knowledge/` | yes, by knowledge-only commits | the project; generated by `/generate-knowledge`, kept current by `/generate-knowledge refresh`, read by both editions |
| Operative knowledge | the learnings inbox in the developer's profile, `~/.dream-team/<project key>/`; `CAPABILITIES.md` in `.dream-team-tracking/operative/` | never | one developer: the inbox is shared by all of that developer's working copies of the project and by both editions, written by the agents through `tools/inbox.sh`; `CAPABILITIES.md` describes one working copy and is written by `/team-setup` |

The learnings inbox lives outside the project, in the developer's profile, so that every working copy of a project on one machine (a checkout per release branch, a second clone for a hotfix) and both editions of the team read and fill the same inbox. The profile root is `knowledge.profileDir` in the manifest, `~/.dream-team` in both editions; the project key comes from the repository's remote address: the name of the repository, a hyphen, and a short hash of the address, for example `shop-3f9a1c2e`, so two copies cloned from the same remote address get the same key and another repository gets another one; a copy whose origin is a different address, such as a clone made from a local checkout, gets its own key and its own inbox. `/team-setup` moves an inbox into the profile and reports the directory and the key. The inbox stays per copy, in `.dream-team-tracking/operative/`, in three cases, and `/team-setup` names the one that applies: the repository has no remote, so there is no key; `knowledge.profileDir` is empty in the manifest, which turns the profile off; or the profile directory cannot be created or written. An older `LEARNINGS.md` whose entries the move cannot split also keeps the inbox per copy until it is fixed, and setup says what to fix. Nothing else about the inbox depends on where it lives. The team reaches it only through `tools/inbox.sh`: no role, reference or command opens a path inside it or writes one in the text of a command, so the team never asks for access to it. Each edition keeps its own `CAPABILITIES.md` in the working copy (`operative/claude/` and `operative/copilot/`), because it describes what that edition's session can use there.

Layer one is a single flat copy of this repository — no wrapper directory, no second copy to keep in sync. Every path the team names is one of the paths above, so the deployment does not depend on where you cloned from or what you called the clone.

Layer two and layer four are hidden together: `/team-setup` adds `.dream-team-tracking/` to `.git/info/exclude`, which is machine-local and needs no commit. The inbox in the profile lies outside the repository and needs no hiding. `/team-setup` writes to your project's own `.gitignore` in one case only: when that file already carries a line for the legacy run-state directory, the line is replaced by the current one, so a project that chose to commit its ignore keeps that choice current. The hook wiring in `.claude/settings.json` is machine-local in both installs: the team's own `.gitignore` hides it, and `/team-setup` writes it on every machine without asking. Layer three is the only one a project commits, and it is not hidden: it is read by every edition from the same path, so no generated file may name a team path of either edition.

This split is the whole design. Layer one carries process and roles. Layer three carries every fact about your stack, your commands and your rules, shared by everyone who works on the branch. An agent never hardcodes a language, a framework, a build command or a lint rule; it reads them. Facts that describe one machine or one working copy (a missing tool, the capabilities installed here, the learnings inbox) stay in layers two and four and never reach the committed files.

### The shared knowledge and the branches

`.dream-team/knowledge/` changes only through knowledge-only commits and pull requests. A product branch, one that carries a feature or a fix, never modifies it, and a run never writes to it by itself; a review of a change that touches the knowledge and any other file reports it as a High finding, because knowledge travels in a change of its own. Once the knowledge is committed, two flows change it: any developer submits remarks, and whoever maintains the knowledge runs the refresh, the one run that rewrites it.

**Waiting state.** Until `.dream-team/knowledge/` is tracked in your branch, `/team-setup` says it is waiting for knowledge to land in the repository, and the team keeps reading the private copy that lives in the edition's own directory (`.claude/knowledge/` or `.github/dream-team/knowledge/`). Nothing is created under `.dream-team/` in your working tree.

**The first knowledge commit.** One person, normally the lead, makes it on the current release branch:

1. Update the team in that checkout.
2. Run `/team-setup`. It moves the operative files and, since the shared directory is not there yet, tells you which command the next step needs. It never runs that command itself.
3. Run `bash .claude/tools/migrate-knowledge.sh --first-commit` (the Copilot edition: `bash .github/dream-team/tools/migrate-knowledge.sh --first-commit`) from the project root (add `--from <dir>` when both editions left a private copy and you must choose). It moves the project files into `.dream-team/knowledge/` and extracts the rules people authored there into rule files under `rules/`.
4. Run `/generate-knowledge`. It works on the files in the new place, takes the machine-specific section out of `TOOLCHAIN.md`, removes any team path from the text, and writes a `Covers:` line on every file it regenerates. It writes `BASELINE` only when it regenerated every required file (and the working copy has no uncommitted change outside the knowledge and is on a branch); a migration usually regenerates only the stale files, so usually there is no baseline yet.
5. Commit `.dream-team/knowledge/` alone, in a commit that touches nothing else, and push.
6. Run the first `/generate-knowledge refresh` on that branch (see "The refresh" below). It writes the remaining `Covers:` lines and `BASELINE`, in a knowledge-only commit of its own. Until then the drift line of every run reads `missing`.

Everyone else then updates the team on a branch that already has the knowledge. Their `/team-setup` keeps only their operative part and the committed knowledge always wins; setup never edits it. The first time it sees the committed directory, it turns the lines you authored in your private copy that the committed knowledge does not already hold into learnings inbox entries, once, so no accumulated rule is lost. A developer who ran `/team-setup` before the knowledge reached their branch runs it once more after it lands: that pass is the one that imports their private copy's authored rules into the inbox.

**Remarks from a developer's run.** Once the knowledge is committed, a run still writes what it learned into your learnings inbox and never edits the knowledge. When the run met something worth passing on (its review wrote an entry or a mark, or the inbox was due and you put it off), the closing question offers **pass on what this run met — N remarks → <release branch>**. On yes, the team triages your inbox, after a backup: the rules, facts and traps worth keeping are submitted as remarks, and run summaries, obsolete or covered entries, risks without a shown sequence and defects of the team itself (quoted in the report, for the team's maintainers) are removed. `/generate-knowledge` with nothing after it does the same at any time. The release branch is the one `BASELINE` names; `/generate-knowledge Branch: <release branch>` names it when there is no baseline yet or your work belongs to another branch. The submission is `tools/proposals.sh submit`: one file per remark under `.dream-team/knowledge/proposals/`, in one commit on a new branch, `knowledge/proposals-<date-time>`, based on the release branch (its `origin/` copy when your clone has one). The commit is built with git plumbing in a temporary index: nothing is checked out, your working copy, your index and your current branch are untouched, and so no local commit hook runs on it. It prints the two commands that are yours to run, because the team never pushes:

```
push: git push -u origin knowledge/proposals-<date-time>
pull request: knowledge/proposals-<date-time> → <release branch>; one commit, only files under .dream-team/knowledge/proposals/
```

A remark nobody pushes stays personal: it is marked as submitted in your inbox, it lives only on that local branch, and nobody else sees it. Once its pull request is merged into the release branch, the remark is in force for everyone: every run on that branch reads the files under `proposals/` beside the inbox when it looks for prior learnings, until the next refresh turns the remark into a rule or a fact, or rejects it with a reason. `bash .claude/tools/proposals.sh status` (the Copilot edition: `bash .github/dream-team/tools/proposals.sh status`) says for each submitted entry whether it is pending, in force, or closed with the refresh's reason, and the next triage removes the closed ones from your inbox.

**The refresh.** Run by whoever maintains the knowledge, normally the lead a few times a week, and never offered by a run; `Consent: given` in its arguments runs it without a question, so a pipeline can run it later. `/generate-knowledge refresh` runs in place, on the checked-out release branch at the commit it is on, so bring that branch up to date first. It refuses while a run is open, another refresh is in progress, or the knowledge has uncommitted changes. It moves the working copy onto a branch of its own, `knowledge/refresh-<branch>-<date-time>`, at the same commit, and keeps every product change you have in place, modified, staged or untracked. It regenerates the files the drift report marks and the convention files that went stale, gives code no topic covers a topic, writes the `Covers:` lines a file lacks, turns the remarks under `proposals/` into rule files and facts or rejects them, and asks once before it writes. Then `tools/knowledge-refresh.sh finish` moves `BASELINE` to the commit the refresh ran at, runs the shape and neutrality checks, and makes one commit, `knowledge: refresh <branch> to <short sha>`, which touches nothing outside the knowledge and names every remark it consumed or rejected. Your project's commit hooks run on that commit; a hook that rejects it leaves the refresh on its branch, to finish again once the cause is fixed. It switches back to the release branch, carrying your product changes with it, warns about any path outside the knowledge that changed during the refresh (it is not in the commit), and prints the two commands that are yours to run:

```
push: git push -u origin knowledge/refresh-<branch>-<date-time>
pull request: knowledge/refresh-<branch>-<date-time> → <branch>; knowledge only
```

Only the refresh moves `BASELINE`, so two refreshes of one branch at the same time conflict on that file once the branch moved between them (two taken at the very same commit write the same `BASELINE` and conflict only where their regenerated files differ): merge the first, close the second's pull request, and run the second again from the updated branch.

**One refresh line per open release branch.** Every open release branch carries its own `BASELINE` and is refreshed on its own, when its drift line says a refresh is due: a fix branch that changes little is refreshed rarely, a frozen one never. Remarks are submitted to the release branch of the run that made them. When the baseline was taken on another branch, the refresh asks whether this branch was cut from it or a merge brought its knowledge in, and in the second case regenerates every topic that declares paths; the first refresh of a branch and the one after a large forward merge are therefore the expensive ones.

**The private copy stays.** The migration never removes the private copy. It keeps serving the branches that have no committed knowledge yet, such as an old fix branch. When you no longer work on such a branch, run `bash .claude/tools/migrate-knowledge.sh --drop-legacy`: it imports any authored lines the inbox does not hold, backs the private copy up under `.dream-team-tracking/operative/`, and removes it.

**Merging an older release branch into a newer one.** When release branches are merged forward (older into newer), the newer branch's `.dream-team/knowledge/` is kept whole: nothing that the older branch changed there is wanted, because the newer branch has its own knowledge and text about the older branch does not belong in it. Run this during the merge, from the project root:

```bash
git merge --no-ff --no-commit <older-branch>
git rm -rfq --ignore-unmatch .dream-team/knowledge && git checkout HEAD -- .dream-team/knowledge
git commit
```

The second line drops whatever the merge brought into the directory, including files that exist only on the older branch, and restores the directory as it is on the branch you are merging into. If the merge already stopped on conflicts, run the second line there. When the branch you are merging into has no `.dream-team/knowledge/` yet, the `git checkout` fails with a pathspec error; that is expected, because the `git rm` has already left the right state (no directory). `git checkout --ours -- .dream-team/knowledge && git add .dream-team/knowledge` also works during a merge into the current branch (`--ours` is the current branch), but it leaves behind files that exist only on the older branch, so prefer the line above. A merge performed on a server cannot run it; whoever merges there restores the directory afterwards, in a follow-up commit of its own. A rule adopted on the older branch does not reach the newer one by itself, because this merge drops it: submit its remark to the newer branch too, or let whoever maintains the knowledge carry the rule over by hand. An inbox entry is submitted once, so a remark already sent to the older branch goes to the newer one as a new entry:

1. `bash .claude/tools/inbox.sh show learnings/<file>.md` prints the entry. Save it to a file under `.dream-team-tracking/` without the `==>` line and without its `[SUBMITTED` line (`proposals.sh submit` refuses an entry that carries one).
2. `bash .claude/tools/inbox.sh add <that file>` adds it as a new entry.
3. `/generate-knowledge Branch: <newer branch>` submits it to the newer branch.

### How far knowledge lags

The knowledge records the commit it was last verified against in `.dream-team/knowledge/BASELINE` (`commit=`, `date=`, `branch=`), written by the first generation and moved afterwards only by the refresh, and every generated file and topic declares what it covers on a `Covers:` line near its top. At the start of every run, `tools/knowledge-drift.sh` compares that commit with the current one, in your working copy and without contacting a remote, and every handoff carries its report as `knowledge drift`: how many files changed since the baseline, which knowledge files describe changed paths, and which changed paths no knowledge covers. When too many topics are marked, it says a refresh is due instead, and it adds that line too when more remarks wait under `proposals/` than `knowledge.budgets.proposalsMaxFiles`; scaffold knowledge, a missing baseline, or a baseline commit this copy does not have gets one line saying so. A marked topic is still read: where it and the code disagree, the code wins and the agent reports the disagreement. The report never stops a run.

## Directory layout

This repository, and equally the project's `.claude/` after deployment:

```
team-manifest.json             the contract: what must exist, where, and what to check
agents/                        twelve role prompts
skills/                        three commands; skills/team/references/ holds one file per workflow and the shared mechanics the orchestrator reads per step
templates/                     status, handoff, learnings, report, capabilities, stack cards and the interface card
hooks/                         sticky team mode and the guard
tools/                         the run-state and knowledge migrations, the knowledge resolver, the
                               inbox tool and the learnings index, the rule extractor, the drift
                               report, the proposals and refresh tools, the status-line
                               normaliser and the amendment collector
checks/                        the scripts the manifest's checks run: manifest budgets, role and
                               workflow consistency, text encoding, agent and skill frontmatter,
                               the orchestrator's reference files, the integrity check
                               `/generate-knowledge` must pass after shape work, the knowledge
                               shape and neutrality checks, the learnings inbox check, the hook
                               check for sticky mode and the guard, and one test per tool
copilot/                       the GitHub Copilot edition: translation rules, overlays, the
                               installer and its tests
.github/workflows/             this repository's CI; the install removes it from .claude/
docs/                          the team's own documents; never read as project documentation
.gitignore                     hides the private knowledge copy (knowledge/) once deployed; the
                               committed .dream-team/knowledge/ lies outside .claude/ and is never hidden
.gitattributes                 pins LF on the hook files and the clients under tools/; a CRLF checkout breaks them
```

What the team keeps in a project, besides `.claude/`:

```
.dream-team/knowledge/         committed: the ten knowledge files and their topic directories,
                               rules/ (one file per authored rule), proposals/ (remarks waiting
                               for the refresh) and BASELINE (the commit the knowledge was last
                               verified against)
.dream-team-tracking/          never committed, hidden by .git/info/exclude: run state, backups,
                               operative/ (CAPABILITIES.md per edition, and the learnings inbox
                               when it stays per copy)
~/.dream-team/<project key>/   outside the repository, in your profile: the learnings inbox
                               (learnings/, one file per entry, and review-exceptions.md),
                               shared by your working copies of the project and both editions
```

## The roles

Each role is a separate subagent with its own tool set. The narrow tools are the enforcement, not a suggestion.

| Role | Tools | Does | Never does |
|------|-------|------|------------|
| Brainstorm | read only | Three parallel instances propose questions, solutions or a diagnosis | Reads your source; talks to you |
| Advisor | read only | One read-only advisor consulted at the decision points of a Quick Fix: the minimum change, the add-ons, a blocked developer | Searches your source; reads past a cited line; talks to you; edits; returns a patch |
| ResearcherExplorer | read, search, git history, write to run state; a `Build` (cheap only), `Test one` or `Validate` row of the toolchain when the handoff names it | Finds the exact files, symbols and insertion points; runs a named row to confirm a signature, a failing test or a document and lists every command it ran under `## Commands run`, which the orchestrator copies into the run's Operations log | Modifies source; runs a command the handoff did not name |
| Architect | read, search, write to run state | Detailed plan and task breakdown for a full feature | Writes production code |
| Designer | read, search, write to run state | Audits the interface against your users' tasks (Analyze), or writes the design brief a user-facing feature is built from: surface, states, exact copy, the existing elements to reuse, done-when lines | Writes markup or code; proposes a palette, a typeface or a brand; changes a recorded interface convention without your decision |
| PlanAuditor | read, search, git history, write to run state | Attacks the Full Feature or Change Set plan against the code before you approve it | Edits the plan; reads the research that produced it |
| Developer | read, edit, write, formatter, lint and compile check on its own files, a diff of its own files | Implements exactly one task; fixes lint findings on its own lines and counts the pre-existing ones it leaves | Writes or runs tests; lints wider than its own files |
| DocWriter | read, search, edit, write — no shell | Writes documentation, verifying every claim against the code first | Touches source code or tests |
| Tester | read, edit, write, formatter and lint on its own files, runs only its own tests, a diff of its own files | Decides what needs tests and writes them; takes the review findings whose path is a test file | Touches production code |
| Reviewer | read, search, edit, write, full toolchain | Reviews against the generated checklist, runs format, lint, build and tests, classifies what the run taught | Adds features; edits a knowledge file — a stale claim becomes a mark for `/generate-knowledge` |
| Verifier | read, search, git history | Confirms or rejects the Reviewer's manual findings before a rework starts, from the code at the cited line | Edits anything; votes on style or criteria |
| ChangeReviewer | read, search, git history, read-only toolchain rows | Reviews a finished change against the checklist and the team's review baseline, independent of the plan; writes findings with severity, story and required change | Edits anything; checks out a branch; posts to a pull request; reads the plan in a final pass |

The orchestrator is the only role that talks to you. It never writes code and never runs a build.

**Brainstorm lenses.** The three instances are not clones. One argues for the smallest change, one hunts regressions and edge cases, one looks for what already exists in the codebase. A point agreed by two of three is accepted. A three-way split is not resolved silently: it comes back to you as a question. A lens that needs a piece of code it was not given says so, and the team fetches it rather than letting the lens guess; a choice the research or the Architect finds afterwards goes back to the three lenses once, by a count, before it can reach you.

**Model.** No role pins a model in its own file; every agent declares `inherit`. The orchestrator picks the model of each call from `team-manifest.json → modelRouting` and never goes above the model you run the session on — that is the ceiling. Each role also has a floor: Brainstorm, Advisor, Architect, Designer, PlanAuditor and ChangeReviewer opus; Developer, Reviewer, DocWriter and Verifier sonnet; ResearcherExplorer and Tester haiku. Where floor and ceiling clash, the ceiling wins, so a sonnet session runs every subagent on sonnet or below.

**Model routing.** A matrix in the manifest gives every workflow and call a starting tier. A Bug Fix, Small Change or Quick Fix runs its Developer, Reviewer and Verifier on sonnet. The Quick Fix Advisor has the same floor as Brainstorm, so it runs at the Brainstorm tier. Change Set and Full Feature tasks follow their `Complexity`; the Verifier takes the `Complexity` of the Reviewer call whose findings it judges. The Architect, the Full Feature plan audit and the Full Feature final review run on the session model itself. One judgement sits on top. At the start of a run the orchestrator decides whether it is hard: an unclear cause, concurrency, security, a data migration, an invariant across modules, an earlier failed attempt. A hard run moves every call up one tier, still under the ceiling. The ceiling, the verdict and its reason are the first `Models:` line in the run's Decisions log. Brainstorm's cells are the main cost lever, because three instances run on every phase that uses it. Edit the matrix to change the policy. `checks/verify-role-consistency.sh` fails if a role has no floor, a workflow has no block or lacks a cell for a call that workflow makes (the check's own table lists them), a tier is misspelt, or an agent file pins a model.

## The eight workflows

| Workflow | Trigger | Shape |
|----------|---------|-------|
| Analyze | explain, trace, find out | Research, then an answer; when the subject is the interface itself, a designer audits it against your users' tasks first. No code changes. |
| Docs | update the readme, the documentation, the changelog | Your approval of the file list, then one role writes the prose and verifies every claim against the code. No brainstorm, no review, no toolchain. |
| Bug Fix | something is broken | Research, three diagnoses, your approval, a test that fails before the fix when one is needed, a surgical fix, review |
| Small Change | one concern, up to three files | Research, three proposals, your approval, implementation, a test when the plan names one, review |
| Quick Fix | a small fix or change, the minimum first | Research, one advisor instead of three proposals, your approval of the minimum change with each add-on approved, deferred or dropped separately, a test when the fix needs one, review; deferred add-ons are asked about again at close |
| Change Set | a list of independent small items | One research pass, a design brief when the items are user-facing, an audit of the batch plan before your approval, batches with non-overlapping files run in parallel, one combined review |
| Full Feature | a new capability across modules | Questions, wide research, a design brief when the feature is user-facing (its open decisions asked before anything is designed), design, architecture, an adversarial audit of the plan and an HTML page of it before your approval of the plan with its new public API listed first, batched implementation with a stop after each batch, final review |
| Review Changes | review this PR, review the branch against <ref> | Resolve the range; above sixty files or three thousand changed lines, a proposal to split it into separate pull requests, or a review in parallel parts with a cross-part pass if you prefer; a merge of branches and a change reviewed before each take their own road; an independent review, verification of the blocking findings, an HTML page with severity tabs and expandable findings. No code changes. |

`/team` announces a provisional class from your words and fixes the workflow after the research pass, from the files and wiring it found: up to three files and no wiring is a Quick Fix, a Small Change or a Bug Fix, more is a Change Set or a Full Feature. When your words did not name a workflow and the research finds up to three files and no wiring, or a list of independent items within that limit, `/team` asks whether to run it as a Quick Fix or as the Bug Fix or Small Change with three lenses, and recommends Quick Fix unless the run was judged hard, when it recommends the three-lens road and says why. Saying "quick fix" or "as a Quick Fix" reaches it at any size, after you confirm when the evidence is bigger. Apart from the Quick Fix offer, it asks only when your own words named a workflow and the evidence disagrees; the run keeps its directory either way.

## Knowledge files

`/generate-knowledge` writes ten files into `.dream-team/knowledge/`, the directory the project commits and every edition reads. Six describe your codebase; four are the contract the agents run on.

| File | Read by | Contains |
|------|---------|----------|
| `PROJECT-OVERVIEW.md` | all | What the project is, its stack, its domains, its build facts |
| `BACKEND-ARCHITECTURE.md` | most | Layers, patterns, dependencies, anti-patterns, code paths that must change together |
| `FRONTEND-ARCHITECTURE.md` | most | The same for the user interface, plus its design language — what each interface element is here, how states and copy are done — or a note that there is none |
| `DI-AND-STARTUP.md` | architect, developer | Boot sequence, wiring, configuration, background work |
| `TESTING-CONVENTIONS.md` | tester, developer, reviewer | Frameworks, real examples, naming, what is deliberately not covered |
| `SEARCH-PLAYBOOK.md` | researcher | Verified search recipes for this repository |
| `TOOLCHAIN.md` | developer, tester, reviewer | Every command they may run, each marked verified or not, with its source |
| `CODING-STANDARDS.md` | developer, reviewer | Stack card plus your observed conventions; where they conflict, yours wins |
| `REVIEW-CHECKLIST.md` | reviewer | A flat numbered list the reviewer applies to every changed file |
| `PROJECT-RULES.md` | all | Obligations lifted from your own documentation, such as what must be updated alongside a change, and the critical zones: paths where a mistake is a security or data incident; the Reviewer fixes nothing there and sends every finding back for rework |

**Shape and size.** The manifest gives every knowledge file a class and a token budget, and the generator keeps it inside that budget. A file every reader needs whole stays one file and is shortened to fit. A file a reader only needs part of becomes an index at its own path plus a sibling directory of topics — `BACKEND-ARCHITECTURE.md` next to `backend-architecture/` — so an agent reads the short index and then only the topic its task selects. The numbers live in `team-manifest.json` under `knowledge.budgets`; `checks/verify-manifest-budgets.sh` keeps them consistent with each other.

**Rule files.** A rule a person authored is not a line in those ten files, which every regeneration rewrites: a rule promoted from the learnings inbox, a critical zone you named, a finding you accepted as an exception. Each one is a file of its own under `rules/` in the knowledge directory, in the format of `templates/rule.md`, so two branches that each add a rule add two files and never conflict. Three things write them: the inbox triage of `/generate-knowledge` while the knowledge is not committed and the refresh from the remarks under `proposals/` once it is, each with consent, and `tools/extract-rules.sh`, which moves the authored lines that knowledge written before rule files existed keeps inside the generated files; `tools/migrate-knowledge.sh --first-commit` runs it on the files it moves, and `/generate-knowledge` runs it when such lines are left. Every regeneration re-checks each rule against the code and never rewrites one; a rule the code no longer bears out is removed only when you agree. The agents read them beside the generated files and cite one as `rule:<slug>`; `checks/verify-knowledge-shape.sh` checks their shape.

**Two modes.** What `/generate-knowledge` may write depends on whether the knowledge is committed in your branch.

- **Private mode**: nothing under the knowledge directory is tracked (a private copy, knowledge waiting for its first commit, or no repository at all). `/generate-knowledge` with nothing after it works out what the knowledge base needs — the first generation, restructuring after a team update, regenerating files whose claims went stale, emptying the learnings inbox — shows the list, asks once (do it, only the regenerations, nothing), backs up to `.dream-team-tracking/knowledge-backup-…/` and does it; when there is nothing to do it says so and asks nothing. Naming files regenerates only those, for example `/generate-knowledge TOOLCHAIN.md`. The team offers to run it for you when a run starts with the inbox due or on scaffold knowledge, and when a run closes with stale knowledge reported. `/generate-knowledge refresh` is refused here: the first generation is a plain `/generate-knowledge`, committed alone.
- **Committed mode**: the knowledge belongs to the whole team. `/generate-knowledge` with nothing after it writes nothing under the knowledge directory: it triages your inbox and submits its remarks to the release branch, and reports in one line which files are stale, for whoever runs the refresh. `/generate-knowledge refresh` is the one run that rewrites the knowledge, as "The shared knowledge and the branches" describes. A file name after the command is refused. A run offers only the triage of your inbox, never the refresh.

**An empty project.** When the folder holds nothing but the team and, at most, the documents a new repository starts with (a README, a licence, a `CLAUDE.md` or `AGENTS.md`), `/generate-knowledge` asks one question, whether the intended stack is decided, and writes the same ten files as scaffolds. Each starts with a banner line naming the date and saying nothing in it was verified against code. A decided stack makes its cards active as declared, so the coding standards, the review checklist and the toolchain rows come from the cards with nothing marked verified; an undecided one uses the generic card and leaves `none yet` where a command would be. The reminder outlives the moment: `/team-setup` reports scaffold knowledge, a run says so once when it starts, and once the folder has content the prompt that starts a run says the knowledge should be regenerated first. Regenerating rewrites every file, and the banner goes with it.

Two more things are written by someone else and live in the operative layer, not in the committed knowledge: the learnings inbox, in the developer's profile (see "Four layers"), and `CAPABILITIES.md`.

The learnings inbox persists across regenerations. It is an inbox of traps that have not yet earned a rule, not a log of runs. Each entry is its own file under `learnings/` in the inbox, in the format of `templates/learnings-entry.md`; no index file is kept beside them. The index a run reads is printed from the entry files (`tools/learnings-index.sh`, which `tools/inbox.sh index` runs), one row per entry with its title and tags cut to the limits in `knowledge.budgets`, so what every run reads stays inside its budget and can never disagree with the entries. After a run the reviewer classifies what it taught: a trap becomes an entry, written through `tools/inbox.sh`, and a rule or a fact the knowledge files lack becomes a mark on an entry; a run that taught nothing leaves nothing, and a defect of the team itself goes to the run's report instead. `/generate-knowledge` empties the inbox when marks are pending: with your consent and after a backup, it writes marked rules as rule files and facts into the knowledge files, and removes entries that are covered, obsolete, or never belonged there. Once the knowledge is committed it applies nothing itself: what is worth keeping is submitted as remarks for the refresh, and the rest is removed the same way. When the index is near its row cap, traps older than `knowledge.budgets.learningsTrapAgeDays` with no mark are offered for promotion into a rule as well, so the index empties instead of filling with kept traps. A run offers that refresh once when the inbox is due and records your answer; the offer is not repeated on every resume.

`CAPABILITIES.md` is written by `/team-setup` into `.dream-team-tracking/operative/claude/` and describes the machine rather than the repository: which optional capabilities are installed here and the rules for each. It is rewritten on every setup run, so never edit it by hand. See the next section.

## Optional capabilities

The team ships with none and works fully without any. A capability is an accelerator: when one is present the work is better grounded, when it is absent nothing is blocked and no report ever blames its absence for a gap.

Four are declared in the manifest, each backed by the plugins that can provide it, and each installed only if you agree to that plugin by name. A capability may list more than one: `browser-control` ships two interchangeable entries, of which you install one.

| Capability | What it adds | Who it helps |
|------------|--------------|--------------|
| `library-docs` | Current, version-specific documentation for third-party libraries, so an external call is written against today's API instead of a remembered one | Research, architecture, implementation, review |
| `session-memory` | Recall of standing preferences and what earlier sessions concluded | The orchestrator, at preflight |
| `instructions-maintenance` | A reviewed way to update the project's own instruction file when a run changes a documented rule | The orchestrator, at docs sync |
| `browser-control` | Loading the running application to see what a change actually renders, and reading the real console and network behaviour | Design, testing and review |

Two rules hold for all of them. Whatever a capability returns is evidence to check, never truth: where it disagrees with your repository or the generated knowledge, the repository wins and the disagreement is reported. And a capability never moves work between roles — research stays with research, verification stays with review.

**Consent.** `/team-setup` reports which are present and which are missing, then asks once — one multi-select naming each missing capability and what it is for, with the two browser drivers as one choice. Only what you pick is installed; when nothing is missing, nothing is asked. `/team` and the subagents never install, enable or disable anything.

**Where the wiring lives.** The concrete plugin names, marketplaces and install commands are in `team-manifest.json` under `plugins`, together with the `useWhen` and `neverUseFor` rules for each. `/team-setup` writes what it actually found into `.dream-team-tracking/operative/claude/CAPABILITIES.md`, which the team reads. That file describes the machine rather than the repository, so it is rewritten on every setup run and never hand-edited.

**How agents reach them.** A subagent runs with the tool list in its own file, which does not include tools a plugin contributes. So by default the orchestrator uses a capability itself and passes the result into the handoff. If you would rather have a role call one directly, add that capability's tools to the role's file yourself; `/team-setup` reports which roles that would apply to and never edits them.

**Replacing an entry.** Point a manifest entry at a different plugin, keep its `capability` value, and nothing else changes: the rules and the roles follow the capability, not the vendor. Two entries may share a capability as alternatives, in which case install one, not both.

## Stack cards

A card is one file per language in `templates/standards/`, with a fixed set of twelve sections: how to detect the language, its toolchain, layout, naming, errors, concurrency, testing, dependencies, security, anti-patterns, review checks and sources. Run `ls templates/standards` to see which ship today.

`/generate-knowledge` matches every card's detection rules against your repository. Several can match at once, each labelled with the directories it applies to. It then annotates each rule against what your code actually does, marking it as followed, deliberately not followed, or irrelevant. Where a card and your codebase disagree, your codebase wins and the conflict is written down.

**Adding a language.** Copy `_generic.md`, keep the twelve section headings, fill them in. No agent changes.

**The interface card.** `templates/interface/_generic.md` is the same idea for the user interface: a vocabulary every interface shares, twelve heuristics written as checks, a state matrix, a severity scale and copy rules. `/generate-knowledge` applies it to your pages to write the design language into `FRONTEND-ARCHITECTURE.md` and adds its review checks to the checklist; the Designer works from both. It names no framework; your pages supply the elements.

## Sticky team mode

A run outlives the conversation that started it. While it is open, a marker file at `.dream-team-tracking/.team-mode` records the run, its workflow and its phase. A hook on every submitted prompt reads that marker and reminds the model that the run is active and which phase it is in. After the run closes, the same marker records that it closed, with what result and how many checks are still yours, so your feedback lands in the team and not in a plain chat.

This is deliberately not a memory or an instruction that lives in context. The harness runs the hook itself, so the behaviour survives a model switch, a long pause, a compaction and a full restart.

- The marker is written when a run starts, updated at every phase change, and rewritten with `state=closed` and the result when the run closes; it is deleted by `/team stop`, when you confirm every check, or when a new run replaces it.
- After a close, the hook reports the run as closed and the orchestrator triages your message — a verification result, a defect in the delivered change, new scope, operations, something unrelated, or a review comment on the delivered code — following `skills/team/references/follow-up.md`. A defect opens a linked run whose first step is a diagnosis against the delivered change, not a new research pass. The guard sleeps while a run is only closed, so your own commit and deploy commands are not touched.
- A message starting with a slash is never captured, so every command still works normally. Leading whitespace does not change that.
- `/team stop` deletes the marker and leaves an open run parked; `/team resume` picks it up.
- A marker whose `status.md` is gone is reported as stale instead of hijacking the message; the orchestrator deletes it.
- While the pre-4.0.0 run-state directory still exists, every prompt carries a one-line notice that `/team` starts nothing until `/team-setup` has moved it. The notice comes from the hook, not from the skill, so it cannot be skipped.
- On the prompt that starts a run, the hook also says when the learnings inbox is due or the knowledge is a scaffold on a project with content, so the orchestrator offers a refresh before any research; the offer does not depend on the model counting marks in a directory its search tools skip.
- If bash is missing, the hook exits quietly. Runs still work; they just do not follow you across sessions, and the guard below denies nothing.

Wiring is one step: `hooks/settings-snippet.json` is merged into the project's `.claude/settings.json`, which `/team-setup` does without asking. A newly added hook is picked up after opening `/hooks` once or restarting the session. The command in the snippet is a plain project-relative path with no bash syntax, because VS Code Copilot reads hooks from the same file and runs them in PowerShell on Windows; `/team-setup` replaces an entry with an older spelling and reports it as rewired.

**The guard.** A second hook, `hooks/guard-command`, runs before every command the model issues through the Bash tool and denies the ones no role should run: killing processes by name or pattern (`pkill`, `killall`, `kill $(pgrep …)`, `xargs kill`, `kill -1`, `kill 0`, with any signal option or `--` before them); a recursive `rm` whose target is a glob, `/`, `~`, `$HOME`, `.`, `..`, a path above the project, or a path one level under `/` or the home directory; a force push; `git clean -f`; and `git reset --hard`, `git checkout -- <path>`, `git checkout .` (or `..`, `./<path>`) and `git restore <path>`, which discard uncommitted work. Each denial carries a one-line reason that says what to do instead. The guard acts only while a run is open, that is while the marker says `state=open`, so a developer's own session in the same project, and their commands after a run closes, are never affected. A command written verbatim in a Command cell of the knowledge `TOOLCHAIN.md`, such as a clean-build row, is exempt; the match is the whole command, never a prefix. Its limits are known and accepted: the scan is text only, so a harmless `echo pkill` is refused too; a literal home or drive path is not recognised as the home directory, so `rm -rf /c/Users/<name>` passes; and `git checkout <file>` without `--` cannot be told from a branch switch, so it passes. `/team-setup` wires the guard from the same snippet, into the `PreToolUse` array.

## Review comments and team amendments

A reviewer's comment on a pull request, or your complaint about code the team delivered, is a claim to verify, not a defect by definition. Before anything is designed, the Reviewer checks every comment and says four things: whether it holds, how severe it is, whether the scenario it describes can actually happen, and which decision produced the code. A scenario counts as reachable only when it is shown as a sequence of events with a line for each step. A comment that does not hold, a question, or a scenario nobody showed reachable is offered as "reply in the PR, no code" first. The gate shows every comment in one table, and only the comments you approve as code are designed. The draft replies cite a line for every claim, and the Reviewer checks those lines. A run that only answers closes as `ANSWERED`.

The same rule runs upstream. A risk is a fact the research shows reachable or not, never an open choice. The minimalism lens names "do nothing" when nothing needs fixing. A reviewer's "maybe X" is not a requirement. Defensive code without a shown sequence is a finding for the PlanAuditor and the Reviewer. A compile error before the fix does not count as reproducing a bug. A lesson about a risk enters the knowledge only with its sequence.

**Team amendments.** Every comment that holds is traced to its decision through the gate log, which records what was offered, what was recommended and what was chosen. If you picked an option the team did not recommend, nothing is learned. If the team recommended it, or decided it alone, that is a lesson about the team. Such lessons, and the Reviewer's `Team issues`, become team amendments. The Verifier checks each one against the run's evidence and against the role it would change, and an amendment may only add or narrow a rule. You adopt or decline each one at the close of the run. Adopted amendments live in `.dream-team-tracking/team-amendments.md` and the running team applies them through its handoffs until a team update absorbs them.

For the lead: every amendment carries a generic `Proposal` for a team file. `bash tools/collect-amendments.sh <project-dir>...` merges the collectors of several projects into one report, without writing to them. When you port a proposal into the team, or decide against it, add a row to `skills/team/amendments-resolved.tsv`. After the next update, `/team` removes the rows you resolved and the amendments the new version absorbs, and `/team-setup` reports how many are waiting for that check.

## The manifest

`team-manifest.json` is the single source of truth for what a correct install looks like. It lists the agents and commands, the required and persistent knowledge files, the template paths, the paths hidden from version control, the plugins the team expects, the hook wiring, and the neutrality check.

`/team` reads it on every invocation and refuses to start when a required knowledge file is missing. `/team-setup` validates every field. Adding a role, a command or a knowledge file means editing this file too.

**Plugins.** The `plugins` array declares the optional capabilities described above. Each entry names a capability, the plugin that provides it, its marketplace and install command, who uses it, and the rules for when it may and may not be used. `pluginPolicy` above the array states the three invariants: consent per plugin, equal quality without any of them, and brokering through the orchestrator. Add your own entries the same way.

**Model routing.** The `modelRouting` block holds the tiers, each role's floor and the workflow-by-call matrix the orchestrator picks models from; see "The roles".

**Update.** The `update` block names this repository and the clone, pull and copy commands `/team-setup` shows and runs; see "Updating the team".

## Neutrality check

The manifest carries a search pattern that must produce no output when run from the team root. It fails if any role prompt, command or this file names a language, a framework, a tool or a build command. Stack knowledge belongs in the cards and in generated knowledge, nowhere else. `/team-setup` runs this check and reports a hit as a defect in the team, not in your project.

Run it yourself before committing a change to any prompt.

## Updating the team

With a clone in place, updating is a pull — or `/team-setup`, which fetches your clone's remote and pulls when it is behind and clean:

```bash
git -C .claude pull --ff-only
```

With a copy, updating is the install again: take a fresh copy and lay it over `.claude/`.

```bash
git clone --depth 1 https://github.com/dm-23/dream-team.git /tmp/dream-team
cp -r /tmp/dream-team/. .claude/ && rm -rf .claude/.git .claude/.github /tmp/dream-team
```

`knowledge/` and any `settings.json` you have are untouched — nothing in this repository is named either, and the team's own `.gitignore` hides both settings files from the clone. Then reopen the session, so the new role and command prompts are loaded, and run `/team-setup`. It records the version it ran as in `.dream-team-tracking/.setup`, performs the steps an update needs itself (`setup.postUpdate` in the manifest), and names in one line any knowledge regeneration the new version wants: `/generate-knowledge is due (…)` while the knowledge is not committed in your branch, and, once it is, `the next refresh covers (…) — /generate-knowledge refresh, run by whoever maintains the knowledge`, a line for information that asks nothing of anyone else.

### Moving the knowledge to the shared directory (5.0.0)

Before 5.0.0 the knowledge lived inside the edition's own hidden directory (`.claude/knowledge/` or `.github/dream-team/knowledge/`), together with the learnings inbox and `CAPABILITIES.md`. After the update, `/team-setup` runs `tools/migrate-knowledge.sh` (a dry run first) as its step 1b: the inbox and `CAPABILITIES.md` move out of the edition's directory, `CAPABILITIES.md` into `.dream-team-tracking/operative/` and, since 6.0.0, the inbox on into your profile (next section), and the project files stay where they are until the project's knowledge is committed to the repository. Nothing is created under `.dream-team/` in your working tree, and setup never runs `--first-commit` or `--drop-legacy` for you. The shared layout, the lead's order for the first knowledge commit and the merge rule are described under "The shared knowledge and the branches" above. A run open in either edition stops the migration with a reason; close it with `/team stop` and run `/team-setup` again.

### The inbox in your profile, rule files and the baseline (6.0.0)

After the update, step 1b of `/team-setup` runs the same migration again: the learnings inbox moves from `.dream-team-tracking/operative/` into your profile (see "Four layers"), the entries an older `LEARNINGS.md` held inline become entry files, and the index file is dropped, backed up first; the report names the profile directory and the project key, or why the inbox stays per copy. A project whose knowledge is not committed yet then follows "The first knowledge commit", in which `--first-commit` also extracts the authored rules into `rules/`, `/generate-knowledge` writes a `Covers:` line on every file it regenerates (`BASELINE` only when it regenerated every required file), and the first `/generate-knowledge refresh` after the knowledge commit writes the remaining `Covers:` lines and `BASELINE` in a knowledge-only commit of its own. A project that committed its knowledge under 5.x gets the rule files, the `Covers:` lines and the baseline from its first refresh: `/team-setup` says so in its informational `Knowledge: the next refresh covers (…)` line, and whoever maintains the knowledge runs `/generate-knowledge refresh` once on each open release branch. Until then the drift line of every run says the baseline is missing, and, because the team reads the release branch from `BASELINE`, a run's closing offer only triages the inbox and submits nothing; `/generate-knowledge Branch: <release branch>` submits remarks meanwhile. From the first refresh on, remarks from a run are submitted as described in "The shared knowledge and the branches".

A copy adds and overwrites; it never deletes. If you are coming from a layout that kept the team in a subdirectory such as `.claude/team/`, delete that directory after copying — nothing reads it any more.

Existing knowledge files stay valid unless the manifest gained a required file, in which case the check tells you to regenerate. A `PROJECT-RULES.md` written before 4.3.0 has no critical zones section: runs still work, the Reviewer notes the missing section in its report, and `/generate-knowledge PROJECT-RULES.md` adds it. A `FRONTEND-ARCHITECTURE.md` written before 4.4.0 has no design-language topic: the Designer works from the layout and says so, and `/generate-knowledge FRONTEND-ARCHITECTURE.md REVIEW-CHECKLIST.md` adds it together with its review checks. When an update changes the shape the knowledge files are written in, `/generate-knowledge` brings an existing knowledge base over to it without re-reading your code, as its shape work. A file without the scaffold banner on its first line is never a scaffold, so knowledge written before 4.4.1 is unaffected by the empty-project behaviour.

### Moving run state from the legacy directory

Before 4.0.0 the Claude Code edition kept its run state in the legacy `.claude-tracking/`; the Copilot edition already used `.dream-team-tracking/`. Now it is `.dream-team-tracking/`, shared by the Claude Code and Copilot editions, so a run started in one agent can be resumed in the other — never work on one open run from both at once. After updating, `/team` starts nothing until the legacy state is moved:

1. If a run is open, `/team stop` in the session that runs it.
2. `/team-setup`: it runs a dry run of `tools/migrate-tracking.sh` and, when the dry run is clean, moves the state; a dry run that refuses is reported with its reason. Paths inside the moved files and in your knowledge files are rewritten (the knowledge is backed up first); files of your project that still name the legacy directory are listed for you to edit, never changed.
3. Commit the `.gitignore` change, if `/team-setup` made one, before `/team resume`: the resumed run's baseline predates it, so an uncommitted change would show up in the run's review diff. Then `/team resume` continues a parked run.

If both directories hold the same name (typically `.service-consent` or `.update-check` in a project that used both editions), the migration refuses and lists them: keep one of each, then run `/team-setup` again.

## GitHub Copilot

The same team runs in GitHub Copilot, in VS Code agent mode and in the Copilot CLI, from one set of installed files. It is not a second copy to maintain. `copilot/install.sh` translates this repository's files when it installs them, and fails, naming the place, when a change here can no longer be translated.

### Install and update

From the project root, in bash (Git Bash on Windows):

```bash
rm -rf /tmp/dream-team && git clone --depth 1 https://github.com/dm-23/dream-team.git /tmp/dream-team && bash /tmp/dream-team/copilot/install.sh . && rm -rf /tmp/dream-team
```

Updating is the same command. `--dry-run` prints what would change and writes nothing.

Then:
1. Reopen VS Code, or restart the CLI.
2. In VS Code, turn on the `chat.useHooks` setting.
3. Run `/team-setup`.
4. Run `/generate-knowledge` if the project has no knowledge yet.

### What it writes, and what it never touches

| Path | Contents |
|------|----------|
| `.github/agents/<role>.agent.md` | The twelve roles, hidden from the agent picker and called as subagents |
| `.github/skills/<command>/SKILL.md` | `/team`, `/generate-knowledge`, `/team-setup` |
| `.github/hooks/dream-team.json` | The session-start hook and the guard |
| `.github/dream-team/` | Manifest, templates, clients, runtime checks, and `.installed`, the list of what was installed |

**What it touches.** The installer replaces only the files it installed itself, and only if nobody has edited them since. It never writes, moves or deletes:
- `.dream-team/knowledge/` (the shared project knowledge, its `rules/`, `proposals/` and `BASELINE` included), `.github/dream-team/knowledge/` (the private copy) and `.dream-team-tracking/operative/` (`CAPABILITIES.md`, and the learnings inbox when it stays per copy);
- the learnings inbox in your profile, `~/.dream-team/<project key>/`;
- `.dream-team-tracking/` (runs, the marker, consent records);
- `.git/`;
- the project's settings;
- any other file.

**When it stops.** A file of the project's own at one of the installer's paths stops the install, with a list. So does a team file edited by hand, unless you pass `--force`. With `--force`, the edited file is first copied to `.dream-team-tracking/install-backup-<time>/`.

**Removed files.** A file that a newer version no longer ships is deleted, unless it was edited.

The Copilot edition reads the same shared knowledge in `.dream-team/knowledge/` as a Claude Code install, keeps its own `CAPABILITIES.md` in `.dream-team-tracking/operative/copilot/`, fills the same learnings inbox in your profile, and shares run state with a Claude Code install in `.dream-team-tracking/`: a run started in one agent can be resumed in the other, but never work on one open run from both at once. VS Code may also pick up a Claude Code install's commands and roles from `.claude/`, so a project with both installs can show duplicate `/team`, `/team-setup` and `/generate-knowledge` commands and roles. Until that is checked, keep one edition per project (or one per editor).

### What differs from Claude Code

1. **Models.** Every subagent runs on the session model. VS Code and the CLI name models differently, so the tier table in `modelRouting` is not carried over.
2. **Open runs.** An open run is announced when a session starts, not on every message: Copilot lets no hook add context per prompt. After a compaction, use `/team resume`.
3. **Capabilities.** `/team-setup` installs nothing. Optional capabilities are MCP servers; it reports which are missing and gives the VS Code and CLI steps to add each. The session-memory and instruction-file capabilities exist only as Claude Code plugins and are not offered.
4. **Hooks in VS Code.** They run only while `chat.useHooks` is on, a preview feature.
5. **The guard.** It is installed with the team in `.github/hooks/dream-team.json`; `/team-setup` has nothing to wire. It reads bash command lines, so a PowerShell command, which is what the CLI runs on Windows, such as `Remove-Item -Recurse`, is not recognised.

### Maintaining the port

`bash copilot/check.sh` builds the edition from fixtures and from this repository, then installs it into throwaway projects. It prints one `ok [case]` line per case and takes about thirty minutes on Windows with Git Bash, because each case spawns many processes; run `bash copilot/build.sh <empty-dir>` after every prompt change (under a minute, and it fails on a broken anchor or rule) and the full check before a release.

The repository's own CI (`.github/workflows/check.yml`) runs the neutrality grep, every `checks/verify-*.sh` that takes no arguments (the frontmatter parse among them) and `copilot/build.sh` on each pull request and each push to `main`; `copilot/check.sh` stays a manual step before a release.

The translation is data:

- `copilot/rules.tsv`: literal replacements, as `file-glob<TAB>from<TAB>to`, applied in order. A rule that matches nothing fails the build.
- `copilot/overrides/`: whole blocks replaced. A block is a section under a heading, a list item or a paragraph of a Markdown file, or a top-level key of the manifest. The first line of each overlay is its anchor, exactly as it appears in the source.
- `copilot/allow.tsv`: the only Claude Code terms allowed to survive, by file and exact string.
- `copilot/files/`: files that exist only in the Copilot edition.

### Verified by hand

The documentation does not settle two behaviours: whether the hook's combined output is accepted, and whether the roles stay out of the agent picker. These, and the other rows below, must be checked once in each product before you rely on them. The table records the result of each check.

| Check | VS Code | Copilot CLI |
|-------|---------|-------------|
| The twelve roles are callable as subagents | not yet checked | not yet checked |
| The roles are absent from the agent picker | not yet checked | not yet checked |
| `/team <task>` receives the task text | not yet checked | not yet checked |
| Gates appear as questions with options | not yet checked | not yet checked |
| Three Brainstorm calls run in parallel | not yet checked | not yet checked |
| With an open run, a new session receives the `TEAM-MODE-ACTIVE` text | not yet checked | not yet checked |
| With a closed run (`state=closed` marker), a new session receives the `TEAM-MODE-CLOSED` text | not yet checked | not yet checked |
| With an open run, `git push --force` is denied with the guard's reason | not yet checked | not yet checked |
| Side by side with a Claude install: one `/team` and the Copilot roles only | not yet checked | not yet checked |
| The learnings inbox in the profile, under default permissions: the Copilot CLI without `--allow-all-paths` or `--add-dir`, VS Code agent mode with default approvals and `chat.useHooks` on, each in a project with the same remote address as the Claude Code install, so the inbox is the same one. A `/team` run reads and writes the inbox through `inbox.sh` with no path refusal and no approval prompt. On a refusal, record its exact message here; the per-copy fallback for that edition is then the lead's call | not yet checked | not yet checked |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| An update to the team changed nothing, a role or command behaves like the previous version | The session still holds the prompts it loaded at startup | Reopen the session |
| `/team` refuses to start | A required knowledge file is missing | `/generate-knowledge` |
| Sticky mode does nothing | Hook not wired, or no bash | `/team-setup` wires it and says whether bash was found; open `/hooks` once after wiring |
| An unrelated request is pulled into a run | A marker of an open run that never closed, or a closed run's marker you want gone | `/team stop`; a closed run's marker answers unrelated questions normally and only triages messages about the run |
| A command is not offered | The team's contents are not in `.claude/` itself, but one level down in a subdirectory | Move them up so `.claude/skills/team/SKILL.md` is a real path, then reopen the session |
| The reviewer reports a missing tool | A command in `TOOLCHAIN.md` is not installed here | Install it, or accept the gap; it is reported, never faked |
| Generated files appear in version control | The exclude lines were not added | `/team-setup` |
| `/team` says the run state is still in the legacy directory | Updated to 4.0.0, state not moved yet | `/team stop` if a run is open, then `/team-setup` |
| Sticky mode stopped after updating to 4.0.0 | The open run's marker is in the legacy directory, which the hook no longer reads | `/team stop`, `/team-setup`, `/team resume` |
| An old run is listed as open on every preflight | Its `status.md` was closed by an earlier version with `[DONE]` later in the first line, `**[DONE — date]**` or `Complete —` | Nothing: 4.5.0 reads `[DONE` or `Complete —` anywhere in that line as closed |
| `/team` starts but behaves like an older version, or says a workflow file is missing | `skills/team/references/` was not copied, or the session still holds the old prompts | `/team-setup` pulls a clone in place or shows the copy command; then reopen the session |
| The Reviewer reports "Critical zones: section missing" | `PROJECT-RULES.md` predates 4.3.0 | `/generate-knowledge PROJECT-RULES.md` |
| The Designer reports `Design language: topic missing` | `FRONTEND-ARCHITECTURE.md` predates 4.4.0 | `/generate-knowledge FRONTEND-ARCHITECTURE.md REVIEW-CHECKLIST.md` |
| `/team-setup` or a run reports scaffold knowledge | The knowledge was written on an empty project and the project now has content | `/generate-knowledge` |
| A review run stops and says a ref is not in the local repository | The team never reads from a git remote, so a base or head it cannot resolve locally stops the run | Bring the ref into the local repository yourself, then write the next message; the run continues from there |
| A command the Reviewer needs is denied by the guard | It is destructive and not listed in `TOOLCHAIN.md` | Add the exact command as a `TOOLCHAIN.md` row, or run it yourself |
| `/generate-knowledge` refuses a file name: the knowledge is committed | Once the knowledge is committed, only the refresh regenerates files | Leave it to whoever maintains the knowledge: `/generate-knowledge refresh` on the release branch |
| A refresh pull request conflicts on `BASELINE` | Another refresh of the same branch was merged first | Close it, bring the release branch up to date and run `/generate-knowledge refresh` again |
| The closing question offers only to triage the inbox, and nothing is submitted | No `BASELINE` names the release branch yet | `/generate-knowledge Branch: <release branch>` |
| A destructive command is not denied during a run | The guard is not wired (a team updated from before 4.3.0), or no bash | `/team-setup` wires the guard and reports `bash: absent` when there is no bash; open `/hooks` once after wiring |
