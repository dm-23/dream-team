---
name: team-setup
description: Use when the user asks to set up, check, or repair the Dream Team installation in the current repository — validates team-manifest.json, version-control exclude rules for local knowledge, required plugins, and knowledge presence. Safe to run repeatedly. Never auto-invoke.
argument-hint: "[check | fix]"
disable-model-invocation: true
user-invocable: true
---

You are the Team Setup checker. Mode from `$ARGUMENTS`: `check` (default; report only) or `fix` (apply safe repairs after confirmation).

## Steps

1. **Manifest.** Read `.claude/team-manifest.json`. Fail if missing or invalid, or `schemaVersion` ≠ 1.
2. **Team files.** The team is deployed as one layer: the repository's contents sit directly in `.claude/`, which is where Claude Code discovers agents and skills, so there are no copies or links to keep in sync. For each name in `agents[]` verify `.claude/agents/<name>.md` exists and its frontmatter `name:` matches; for each in `skills[]` verify `.claude/skills/<name>/SKILL.md`. Verify every template path under `templates` exists and `templates.standards` contains `_generic.md`. Report anything missing by name; a missing file means an incomplete deployment, and the fix is to re-copy the team's contents into `.claude/`, which this skill never does by itself.
3. **Stack neutrality.** Run `checks.stackNeutralityLint` from the manifest via Bash, from the directory named in `checks.runFrom`. Expected: no output. Any hit is reported as a team defect (file:line).
4. **Version-control exclude.** Generated files are hidden in two places, and both are checked.
   - `.claude/.gitignore` ships with the team and covers `knowledge/` from inside `.claude/`. Verify it exists and still carries that line; if it was deleted or edited, report it — this skill never rewrites it.
   - `.git/info/exclude` is machine-local and covers the rest. For each entry in `gitExclude[]` check a matching line exists; in `fix` mode append the missing ones after AskUserQuestion confirmation.
   - The project's own ignore file at the repository root must NOT contain these paths, and this skill never edits it. `.claude/.gitignore` is the team's file, not the project's, and is the one exception.
5. **Plugins and capabilities.** Read `plugins[]` and `pluginPolicy` from the manifest.
   - **Detect.** For each entry, decide whether its capability is actually present: check the tools and commands available in this session against the entry's `detect` description, and, if the `claude` command-line tool is reachable, cross-check `claude plugin list`. Report a capability as available only when you can see it, not because the plugin name appears in a list.
   - **Consent.** Every entry is optional. In `check` mode install nothing. In `fix` mode, list what is missing and ask via AskUserQuestion **per plugin**, naming what it is for and what it would let the team do; install only the ones the user picks, with the entry's `install` command. Never install anything unasked, never install two entries that share a `capability`, and never enable or disable a plugin the user did not name.
   - **Write `CAPABILITIES.md`.** Render `templates.capabilities` into `knowledge.environment.CAPABILITIES.md` under `knowledge.dir`: available capabilities with their brokering and roles, unavailable ones with their install commands, and the `useWhen` / `neverUseFor` rules copied verbatim from the manifest for the available ones only. If nothing is available, still write the file with "None detected." — the agents read it either way. Rewrite the file completely on every run; it describes the machine, not the repository, so it is never merged or hand-edited.
   - **Direct access.** For each available capability whose `usedBy` names a subagent, report that the role would need the capability's tools added to its frontmatter to call it directly, and that by default the orchestrator brokers it. Report only; never edit an agent.
6. **Knowledge.** For each file in `knowledge.required` check presence under `knowledge.dir`; for `knowledge.persistent` check presence, else (fix mode) create from `persistentTemplates`. If required files are missing, tell the user to run `knowledge.generator`.
7. **Sticky-mode hook.** Read the `hooks` block of the manifest and verify the team can keep a run active across model switches and restarts:
   - Files: `hooks.launcher` and every script it dispatches exist under `hooks.dir`.
   - Wiring: the project's `.claude/settings.json` must contain a `UserPromptSubmit` entry whose command names `run-hook.cmd`. Report whether it was found.
   - Shell: a bash interpreter must be reachable, otherwise the hook exits quietly and sticky mode is unavailable. Report `bash: found|absent (sticky mode disabled)`.
   - In `fix` mode, when no matching entry exists, show the entry from `hooks.settingsSnippet` and ask via AskUserQuestion before merging it into `.claude/settings.json`. Merge into the existing `UserPromptSubmit` array; never replace an existing hooks block. Warn the user that a newly added hook is picked up after they open `/hooks` once or restart the session.
   - Marker: if `hooks.marker` exists, read it and report the run it names; if that run's `status.md` is missing or already `[DONE]`, report it as stale and (fix mode) delete the marker after confirmation.
8. **Toolchain.** If `TOOLCHAIN.md` exists, read `## Missing on this machine` and report it verbatim.

## Report format

```
Dream Team setup — {check|fix}
Manifest: ok (v{team.version})
Team files: ok | missing: [...] → re-copy the team into .claude/
Stack neutrality: ok | violations: [...]
Version-control exclude: .claude/.gitignore ok|altered|missing — .git/info/exclude ok | added: [...] | missing (run fix): [...]
Capabilities: available: [...] | none detected | installed this run: [...] | declined: [...]
  CAPABILITIES.md: written | unchanged
  Direct access would need a frontmatter change: {capability} → {role} | none
Knowledge: ok | missing: [...] → run /generate-knowledge
Sticky mode: wired via project settings | NOT wired (run fix) — bash: found|absent
Active run: none | {context_id} (phase {N}) | stale marker → {context_id} already closed
Toolchain: ok | missing tools: [...]
```

## Rules

- Never modify agents, skills, or templates. The only knowledge files you may write are the persistent ones listed in the manifest and `CAPABILITIES.md`.
- Never install, enable or disable a plugin the user did not explicitly agree to in this run.
- Never edit an ignore file: neither the project's own at the repository root, nor the team's `.claude/.gitignore`. Report, do not repair.
- Never run any command other than the manifest lint, `claude plugin list/install`, a bash availability check, and reading files.
- In `check` mode change nothing except `CAPABILITIES.md`, which is a report of what the machine offers; in `fix` mode the version-control exclude file, the project settings hooks entry, the persistent knowledge files, a stale marker, and plugins the user picked may also change, each after confirmation.
- Never copy, move or delete a team file. A missing or edited agent, skill or template is reported and left alone; replacing the deployment is the user's call.
