---
name: generate-knowledge
description: Use when the user asks to generate, refresh, check or repair the Dream Team knowledge base for this repository, or when the orchestrator runs it after a run offered a refresh. With no arguments it works out what the knowledge base needs — first generation, restructuring, regenerating stale files, triaging the learnings inbox — asks one question and does it. Produces project documentation AND coding standards/toolchain/review-checklist files in the project knowledge directory, and keeps the learnings inbox in the operative directory. Never auto-invoke.
argument-hint: "[FILE-NAME.md ...]"
disable-model-invocation: true
user-invocable: true
---

You are the Knowledge Generator. The Dream Team agents (`.claude/agents/*.md`) contain zero knowledge about any technology. Everything they know about this project — stack, conventions, commands, rules — comes from the knowledge dir, and what runs learned waits in the learnings inbox in the operative dir. You produce those files from actual exploration. The agents follow them literally, so every line must be verified against this repository.

## What this run does

Both directories come from `bash .claude/{knowledge.resolver}`, run from the project root: `project` prints the knowledge dir, `operative` the operative dir, and every path below that names neither is project-root-relative.

Arguments: `$ARGUMENTS` — file names only, as an override: those files are regenerated and nothing else is decided for you — no staleness check on other files, no shape gate, no triage; the question lists only `N files to regenerate: <names>`. An Agent-run instance may also carry `Consent: given` (see "Consent"). Otherwise this run decides. In this order, each test adds work to one list:

1. **Generation.** Run `checks.knowledgeScaffold` as `checks.knowledgeScaffoldRunFrom` spells out. A first line `project: empty`, whatever the exit code → "Empty project" replaces everything below, stack question included. Otherwise: no knowledge dir, a `knowledge.required` file missing, or exit 1 (scaffold knowledge on a project that has content) → regenerate every required file. Otherwise run the staleness check ("Staleness") on every existing file: a file with a `STALE` line, or named by an unresolved `[STALE-CHECK]` mark, is regenerated.
2. **Shape.** For every file not already in the generation list, the shape gate ("Shape work"): a `subset` file with no topic directory, `LEARNINGS.md` with entry bodies inline, a file over its budget, an index header the template no longer has → the moves and rewrites that bring it to shape.
3. **Inbox.** `checks.learningsInbox` exits 1, or any entry classifies as `rule`, `fact`, `summary`, `team`, `obsolete` or `covered`, or `review-exceptions.md` in the operative dir holds an entry ("Triage the learnings inbox") → the triage.

An empty list is reported as `nothing to do` and the run ends without a question.

## Consent

Every branch backs up first, so one question covers all of it. One AskUserQuestion, in the language of the request, whose text is the work list with counts: `N files to regenerate: …`, `S files to restructure: …`, `M rules to promote into …`, `F facts to fold into …`, `R entries to remove (…)`, `T traps to shorten`, `A aged traps to promote into … (kept unless Do it)`, `E accepted exceptions to share in REVIEW-CHECKLIST.md (S stale dropped)`, `backup to .dream-team-tracking/knowledge-backup-{YYYY-MM-DD-HHmm}/`. Options, exactly three: **Do it** (everything listed), **Only the regenerations** (the generation and shape lists; the inbox is left as it is), **Nothing** (the list was the report). A run started with `Consent: given` in its arguments skips the question and does everything listed. The empty-project stack question is a different question and the only one that run asks.

Output language: the language of the user's request; file contents in English (agents read them).

## Inputs (read all before writing)

1. `.claude/team-manifest.json` — the required file list and template locations. `knowledge.learningsEntryTemplate` is the entry format; `knowledge.persistentTemplates` the index.
2. Repository manifests and build files (whatever exists): dependency manifests, lock files, task runners, container files, CI/CD pipeline definitions, editor/format configuration.
3. Human documentation: root `CLAUDE.md`, `README*`, `.claude/PROJECT.md`,
   `.claude/docs/*.md`, `CONTRIBUTING*`, `docs/`. The team's own documents are not
   project documentation: skip anything under `.claude/docs/superpowers/`, which
   belongs to the team that was deployed here and says nothing about this project.
4. Actual source: entry points, 3–5 real files per layer, 3–5 real test files.
5. `LEARNINGS.md` in the operative dir and every entry file in its `learnings/` → all `[PROMOTE]` and `[STALE-CHECK]` lines not yet marked resolved; when the inbox is in the work list, every entry (see "Triage the learnings inbox"). From all of the knowledge dir, searched recursively with topic directories included, the items ending `— source: learnings …` (see "Items promoted from learnings").
6. Stack cards: every file in `.claude/templates/standards/` except `_generic.md`.
7. The interface card, `.claude/templates/interface/_generic.md`, read when FRONTEND-ARCHITECTURE.md will describe an interface: its `## Vocabulary` is what the design language maps, its `## Review checks` what REVIEW-CHECKLIST.md gains.

## Stack detection

For each stack card, evaluate its `## Detect` section against the repository (search for the listed files). Every card that matches is "active". If none matches, use `_generic.md`. A repository may have several active cards (for example a back end in one language, a user interface in another, scripts in a third) — include all, each labelled with the directories where it applies. Record the result in `PROJECT-OVERVIEW.md → Stack`.

## Empty project

A developer who starts a project from nothing deploys the team into an empty folder, and the knowledge has to exist before the first `/team` run can write the first code. Step 1 of "Process" runs `checks.knowledgeScaffold` as `checks.knowledgeScaffoldRunFrom` spells out; when its first line is `project: empty`, this section replaces steps 2–8. It applies whatever the arguments. The script's definition is the only one: a folder whose top-level entries are all dot-prefixed, or root documents a developer has before any code (a file named `README*`, `LICENSE*`, `CLAUDE.md` or `AGENTS.md`), is empty; any other entry, a file or a directory even when that directory is empty, is content, whatever the stack cards detect. Those root documents are Inputs 3 and are read as "Human documentation in an empty project" says.

