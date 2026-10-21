# Decision routing (shadow mode)

Applies only when `CAPABILITIES.md` lists `decision-routing` as available. Otherwise skip this section entirely and never mention it. The service's mode in `team-manifest.json → services` is `shadow`: you ask it, you log what it said, and **nothing it says changes what you do** — not the workflow, not a model, not a question to the user. Do not show its answers to the user.

1. **Workflow.** In Step 0, after creating the run directory, write the user's task text exactly as typed to `routing/task.txt` in it, and run `bash .claude/tools/jev-decide.sh workflow .dream-team-tracking/{context_id}/routing/task.txt`. Decide the workflow yourself as if the service did not exist.
2. **Difficulty.** For Bug Fix and Small Change only, run the same script with `difficulty` and the same file.
3. **Log.** Append one line per call to `routing.log` in the run directory, fields separated by a single tab, in the shapes below. From the JSON it prints, take `answers.{name}.choice` and `answers.{name}.confidence` (two decimals). When it prints nothing, write `jev=unavailable` and `conf=-`. `{provider}` is the provider named in the Services row of `CAPABILITIES.md`, so a change of provider shows in the numbers. Never retry.
   - `{YYYY-MM-DD}	workflow	jev={choice}	conf={confidence}	team={your workflow}	provider={provider}`
   - `{YYYY-MM-DD}	difficulty	jev={choice}	conf={confidence}	provider={provider}`
4. **Outcome.** When the run closes as `[DONE]`, before marking it, append:
   - `{YYYY-MM-DD}	outcome	workflow={workflow the run finished as}	override={yes if the user switched the workflow, else no}	files={N}	rework={N}`
   - `files` is the number of distinct paths changed since the baseline (`git diff --name-only {baseline}` plus new untracked files, excluding the baseline's pre-existing ones). `rework` is the number of times a Reviewer's `needs rework` led to a Developer rework handoff; a vote that confirms nothing is not rework; an `Unverified` line alone is not rework.
   - A run that is stopped or discarded gets no outcome line.

Workflow keys are the workflow names lowercased with spaces as underscores: `analyze`, `docs`, `bug_fix`, `small_change`, `change_set`, `full_feature`. The only text that leaves the machine is `routing/task.txt`; never put anything but the user's own words there. `bash .claude/checks/summarize-routing.sh` turns the logs into the numbers the owner uses to decide whether the service may ever act.
