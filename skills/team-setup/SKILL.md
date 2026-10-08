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
2. **Team files.** The team is deployed as one layer: the repository's contents sit directly in `.claude/`, which is where Claude Code discovers agents and skills, so there are no copies or links to keep in sync. For each name in `agents[]` verify `.claude/agents/<name>.md` exists and its frontmatter `name:` matches; for each in `skills[]` verify `.claude/skills/<name>/SKILL.md`. Verify every template path under `templates` exists and `templates.standards` contains `_generic.md`. Verify too that every script the `checks` block names exists under `.claude/`: `checks.manifestBudgets` and `checks.knowledgeIntegrity` each give a path relative to the team root, and a deployment that lost them passes every other test in this skill while `/generate-knowledge fix` silently cannot verify its own work. Do the same for `checks.jevClient` and `checks.updateCheckClient`, for `updateCheck.script`, and for every `services[]` entry verify its `script` and its `questions` directory exist. Report anything missing by name; a missing file means an incomplete deployment, and the fix is to re-copy the team's contents into `.claude/`, which this skill never does by itself.
3. **Stack neutrality.** Run `checks.stackNeutralityLint` from the manifest via Bash, from the directory named in `checks.runFrom`. Expected: no output. Any hit is reported as a team defect (file:line).
4. **Version-control exclude.** Generated files are hidden in two places, and both are checked.
   - `.claude/.gitignore` ships with the team and covers `knowledge/` from inside `.claude/`. Verify it exists and still carries that line; if it was deleted or edited, report it — this skill never rewrites it.
   - The run-state directory, `tracking.dir`, is shared by every edition of the team and belongs in the project's own `.gitignore`, which is committed and so hides it for everyone. If that file does not hide it, in `fix` mode ask via AskUserQuestion whether to add the line `{tracking.dir}/`, saying that the file is committed. Yes → append the line. No → handle it like the entries below. If the project's `.gitignore` still holds a line for `tracking.legacyDir` once step 9 has moved the legacy state, offer in the same question to remove it. Apart from those lines, and only with the user's answer in this run, never edit the project's `.gitignore`.
   - `.git/info/exclude` is machine-local and covers the rest. For each entry in `gitExclude[]` that the project's `.gitignore` does not already hide, check a matching line exists; in `fix` mode append the missing ones after AskUserQuestion confirmation.
