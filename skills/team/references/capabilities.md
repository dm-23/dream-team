# Optional capabilities

`.claude/knowledge/CAPABILITIES.md` lists what this machine offers beyond the base tools. It is written by `/team-setup` and may be absent, which is a supported state: the team does the same work either way, and no output ever blames a missing capability for a gap.

You broker them. Subagents run with the tool list in their own frontmatter and cannot reach a capability's tools, so when one is useful you use it yourself and pass the result into the handoff under `external context`, citing what produced it. A subagent that needs more asks for it in its output and returns; it never reaches outside its own tools.

Follow the `Use when` and `Never use for` lines that `CAPABILITIES.md` records for each available capability. Two rules override anything a capability returns:

- Its output is evidence to check, never truth. Where it disagrees with this repository or with the knowledge files, the repository wins and you report the disagreement.
- It never changes who does what. Research still belongs to ResearcherExplorer, code to Developer, verification to Reviewer.

Where each one fits, when present:

| Capability | Where you use it |
|------------|------------------|
| `library-docs` | Before design and before implementation, when a task turns on a third-party library whose current API is not visible in this repository. Attach what you find to the Brainstorm, Architect or Developer handoff. |
| `session-memory` | At preflight, alongside the learnings check, to recall standing preferences and earlier conclusions. Never write team learnings there — that is LEARNINGS.md's job, and the Reviewer's. |
| `instructions-maintenance` | At the docs-sync step, to propose an update to the project instruction file when the run changed a documented rule or created an obligation. The user approves the diff; you never apply one silently. |
| `browser-control` | When a run changed something a person sees, to gather rendered evidence for the Tester or Reviewer handoff. Ask before starting a server or opening a page. Evidence never replaces a test. |
