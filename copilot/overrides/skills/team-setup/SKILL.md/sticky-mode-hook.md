7. **Sticky-mode hook.**
7. **Session hook.** Read the `hooks` block of the manifest and verify that a new session can learn about an open run:
   - Files: `hooks.config` exists, and `hooks.script` and `hooks.windowsLauncher` exist under `hooks.dir`. `copilot/install.sh` installs them; nothing is merged into any settings file, and this skill never writes them.
   - Shell: a bash interpreter must be reachable, otherwise the hook exits quietly and the reminder is unavailable. Report `bash: found|absent (session reminder disabled)`.
   - VS Code runs hooks only while its `chat.useHooks` setting is on, a preview feature this skill cannot read. Say so once in the report.
   - Marker: if `hooks.marker` exists, read it and report the run it names; if that run's `status.md` is missing or its first line contains `[DONE]` anywhere, report it as stale and (fix mode) delete the marker after confirmation through AskUserQuestion.