5. **Plugins, services and capabilities.** Read `plugins[]`, `pluginPolicy`, `services[]` and `servicePolicy` from the manifest.
   - **Detect.** For each entry, decide whether its capability is actually present: check the tools and commands available in this session against the entry's `detect` description, and, if the `claude` command-line tool is reachable, cross-check `claude plugin list`. Report a capability as available only when you can see it, not because the plugin name appears in a list.
   - **Consent.** Every entry is optional. In `check` mode install nothing. In `fix` mode, list what is missing and ask via AskUserQuestion **per plugin**, naming what it is for and what it would let the team do; install only the ones the user picks, with the entry's `install` command. Never install anything unasked, never install two entries that share a `capability`, and never enable or disable a plugin the user did not name.
   - **Services.** A service is not a plugin: nothing is installed, but it sends data off this machine, so it has its own consent. For each `services[]` entry:
     - *Credentials.* An entry may reach the service through several `providers`, each naming its own `credential` variable. For each provider, ask bash whether that variable is non-empty (`[ -n "$VARIABLE" ]`); never print it. A provider whose variable is unset is `no key`. Never ask for the key itself, never have it pasted into the chat, and never write it anywhere: the user sets it, following the entry's `keySetup`.
     - *Consent.* Read `.dream-team-tracking/.service-consent`; the last line starting with `{name}=` is the answer, and a granted line without a provider means `defaultProvider`. In `check` mode only report what it says. In `fix` mode, when there is no line for the service, or the user asked to change it, ask via AskUserQuestion, whether or not any key is set: a user who has never heard of the service learns of it here. Offer one option per provider, each marked `key set` or `no key yet`, plus declining; for each, state verbatim its `endpoint`, `recipients` and `retention`, and once for all the service's `dataSent`, what it decides, and its `mode` (in `shadow` nothing it says changes a run). When the options send the text to different companies, say so in the question. Write `{name}=granted {provider} YYYY-MM-DD` or `{name}=declined YYYY-MM-DD`, replacing every earlier line for that service. Consent to a provider without a key is recorded all the same; the script sends nothing until the key exists.
     - *Getting a key.* Whenever consent names a provider whose key is unset, in either mode, tell the user how to finish: the provider's `keyUrl` (and its `keyUrlNote`, verbatim, if it has one) and the entry's `keySetup` with `{credential}` replaced by that provider's variable. The next `/team-setup`, check or fix, probes once the key is set; nothing is asked again.
     - *Probe.* Only for the provider consent names, and only when its key is set: run `bash .claude/{script} probe {provider}`. Output → reachable. Nothing → `unreachable`: the key was rejected, the network failed or the service is down, and which one is unknown — say so rather than guess.
     - A service is available only when all three hold for the same provider.
   - **Update check.** Not a service and not a capability: an optional request for the team's own newest version number, read from the manifest's `updateCheck`. Read the last line of `.dream-team-tracking/.service-consent` that starts with `update-check=`.
     - In `check` mode only report what the line says.
     - In `fix` mode, when there is no line, or the user asked to change it, ask via AskUserQuestion whether to turn it on. State `dataSent` and `recipients` verbatim, and say that `/team` runs it only when a new run starts, at most once per `intervalHours`, and that it never updates anything: it shows the update command and the user runs it. Write `update-check=granted YYYY-MM-DD` or `update-check=declined YYYY-MM-DD`, replacing every earlier `update-check=` line. Without an answer it stays off (`default`).
     - In either mode, when the line is `granted` once the steps above are done, run `bash .claude/{updateCheck.script} probe` and compare what it prints with `team.version`: the same or older → up to date; newer → that version is available; nothing → `unreachable`: the network failed, the source is down, or curl is absent, and which one is unknown — say so rather than guess.
   - **Write `CAPABILITIES.md`.** Render `templates.capabilities` into `knowledge.environment.CAPABILITIES.md` under `knowledge.dir`: available capabilities with their brokering and roles, unavailable ones with their install commands, available services under "Services" with their mode and `dataSent`, and the `useWhen` / `neverUseFor` rules copied verbatim from the manifest for the available ones only. If nothing is available, still write the file with "None detected." — the agents read it either way. Rewrite the file completely on every run; it describes the machine, not the repository, so it is never merged or hand-edited.
   - **Direct access.** For each available capability whose `usedBy` names a subagent, report that the role would need the capability's tools added to its frontmatter to call it directly, and that by default the orchestrator brokers it. Report only; never edit an agent.
6. **Knowledge.** For each file in `knowledge.required` check presence under `knowledge.dir`; for `knowledge.persistent` check presence, else (fix mode) create from `persistentTemplates`. An entry ending in `/` is a directory, not a file: check that the directory exists and (fix mode) create it empty. It has no `persistentTemplates` entry and needs none — an empty learnings directory is the correct state of a project that has not produced an entry yet, and inventing a file to put in it would put content in the knowledge base that no run produced. If required files are missing, tell the user to run `knowledge.generator`.
7. **Sticky-mode hook.** Read the `hooks` block of the manifest and verify the team can keep a run active across model switches and restarts:
   - Files: `hooks.launcher` and every script it dispatches exist under `hooks.dir`.
   - Wiring: the project's `.claude/settings.json` must contain a `UserPromptSubmit` entry whose command names `run-hook.cmd`. Report whether it was found.
   - Shell: a bash interpreter must be reachable, otherwise the hook exits quietly and sticky mode is unavailable. Report `bash: found|absent (sticky mode disabled)`.
   - In `fix` mode, when no matching entry exists, show the entry from `hooks.settingsSnippet` and ask via AskUserQuestion before merging it into `.claude/settings.json`. Merge into the existing `UserPromptSubmit` array; never replace an existing hooks block. Warn the user that a newly added hook is picked up after they open `/hooks` once or restart the session.
   - Marker: if `hooks.marker` exists, read it and report the run it names; if that run's `status.md` is missing or already `[DONE]`, report it as stale and (fix mode) delete the marker after confirmation.