**Say what will happen.** One short message before anything else: the folder holds no project content, so this run writes scaffolds, every file marked on its first line, to be regenerated once the code exists.

**Ask once.** One AskUserQuestion call. The options are the file names of the stack cards in `.claude/templates/standards/` except `_generic.md`, read from the directory at run time and never written out here, multi-select, at most four options per question and as many questions in the one call as the cards need; the last question also carries the option "Not decided yet", which counts toward its four. A developer may pick several cards, as a real project may have several active ones. When human documentation under a dot path names a stack (see below), quote it in the question's text; the answer still decides. A stack typed as free text that matches no card is recorded as the declared stack text in `PROJECT-OVERVIEW.md` and counts as "not decided" for the cards. Nothing selected is "not decided". There is no second question: an empty project has no learnings inbox to triage, so the triage step reports that and does nothing.

**Active cards.** The named cards are active as *declared*: their rules apply because the developer said so, and nothing in the code confirms or contradicts them yet. "Not decided" makes `_generic.md` the one active card.

**Human documentation in an empty project.** Inputs 3 are read wherever they exist: the root documents the definition admits, and dot paths such as `.claude/PROJECT.md`, `.claude/docs/*.md` and their equivalents in another edition. What they say lands where it would for a real project — the Documentation map of `PROJECT-OVERVIEW.md` lists them, and the obligations, prohibitions and documents to keep in sync of `PROJECT-RULES.md` are extracted from them with their sources cited, exactly as step 5 (PROJECT-RULES.md) and step 7 of "Process" extract them. This is the one place a scaffold holds sourced content, and only when such a document exists.

**The banner.** The first line of every scaffold file, byte for byte except the date:

```
> SCAFFOLD — written on an empty project on YYYY-MM-DD; nothing here is verified against code. Run /generate-knowledge when the code exists.
```

The banner is the whole marker: `checks.knowledgeScaffold` reads it from the knowledge files — one bannered file makes the base a scaffold, so a run that regenerated a single file leaves the reminder in place — and `/team`, `/team-setup` and the prompt hook read it through that script. A file regenerated from code loses it because the file is rewritten; a scaffold file a run naming other files leaves alone keeps it, which is right, since that file is still a scaffold.

**What each file holds.** The same section skeleton "Files to generate" gives, the banner first; a section that needs code to fill it holds the one line `not yet known — empty project`, never an invented path, command or entity.

- `PROJECT-OVERVIEW.md`: the Stack table with one row per declared card, Directories `none yet`, plus the declared stack text when it matched no card; or one row `not decided`. Core Domains, Tenancy and Key Technical Facts are one line each. The Documentation map lists the human documents found under dot paths, or says none exist.
- The `subset` files — `BACKEND-ARCHITECTURE.md`, `FRONTEND-ARCHITECTURE.md`, `DI-AND-STARTUP.md`, `CODING-STANDARDS.md`: the index file carries the banner, the orienting line, and one line per section the real file would have, each `not yet known`. The sibling topic directory is created empty, so the shape gate finds the shape it expects. `FRONTEND-ARCHITECTURE.md` names no `design-language` topic; the Designer reports `Design language: topic missing` and continues, which is the right behaviour here.
- `CODING-STANDARDS.md` is the one `subset` scaffold whose topic directory is not empty: the active cards' rules are copied as the real file copies them, one topic per card, every bullet annotated `[declared]` — a fourth annotation beside `[observed]`, `[not followed]` and `[n/a]`, meaning "follow the card as written; nothing in the code confirms or contradicts it yet". The index names every topic and carries that meaning as one line, `Annotations: [declared] — the card's rule applies because the developer named the stack; nothing in the code confirms or contradicts it yet`, so the file explains itself to the Developer and the Reviewer.
- `TOOLCHAIN.md`: with declared cards, one row per row of each card's `## Toolchain`, `Verified: no`, `Source: card (declared stack)`, `Cost: unknown`; with no card, the Purpose column with `none yet` in every Command cell. No `## Operations`, and no `Line endings (check)` row: there is no working copy to measure. `## Verification log` says nothing was run. The header, which already instructs agents, gains one sentence: `A row whose Command is \`none yet\` is not a command; the Reviewer reports the toolchain n/a for it and never counts it as failed.`
- `TESTING-CONVENTIONS.md`: the declared cards' `## Testing` bullets, each marked `[declared]`, or the one line.
- `SEARCH-PLAYBOOK.md`: topology `none yet`, no recipes, and the anti-assumptions that do not depend on code.
- `REVIEW-CHECKLIST.md`: the active cards' `## Review checks`, rewritten only as far as a scaffold allows (no repository paths exist yet), plus item N. The Reviewer applies them to the first code as it applies any checklist.
- `PROJECT-RULES.md`: `Sources: none — empty project` unless a dot-path document was read; every section one line; `## Critical zones`, `## Generated files` and `## Hot files` each hold `- none found — source: empty project`. In `REVIEW-CHECKLIST.md`, `## Change types` holds the same line and `## Accepted exceptions` holds `- none`.
- `LEARNINGS.md` and `learnings/` in the operative dir exactly as for a real project: created from the persistent template when missing, never a scaffold, never bannered.

**Report.** Files written, the declared cards or "not decided", one sentence that `/generate-knowledge` is due once the code exists, the size table, and the neutrality output and first-commit line step 8 of "Process" gives.

