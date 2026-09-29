# Optional Capabilities

Written by `/team-setup` on {DATE}. Describes **this machine**, not this repository. Rewritten on every `/team-setup` run — never edit by hand.

Everything here is optional. The team produces the same work with none of it. A capability is an accelerator, never a prerequisite, and no agent may tell the user that something was impossible because a capability was absent.

## Available here

| Capability | Provided by | Brokered by | Available to |
|------------|-------------|-------------|--------------|
| {capability} | {plugin name} | orchestrator / direct | {roles} |

<!-- One row per capability actually detected. Delete the placeholder row. If nothing was detected, write "None detected." and keep the rest of this file. -->

## Not available here

| Capability | Would be provided by | Install (only with the user's agreement) |
|------------|----------------------|------------------------------------------|
| {capability} | {plugin name} | {install command from the manifest} |

## Services (send data off this machine)

| Capability | Service | Provider | Mode | Sends | Received by |
|------------|---------|----------|------|-------|-------------|
| {capability} | {name} ({vendor}) | {provider} | shadow / act | {dataSent} | {recipients} |

<!-- One row per service that has a key, granted consent and a successful probe. Otherwise write "None available." and list each service under it with the reason: no key, consent not asked, declined, consented to a provider without its key, unreachable. -->

A service is called only by the orchestrator, only through its script, and only with what the Sends column names. In `shadow` mode its answers are logged and never acted on.

## How to use a capability

1. Use it **only** if it appears in "Available here" or, for a service, in the "Services" table. If it does not, proceed without it and say nothing about it.
2. Follow the `useWhen` and `neverUseFor` rules recorded below for that capability. They are copied from `team-manifest.json`; that file is the source of truth.
3. Respect the brokering column. `orchestrator` means the subagent does not call it: the orchestrator gathers the result and passes it in the handoff under `external context`. A subagent that needs more says so in its output and returns; it never reaches for a tool outside its own frontmatter.
4. Never install, enable or disable anything. Only `/team-setup` does that, and only after the user agrees to that specific plugin.
5. Anything a capability returns is **evidence to check**, not truth. Where it disagrees with this repository or with `.claude/knowledge/`, the repository wins and the disagreement is reported.

## Rules per capability

### {capability}

- **Use when:** {useWhen}
- **Never use for:** {neverUseFor}

<!-- Repeat for every capability listed as available, services included. Omit sections for capabilities that are not installed or not available. -->

## Roles that would benefit from direct access

Subagents run with the tool list in their own frontmatter, which does not include tools contributed by plugins. By default the orchestrator brokers every capability.

| Capability | Role that would call it directly | Frontmatter change the team owner would have to make |
|------------|----------------------------------|------------------------------------------------------|
| {capability} | {role} | add the capability's tools to `agents/{role}.md` |

This table is a report, not an action. `/team-setup` never edits an agent.