8. **Toolchain.** If `TOOLCHAIN.md` exists, read `## Missing on this machine` and report it verbatim.
9. **Legacy run state.** Read `tracking.legacyDir` and `tracking.migration` from the manifest. If the legacy directory does not exist at the project root, report `Tracking: {tracking.dir} ok` and stop this step. Otherwise run `bash .claude/{tracking.migration} --dry-run` and report what it prints. In `fix` mode ask via AskUserQuestion whether to move the state now, quoting the dry run's counts; on yes run `bash .claude/{tracking.migration}` and report its output verbatim, including the project files it lists for the user to edit by hand. A refusal because a run is open is reported with the instruction the script prints; the other steps still count. Never move, copy or delete run-state files yourself.

## Report format

```
Dream Team setup — {check|fix}
Manifest: ok (v{team.version})
Team files: ok | missing: [...] → re-copy the team into .claude/
Check scripts: ok | missing: [...] → re-copy the team into .claude/
Stack neutrality: ok | violations: [...]
Version-control exclude: .claude/.gitignore ok|altered|missing — project .gitignore hides {tracking.dir}: yes | added | declined — .git/info/exclude ok | added: [...] | missing (run fix): [...]
Tracking: {tracking.dir} ok | legacy {tracking.legacyDir} present (run fix) | migrated this run | refused: open run {context_id}
Capabilities: available: [...] | none detected | installed this run: [...] | declined: [...]
  CAPABILITIES.md: written | unchanged
  Direct access would need a frontmatter change: {capability} → {role} | none
Services: {name} ({capability}): available via {provider} ({mode}) | no key for any provider | consent not asked (run fix) | declined | consented to {provider} but no key for it → set {credential}, key from {keyUrl} | unreachable via {provider}
Update check: on — up to date (v{team.version}) | v{R} available → README "Updating the team" | unreachable | off | not asked (run fix)
Knowledge: ok | missing: [...] → run /generate-knowledge
Sticky mode: wired via project settings | NOT wired (run fix) — bash: found|absent
Active run: none | {context_id} (phase {N}) | stale marker → {context_id} already closed
Toolchain: ok | missing tools: [...]
```

## Rules

- Never modify agents, skills, or templates. The only knowledge files you may write are the persistent ones listed in the manifest and `CAPABILITIES.md`.
- Never install, enable or disable a plugin the user did not explicitly agree to in this run.
- Never edit the team's `.claude/.gitignore`. Edit the project's own `.gitignore` only as step 4 describes: the run-state lines, with the user's answer in this run.
- Never run any command other than the manifest lint, `claude plugin list/install`, a bash availability check, a service's credential test and `probe`, the update check's `probe`, the run-state migration script, and reading files.
- In `check` mode change nothing except `CAPABILITIES.md`, which is a report of what the machine offers, and `.dream-team-tracking/.update-check`, which the update check's `probe` writes itself; in `fix` mode the version-control exclude file, the run-state lines of the project's .gitignore, the run state the migration moves (and the knowledge it rewrites), the project settings hooks entry, the persistent knowledge files, a stale marker, `.dream-team-tracking/.service-consent`, and plugins the user picked may also change, each after confirmation.
- Never copy, move or delete a team file. A missing or edited agent, skill or template is reported and left alone; replacing the deployment is the user's call.