**Regenerating with code present.** The normal path, nothing special: every file is rewritten from the repository and the banner disappears with it. A `[declared]` item carries over only when the code confirms it, and then as `[observed]`; items ending `— source: learnings …` follow their own rule. There is no "merge the scaffold" step.

## File shape and budgets

`team-manifest.json → knowledge.classification` gives each file a class, and
`knowledge.budgets` gives the sizes. Read both; never hardcode a number here.
Measure by characters at four to the token — no tokenizer is available.

**A `subset` file** becomes an index at its own path plus a sibling directory of
topics. The directory's name is the file's own base name (without `.md`), lower-cased,
with hyphens preserved — `BACKEND-ARCHITECTURE.md` becomes `backend-architecture/`.
This is the exact and only transform; do not abbreviate, reorder, or otherwise alter
the name. The index holds one descriptive line per topic and the short orienting
material every reader needs, inside `indexTokens`. Each topic file stays inside
`topicTokens`; a topic over budget is split again into additional flat sibling files
inside the same topic directory, never a nested subdirectory — the integrity check
that verifies shape work only scans a topic directory one level deep, so anything
nested there would be invisible to it and reported as lost content.

When a topic is split that way, the index names every file the split produced, each
on its own line under the same selecting condition. A file no index line names is
content that exists on disk, survives the integrity check, and no reader can reach:
nothing lost and nothing findable are different guarantees, and only the index
delivers the second one.

Topic boundaries are the file's own top-level (`##`) sections — one section, one
topic — with adjacent sections merged when a topic would fall under roughly 300
tokens. Do not invent a structure the content does not already have.

Longer material that *every* reader needs does not fit the index and does not
become optional because of it. It becomes a topic the index marks **required**.
Every other topic line states the condition that selects it, so a reader chooses
by matching its task, not by guessing.

**A `whole` file** stays one file inside `wholeFileTokens`, or its own entry in
`budgets.overrides`. Over budget it is cut, never split — splitting would
contradict its class. The cuts that work:

- Drop `[n/a]` items instead of listing them with the evidence that made them so.
- One example path per pattern, not three.
- Do not restate what another knowledge file says; link to it.
- Record a decision once, without the search that produced it.

## Files to generate (all in the knowledge dir unless a section says otherwise)

### PROJECT-OVERVIEW.md

```markdown
# [Project] — Project Overview
[1–2 sentences]

## Stack
| Area | Language / runtime | Frameworks & key libraries | Directories | Standards card |

## Core Domains
| Domain | Key entities | Modules |

## Tenancy / Auth Model

## Key Technical Facts
- build cost (measured or from CI), deployment target, single or multiple repositories, generated code, etc.; counts in the measured form

## Documentation map
- which human documents exist and which are authoritative (from Inputs 3), with known discrepancies
```

### BACKEND-ARCHITECTURE.md

```markdown
# Backend Architecture

## Layout (tree with one-line descriptions)

## Entry / Routing layer — location, conventions, response shape, auth mechanism

## Business logic layer — location, pattern, naming

## Data access layer — technology, query style, entity naming, migrations (tooling and location)

## Key dependencies (name, version, purpose)

## Anti-patterns (what this project deliberately does NOT use — and what it uses instead)

## Async / concurrency conventions

## Error handling conventions

## Duplicated code paths that must change together (if any)
```

### FRONTEND-ARCHITECTURE.md

Same depth: root layout, stack table, state management, API call layer (the exact wrapper functions to use), component/page structure, navigation, styling, forms, module loading rules, key dependencies. If there is no user interface, say so in one paragraph and stop.

When there is an interface, also a `## Design language` section, built from the interface card's `## Vocabulary` applied to the real pages: one line per vocabulary term → the project's element and its `path:line` (`no equivalent` when the project has none); how the project renders each state of the card's `## States` (empty, loading, error, partial, success, no permission), one example path each or `not rendered`; the interface language, and the copy conventions observed (button verbs, the shape of error text, confirmation wording); the feedback and confirmation patterns with their paths; and `### Inconsistencies observed` — the same element done two ways, both paths, or `none found`. As a `subset` file this section becomes the topic `frontend-architecture/design-language.md`, named in the index with the condition `Read for every task the Designer runs on, and when adding a state, a message or an action a person sees`.

### DI-AND-STARTUP.md

Startup sequence, wiring/registration pattern and location, configuration sources and access pattern, request pipeline/middleware, background processing.

### TESTING-CONVENTIONS.md

Frameworks per layer (framework, assertion style, mocking approach), test layout, one real example per pattern (unit, entry-point/handler, external-service fake, user interface if any), naming, location rules, what is NOT covered and whether that is deliberate.

### SEARCH-PLAYBOOK.md

Repository topology (entry points, API surface, logic, data, user interface, tests — exact paths), 6-step discovery strategy adapted to this repo, query recipes (verified search patterns), batching guidance, anti-assumptions. Run every recipe once and keep only the ones that return results.

### TOOLCHAIN.md

```markdown
# Toolchain
All commands run from: `<directory>`. Agents may run ONLY commands listed here; a row under `## Operations` runs only as its `Runs as` column says.
`<scratch>` in a command stands for the temporary directory your environment gives you; substitute it, and never a fixed system path.

| Purpose | Command | Verified | Source | Cost |
|---------|---------|----------|--------|------|
| Format (check) | ... | yes/no | CI file / README / card / derived here | cheap/expensive |
| Format (apply) | ... (the form that takes the file paths to format, when the tool has one; the Developer and the Tester format only their own files) |
| Lint | ... |
| Build | ... (when the cost differs by project, the Cost cell names the cheap projects; the Developer builds only those) |
| Test all | ... |
| Test one | ... |
| Additional test runners | ... (for example a separate user-interface test command) |
| Validate `<document>` | ... (one row per document; see below) |
| Run | ... |
| Install missing | ... |
| Line endings (check) | `git ls-files --eol -c -o --exclude-standard -- <paths>` | yes | derived here | cheap |

## Operations
(only when the repository has deploy, rollback or remote-inspection scripts or documented commands; otherwise omit the section)

| Purpose | Command | Runs as | Read-only | Source |
|---------|---------|---------|-----------|--------|
| Deploy | ... | user | no | script path / README |
| Rollback | ... | user | no | ... |
| Service status | ... | orchestrator with per-command approval | yes | ... |

## Verification log
- command — how verified (executed / found in CI at path / from card, not executed)
```

Procedure: take candidates from CI/pipeline files first, then task runners/README, then the active stack card's `## Toolchain`. Execute the cheap read-only ones (format check, lint, build, test) if the user has not forbidden it; mark `Verified: yes` only after a real run. Mark "Cost: cheap" only when measured under about one minute.

Tools missing on this machine are written to `knowledge.toolchainMissingFile`, one line each, `- <tool> — <install command>`. A run that measured them rewrites the file whole, and writes it even when nothing is missing, as the one line `none`; the lines the orchestrator appended when a command failed for an absent tool are replaced by the new measurement. While the directory `tracking.legacyDir` exists, nothing is written there: run state is still in the legacy directory. Nothing about this machine goes into `TOOLCHAIN.md`.

**Where a command may write.** Only to the repository paths its purpose names, and to standard output. Feed a tool its input through a pipe or standard input instead of staging a copy. When a tool can only write a file, the command writes it under `<scratch>`. Never name a fixed temporary path such as `/tmp/...`, `%TEMP%` or `$TMP`: it is shared between runs, it means different things in different shells, and the agent's environment may forbid writing there.

**Line endings.** When the working copy keeps CRLF — `git config core.autocrlf` prints `true`, or `.gitattributes` sets `eol=crlf`, or `git ls-files --eol | grep -c 'w/crlf'` is above zero — the `Line endings (check)` row is required and its command is `git ls-files --eol -c -o --exclude-standard -- <paths>`, read as `i/<index> w/<working tree>` per file. A path that prints no line is reported `not checked`. It is the only line-ending check agents may claim: counting carriage returns with a text tool misreports on this platform, and the row exists so nobody improvises one. Without CRLF in the working copy, omit the row.

**Operations.** Commands that deploy, roll back, restart or inspect a running system are never run by this generator and never marked verified. List them from the repository's own scripts and documents, each with who runs it: `user` for anything that writes to a remote or production system, `orchestrator with per-command approval` for a read-only inspection the team may perform during a run. The `Read-only` column is a promise the ResearcherExplorer relies on; when in doubt, `no`.

**Validate rows.** Every document the team edits by hand that has a machine-readable format (a specification, a schema, a configuration file) gets a `Validate` row. `PROJECT-RULES.md → Documents to keep in sync` lists these documents. Without a listed command, an agent either skips the check or improvises one, and both break the rule that agents run only what this file lists. Take the command from the repository's own tooling or CI first. Otherwise build it from a parser already present on this machine (a runtime's standard library, or a library already in the dependency cache, never a new download), run it on the current file, and record it as `derived here`. If nothing here can parse the format, write the row as `none — the Reviewer checks it by reading`. That way the absence is a recorded decision, not a gap. PROJECT-RULES.md is written after this file, so step 7 of "Process" confirms that every such document has its row.

### CODING-STANDARDS.md

```markdown
# Coding Standards

## Active standards cards
- card — applies to directories

## Layout / Naming / Errors / Concurrency / Testing / Dependencies / Security / Anti-patterns
(one subsection per active card, copied from the card and then ANNOTATED: for each bullet mark
 `[observed]` — the repo follows it (cite an example path),
 `[not followed]` — the repo consistently does otherwise (describe what it does instead — the project convention WINS, agents must follow the repo),
 `[n/a]` — does not apply here.)

## Project conventions not covered by the cards
- convention — example path (things the repo does that no card mentions)

## Conflicts
- card rule vs project convention — resolution: follow project (or: user decision needed)
```

### REVIEW-CHECKLIST.md

```markdown
# Review Checklist (generated — the Reviewer applies every item to every changed file)
1. ... (from each active card's `## Review checks`, minus items marked [n/a] in CODING-STANDARDS.md, rewritten with this repo's exact commands/paths)
M. ... (from PROJECT-RULES.md obligations, one item each)
K. ... (from BACKEND/FRONTEND-ARCHITECTURE.md conventions that a reviewer can verify mechanically)
L. ... (from "Duplicated code paths that must change together")
I. ... (from `.claude/templates/interface/_generic.md → ## Review checks`, only when FRONTEND-ARCHITECTURE.md has `## Design language`, each rewritten with this repo's element and path from that section)
N. If any changed file is under a path of PROJECT-RULES.md → Critical zones, review in critical-zone mode (the Reviewer's Step 0).
G. A changed file under a path of PROJECT-RULES.md → Generated files is not read line by line; it gets the check that section names for it, and it changes only together with the source it is generated from.

## Change types
### <type, e.g. "a new endpoint">
- Trigger: <what in a diff makes it this type: a path pattern, a kind of file added, a registration>
- Exemplar: <one existing file that shows every point done right>
- Points: <point 1>; <point 2>; … (each one a thing a reader can find in the diff or its neighbours)
(or the single line `- none found — source: <what was searched>`)

## Accepted exceptions
- <path> · "<cited line>" · <rule> — accepted YYYY-MM-DD: "<words>" (<run> F-<n>)
(or the single line `- none`)
```

The numbered list is flat, with no headings inside it, each item verifiable by reading the diff or running a TOOLCHAIN command. The two sections after it are not items: the Reviewer applies the numbered list only, and the change-reviewer reads the sections.

**Change types.** The stereotyped changes of this project: the kinds of change that recur and that each need the same handful of things done (a new endpoint, a schema change, a new setting or switch, a new background operation, a new screen). Derived from the code only: a type is written when at least three existing instances show the same points, and its exemplar is one of them. At most six types, at most eight points each, every point phrased so that it is either present in a diff or not. A point no instance shows is not a point; a project with no such pattern gets the `- none found` line. Never a point taken from a stack card that the code does not bear out.

**Accepted exceptions.** Findings a developer consciously declined, which a review must not raise again. They are never derived: each one is an entry moved here from the inbox `review-exceptions.md` in the operative dir, under consent ("Triage the learnings inbox"), or carried over from the existing file. On every regeneration, read the existing section first and keep each entry verbatim whose cited line is still in the file it names (`grep -F`); an entry whose line is gone is stale: listed in the report and removed, since changed code is judged again.

An item that can be confirmed only once a commit exists — a commit-message form, a pre-commit hook's result, a pull-request target — ends with the suffix `(after commit)`. The Reviewer reports such items separately and never counts them as unverified; without the suffix, every run reports them unverified forever.

### PROJECT-RULES.md

```markdown
# Project Rules
Sources: CLAUDE.md, README, CI, .claude/PROJECT.md, .claude/docs (cite each)

## Obligations (when X changes, Y must be updated)
- for example "new API route → update the API specification file at <path>" — source: <file:line>

## Prohibitions
- for example "never hard-delete records in <tables>; use the active flag" — source

## Verification before reporting done
- commands/gates the project requires (reference TOOLCHAIN rows)

## Documents to keep in sync
- path — what it tracks — who updates it (team run: yes/no)

## Critical zones
- <path or glob> — <auth | permissions | money | personal data | data migration | secrets and deploy config | CI> — source: <file:line, or "user">
(or, when nothing qualifies, the single line `- none found — source: <what was searched>`)

## Generated files
- <path pattern git accepts> — <dependency lock | schema snapshot | built output | generated client | other> — check: <how a reader tells the file is whole and in step with its source>
(or the single line `- none found — source: <what was searched>`)

## Hot files
- <path> — <N> commits (measured at <short-sha> with <command>)
(or the single line `- none found — source: <no history | fewer than twenty commits>`)
```

Extract only rules that are actually written in the sources; do not invent. The exceptions are items promoted from learnings and the Critical zones, Generated files and Hot files sections, derived from the code as described below — see "Items promoted from learnings".

**Generated files.** Tracked files a tool writes and nobody reads line by line: dependency lock files, schema snapshots and their designer companions, built or minified output, generated clients. Found from the repository only: the lock files of the dependency manifests read as input 2, files whose header says they are generated, output directories a build definition names and git tracks. Each line's `check:` is what this project's tooling and the file's own format allow, in this order of preference: a `TOOLCHAIN.md` row that verifies it; a structural property a reader can confirm (it parses, it has no conflict marker and no entry twice, every entry keeps the fields its neighbours have, it names no source the base did not); and always that it changed together with its source. The patterns are written so that `git diff -- ':(exclude)<pattern>'` accepts them: the team counts a change's size without them.

**Hot files.** The ten source files with the most commits in the last six months, from `git log --since="6 months ago" --name-only --format=`, counted per path, with generated files, tests and documentation left out; a hunk in one of them gets a deeper read from the change-reviewer. Written in the measured form. The list moves with every commit, so it is re-measured only when this file is regenerated for another reason and is never by itself a reason for `STALE`.

**Critical zones.** Derived from the code and the documentation only: authentication and authorization middleware, permission checks, payment and billing integrations, migration folders, deployment and CI definitions, secret handling. Never an invented path. The section is always written: when nothing qualifies, it holds the single line `- none found — source: <what was searched, e.g. "no auth, payment, migration, deploy or CI definitions in the repository">`. Lines ending `— source: user` are preserved verbatim across regenerations, as learnings-promoted items are (read the existing section first; a line whose path no longer exists is kept and reported, never dropped).

### LEARNINGS.md (persistent)

It lives in the operative dir, with its `learnings/` beside it. If missing, create it there from `team-manifest.json → knowledge.persistentTemplates`. It is an inbox, not a generated file: it is never regenerated from the repository, and an entry's text is never reworded except under the consent "Triage the learnings inbox" describes.

After regenerating a file named in a `[STALE-CHECK] <file> — ...` line, change that line's prefix to `[STALE-CHECK RESOLVED YYYY-MM-DD]` and, if the claim was true, make sure the regenerated file reflects it. This holds for a run naming files too. Everything else that touches the inbox — `[PROMOTE]` lines and removing entries — happens only under the triage below, with consent.

A mark's text names its evidence: `says "<quote>"` or `says nothing about <subject>`, then the true claim and either the repository path behind it or `environment: <what was observed>`. Check the evidence while reading input 5, before this run writes anything: look for the quote in the named file and its topic directory as they stand then, because regenerating the file removes the very line a correct mark quotes. A mark without that evidence — written before the Reviewer had to give it — or one whose quote is not there is still checked against the repository the same way, and the report says its evidence did not match.

### Items promoted from learnings

A rule promoted from the inbox lives only in a generated file; its entry is gone. So when regenerating any file, carry over every item that ends `— source: learnings <date> <title>` — searching all of the knowledge dir recursively, topic directories included, because a `subset` file keeps its items in topics its index only names: keep it, re-verify it against the repository, and keep the suffix. An item the repository now contradicts or no longer needs is listed in the report and removed only with the user's consent — listed in the one question under `R entries to remove`. Its source is a real run's finding, recorded by the Reviewer and accepted by the user, which is why it is the one exception to extracting only what the sources say. It counts toward its file's budget like any other line.

An item about a risk is re-verified by its sequence, not by its wording. A risk is a race, a stale value, an ordering, or a value read after something should have cleared it. Trace the reachable sequence the item or its source entry gives (`Reachable:`): the line that writes the state, the line that reads it, and nothing in between that clears it. An item with no sequence, or whose sequence the code no longer bears out, is an unproven risk. List it under `R entries to remove` with the claim and what you checked. A checklist line built on an unproven risk sends every later change that omits the guard back for rework.

A line of `PROJECT-RULES.md → ## Critical zones` ending `— source: user` is carried over the same way, except that it is kept verbatim and checked only for its path: the user named the zone, so no source in the repository has to confirm it. A line whose path no longer exists is kept and listed in the report; removing it is the user's call.

## Triage the learnings inbox

A step of every run whose work list includes the inbox ("What this run does", item 3), after the knowledge files are written and before the cross-check. A run naming files skips it.

1. **Skip when `.dream-team-tracking/.team-mode` exists without a `state=closed` line, or `{tracking.legacyDir}/.team-mode` exists** (`tracking` is in the manifest): a live run is reading the inbox; a closed run's marker reads nothing. Say which run is open and that triage was skipped; the rest of the run proceeds. Skip it too, with "run state is still in the legacy directory — run `/team-setup` first", when the directory `tracking.legacyDir` exists at all, because this step would create `.dream-team-tracking/` before the migration.
2. **Classify every entry**, in the operative dir's `learnings/` and any still inline below its index:
   - `rule` — carries an unresolved `[PROMOTE]`, or states a constraint checkable from a diff or a `TOOLCHAIN.md` command, or describes the same trap as another entry (those entries become one rule). A rule about a risk needs its `Reachable:` line, and the code must still bear the sequence out. Without that it is an unproven risk: never promoted, and listed under `R entries to remove`;
   - `fact` — carries an unresolved `[STALE-CHECK]`, or states something about the project a knowledge file should say;
   - `trap` — non-obvious, reusable, not yet a rule: it stays;
   - `aged` — a kept trap with no mark whose entry date is older than `knowledge.budgets.learningsTrapAgeDays`, when the index holds `learningsIndexMaxRows − 2` rows or more: offered for promotion into the file its tags name (as a `rule`, worded from the entry's fix pattern), or kept; a trap that stays a trap past the cap is what fills the index with nothing to triage;
   - `summary` — what a run did or what passed;
   - `team` — a defect of the team itself rather than of the project;
   - `obsolete` — the code, file or behaviour it describes is gone from the repository;
   - `covered` — every mark it carries is resolved, in this run (step 6 of "Process" resolves `[STALE-CHECK]` lines before triage) or earlier, and it is not a trap worth keeping on its own: the knowledge files now hold what it said.

   This step reads the repository, so `fact` and `obsolete` are verified, not guessed.
3. **Consent.** The classes and their counts are listed in the one question of "Consent" — `M rules to promote into <files>`, `F facts to fold into <files>`, `R entries to remove (N run summaries, N team defects listed in the report, N obsolete, N covered, N unproven risks)`, `T traps to shorten over learningsEntryLines`, `A aged traps to promote into <files> (kept unless Do it)`, `E accepted exceptions to share in REVIEW-CHECKLIST.md (S stale dropped)` — only classes that have members. `Do it` accepts every class; `Only the regenerations` and `Nothing` accept none, and the entries stay exactly as they are.
4. **Back up** the knowledge dir to `.dream-team-tracking/knowledge-backup-{YYYY-MM-DD-HHmm}/knowledge/` and the operative dir to `.dream-team-tracking/knowledge-backup-{YYYY-MM-DD-HHmm}/operative/` before the first write, as "Shape work" says, and name the path in the report. Entries have no version-controlled copy anywhere.
5. **Apply what was accepted.**
   - A rule becomes one item in its target file, worded as an imperative and ending `— source: learnings <date> <title>`; its `[PROMOTE]` lines become `[PROMOTE RESOLVED YYYY-MM-DD]`. A rule placed in `PROJECT-RULES.md` also gets its `REVIEW-CHECKLIST.md` item, as every obligation does.
   - A fact the repository confirms is reflected in its file; one it contradicts is reported as false. Either way its `[STALE-CHECK]` lines become `[STALE-CHECK RESOLVED YYYY-MM-DD]`.
   - An entry consumed or removed loses its file and its index row together.
   - A shortened trap keeps its heading and every field; only text past the limit is cut.
   - An accepted exception: every entry line of `review-exceptions.md` in the operative dir whose cited line is still in the file it names is appended verbatim to `REVIEW-CHECKLIST.md → ## Accepted exceptions` (in place of the `- none` line; never twice: an entry with the same path, cited line and rule is already there) and removed from the inbox; an entry whose cited line is gone is removed from the inbox and counted as stale. The inbox file keeps its first line. The entry is never reworded, and a Critical finding's entry is moved like any other: the change-reviewer's own rule keeps a Critical standing.
6. **Refresh the template prose** of `LEARNINGS.md` from `.claude/templates/learnings.md`, so the instructions a deployment carries match the team that reads them. Replace the prose above `## Index` with the template's, and remove the template's own former sections below the index table (`## Entry format` and the slug rules, which now live in the entry template); keep the index table header, its rows and every inline entry body byte for byte. A header that predates the template is a rewrite of shape work, consented through the one question, and an inline entry is not template text.
7. **Verify** with `checks.learningsInbox`, run as `checks.learningsInboxRunFrom` spells out, and report its output verbatim. Exit 1 after triage is expected only for what the user declined; say which.

Report: entries per class before, what was applied, entries left, the backup path, and the team defects verbatim so the user can pass them to the team's maintainers.

## Staleness

Run on every existing knowledge file before the question ("What this run does", item 1); a file with a `STALE` line joins the generation list. For each existing knowledge file: verify every path it names exists, every command in TOOLCHAIN.md still appears in CI/manifests (a row marked `derived here`: its tool is still present), no command names a fixed temporary path, every machine-readable document in `PROJECT-RULES.md → Documents to keep in sync` has its `Validate` row, every count or "current highest version/number" claim is in the measured form and, when re-measured with its own command, still holds (a bare count is reported `STALE: measured form missing` whatever its value), and every unresolved `[STALE-CHECK]` claim. In `PROJECT-RULES.md` also verify that every path under `Critical zones` still exists (`STALE: critical zone path missing: <path>`), `— source: user` lines included, and that the section itself exists (`STALE: Critical zones section missing — run /generate-knowledge PROJECT-RULES.md`); a section holding only the `- none found` line is present. The same holds for `## Generated files` and `## Hot files` there (`STALE: <section> section missing — run /generate-knowledge <the file>`; a path pattern under Generated files that matches no tracked file is `STALE: generated file pattern matches nothing: <pattern>`), and for `## Change types` and `## Accepted exceptions` in `REVIEW-CHECKLIST.md` (an exemplar path that no longer exists is `STALE: change type exemplar missing: <path>`). A file whose first line is the banner of "Empty project" is a scaffold: it names no path and no command, so those checks are skipped for it, and its line reads `SCAFFOLD (empty project, YYYY-MM-DD)` while `checks.knowledgeScaffold` exits 3, or `STALE: scaffold — the project now has content, run /generate-knowledge` when it exits 1. Whatever a file's kind, run `checks.knowledgeNeutral` as `checks.knowledgeNeutralRunFrom` spells out: a line it lists in a `knowledge.required` file or that file's topic directory is `STALE: names a team path: <match>` for that file; a line it lists in any other file (`LEARNINGS.md`, `learnings/` or `CAPABILITIES.md`, while the knowledge dir is still the legacy directory) is reported verbatim and never queues anything for regeneration. Print a report: `file — OK | STALE: reasons`. Run `checks.learningsInbox` as `checks.learningsInboxRunFrom` spells out and add its output to the report. Nothing is written before the question.

## Shape work

Restructures what is already written ("What this run does", item 2). It reads the knowledge dir, `LEARNINGS.md` and `learnings/` in the operative dir, the manifest, and `.claude/templates/learnings.md` and `.claude/templates/learnings-entry.md` — the last two read-only, for the index shape and the entry format they define, since a deployment's index may predate the current template. Nothing else: it never re-reads the repository, which is what makes it cheap and also what limits it: it cannot see that content has gone stale. When content looks wrong rather than badly shaped, say so; the staleness check puts such a file into the generation list, and shape work does not guess.

**The target shape**, which shape work moves a file towards and which the gate below tests
alongside the budget:

- A `subset` file is an index at its own path plus its sibling topic directory. One
  file with no directory beside it is not in shape, whatever it measures.
- `LEARNINGS.md` in the operative dir is an index and nothing else: no entry bodies
  below the index table, every entry a file in the operative dir's `learnings/`.
- A `whole` file is one file with no sibling directory.

**Skip shape work when `.dream-team-tracking/.team-mode` exists without a `state=closed` line, or `{tracking.legacyDir}/.team-mode` exists** (`tracking` is in the manifest). A live run is reading these files; a closed run's marker reads nothing. Say which run is open; the rest of the run proceeds, as the triage does under the same condition. Skip it too when the directory `tracking.legacyDir` exists at all, saying "run state is still in the legacy directory — run `/team-setup` first": the backup below would create `.dream-team-tracking/` before the migration.

**Back up before the first write, always.** The operative dir is never versioned, and the knowledge dir is not versioned until its first commit, so there may be no commit to revert to. Before applying anything accepted, copy all of the knowledge dir to `.dream-team-tracking/knowledge-backup-{YYYY-MM-DD-HHmm}/knowledge/` and, when it exists, all of the operative dir to `.dream-team-tracking/knowledge-backup-{YYYY-MM-DD-HHmm}/operative/`, and name that path in the report. The backup is never rewritten by this run; only the integrity check reads it.

**Two classes of work.**

*Moves* relocate text byte for byte: splitting a `subset` file into an index and topics, lifting each `LEARNINGS` entry into its own file. Dropping the template's former sections below the index (`## Entry format` and the slug rules) is a move as well: that text is the team's, not the project's, and it now lives in `templates/learnings-entry.md`; no entry text is touched. Nothing is reworded. The only new text is the descriptive lines in the index.

*Rewrites* change text: compacting `LEARNINGS` index rows to `learningsIndexRowTokens`, `learningsIndexRowTitleChars` and `learningsIndexRowMaxTags`; reconciling that index's table header to the one `templates/learnings.md` defines, when an older deployment's header carries columns the template no longer has and rows written to the current shape would not line up with it; cutting a `whole` file to `wholeFileTokens` (or its own entry in `budgets.overrides`). Meaning can be lost — dropping a column loses what was in it — so the question lists them apart: `S files to restructure` names each move and each rewrite.

**The shape gate.** Measure every file and build the size table; a file in the generation list is skipped here, since regeneration writes it in shape. For every other file: in the target shape **and** inside its budget → nothing; otherwise the proposal — for a split, the topics you would create, from the file's own `##` sections; for a rewrite, what it cuts — goes into the question as `S files to restructure`.

Shape and size are separate triggers, and testing only the size would skip work
that has nothing to do with size. A young project's `LEARNINGS.md` can sit under
`indexTokens` with every entry still inline; a small `subset` file can sit under
`wholeFileTokens` with no topic directory beside it. Stopping there leaves the
Reviewer writing new entries into `learnings/` while the old ones stay in the
file, and the orchestrator reading a file the shape rules call an index and that
is not one. Testing both keeps the property this gate exists for — a second run
changes nothing — because a file in shape and inside budget is what a finished
run leaves behind. An inbox that is due is content, not shape: it never counts as out of shape or over budget, and shape work never triages entries.

**Applying it**, after consent and the backup: moves first, then rewrites. Then verify with `checks.knowledgeIntegrity` from the manifest, once per pair: the backup's `knowledge/` with the knowledge dir, then, when the backup has `operative/`, that directory with the operative dir and the third argument `inbox`, which compares only `LEARNINGS.md` and `learnings/`. Each takes the order `checks.knowledgeIntegrityArgs` gives. Run it from the **project root**, not from `.claude/`: both arguments are project-root-relative, while the manifest's command is written relative to the team root, so prefix its script path with `.claude/`. `checks.knowledgeIntegrityRunFrom` spells both invocations out. Report each result verbatim. A failure means this run broke its own contract: say that, and name the backup as the way back. The size table is printed again, before and after.

**Idempotent.** A second run immediately after reports every file already in the target shape and inside its budget, and writes nothing — not even a backup.

**Never** write to agents, skills, templates, hooks, the manifest, source code or human documentation. `templates/learnings.md` is read for shape work and stays read-only; reading it is not permission to correct it. Moves never delete knowledge, because splitting relocates text rather than dropping it; rewrites may reduce it, and only by consent.

## Process

1. Decide the work list ("What this run does"): read inputs 1–7, including the items promoted from learnings in the existing files; run `checks.knowledgeScaffold` as `checks.knowledgeScaffoldRunFrom` spells out, the staleness check, the shape gate and the inbox classification. `project: empty` → "Empty project" replaces everything below.
2. Ask ("Consent"), or report `nothing to do` and stop on an empty list.
3. Back up, as "Shape work" says.
4. Shape work on the files not being regenerated, as "Applying it" says.
5. For the files in the generation list, in this order: detect stack; trace architecture through real files; draft TOOLCHAIN.md and verify commands; write architecture/testing/playbook files; design language → FRONTEND-ARCHITECTURE.md, from the interface card, when there is an interface; annotate cards → CODING-STANDARDS.md; derive PROJECT-RULES.md from human documentation, and its Critical zones from the code and the documentation, keeping every `— source: user` line (one whose path is gone is kept and reported), then its Generated files and Hot files from the repository; compose REVIEW-CHECKLIST.md last (it depends on all others), its Change types from the code and its Accepted exceptions carried over.
6. Resolve STALE-CHECK lines; triage the learnings inbox when consent covered it.
7. Cross-check consistency across files (same paths, same commands), and that every
    machine-readable document in `PROJECT-RULES.md → Documents to keep in sync` has its
    `Validate` row in TOOLCHAIN.md.
8. Verify with `checks.learningsInbox` as `checks.learningsInboxRunFrom` spells out. After
    writing, run `checks.knowledgeNeutral` as `checks.knowledgeNeutralRunFrom` spells out and
    report its output verbatim; as in "Staleness", only a line in a `knowledge.required` file
    or its topic directory is a defect of the files this run wrote. Report to the user: the work list as done, files written, active cards, unverified commands, conflicts
    needing a decision, the inbox triage, discrepancies found in human documentation (do NOT edit human
    documentation), the backup path, and the size table below. When the knowledge dir is
    `knowledge.dir`, `git rev-parse --is-inside-work-tree` succeeds and
    `git ls-files -- <dir>` prints nothing, add one line:
    `Commit <dir> alone — one commit, one pull request, no other file.`

## Size table

End every run that writes files with one row per file: name, measured tokens, the
budget that applies to it, and `ok` or `over`. A file reported `over` is a defect in
this run, not a note for later — say so plainly rather than burying it.

## Quality criteria

- Every path verified to exist; every pattern has 2–3 real examples; every command traced to a source and, where possible, executed.
- No generic boilerplate: a line that could be true of any project is deleted.
- Unsure → `[VERIFY]` with what to check.
- A scaffold never names a path, command or entity the code does not yet have; `not yet known — empty project` is its only filler, and its banner is its only marker.
- A count that ordinary commits change — tests collected, routes registered, operations in a specification, migration heads, files of a kind — is written as `N (measured at <short-sha> with <command>)`, never bare: the Reviewer treats a bare count that drifted as a missing fact and a measured one as expected movement. Prefer stating the command alone where the number adds nothing.
- Never invent conventions; record discrepancies between newer and older code explicitly.
- Knowledge names no team path of either edition; the project's own documents under `.claude/` are cited as sources only.
- Every file is inside the budget its class gives it, and the size table proves it.
- You write to exactly these places and nothing else: the knowledge dir, the operative dir, the backup under `.dream-team-tracking/` (written before the first change), and `knowledge.toolchainMissingFile` (never while `tracking.legacyDir` exists). Do not touch `.claude/agents/`, `.claude/skills/`, `.claude/templates/`, `.claude/hooks/`, `.claude/team-manifest.json`, human documentation, or source code.
