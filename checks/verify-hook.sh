#!/usr/bin/env bash
# Exercises hooks/team-mode-prompt and hooks/guard-command against scratch
# project directories.
#
#   verify-hook.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds a throwaway project, feeds a hook its payload on stdin
# (UserPromptSubmit or PreToolUse) with CLAUDE_PROJECT_DIR pointing at it, and
# asserts on the text the hook prints. No JSON parser: the assertions are greps on the exact
# strings the skill and the harness depend on. Exit 0 = every case passed,
# 1 = at least one failed; each failure names its case.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/team-mode-prompt"
GUARD="$ROOT/hooks/guard-command"
LAUNCHER="$ROOT/hooks/run-hook.cmd"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

fails=0
fail() { echo "FAIL [$1] $2" >&2; fails=$((fails + 1)); }

# run CASE PROJECT PROMPT -> sets OUT and RC
run() {
  OUT="$(printf '{"session_id":"s","prompt":%s}' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$HOOK")"; RC=$?
}
project() { local p="$TMP/$1"; mkdir -p "$p"; printf '%s' "$p"; }
marker() { # dir context_id phase
  mkdir -p "$1/.dream-team-tracking"
  printf 'context_id=%s\nworkflow=Bug Fix\nphase=%s\nlanguage=Russian\nstarted=2026-10-08\n' "$2" "$3" > "$1/.dream-team-tracking/.team-mode"
}
status() { # dir context_id first-line
  mkdir -p "$1/.dream-team-tracking/$2"
  printf '%s\n\n**Workflow:** Bug Fix\n' "$3" > "$1/.dream-team-tracking/$2/status.md"
}

# 1. nothing to say
p="$(project empty)"
run empty "$p" '"hello"'
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail empty "expected silence, got exit $RC: $OUT"

# 2. open run, plain prompt
p="$(project open)"; marker "$p" bug_fix_x_2026-10-08 "3 Design"; status "$p" bug_fix_x_2026-10-08 "# Status: x"
run open "$p" '"hello"'
case "$OUT" in *'"hookEventName": "UserPromptSubmit"'*) ;; *) fail open "no hookEventName: $OUT" ;; esac
case "$OUT" in *TEAM-MODE-ACTIVE*bug_fix_x_2026-10-08*"3 Design"*) ;; *) fail open "no active block: $OUT" ;; esac
case "$OUT" in *TEAM-MODE-STALE*|*TEAM-LEGACY-STATE*) fail open "unexpected block: $OUT" ;; esac

# 3. slash prompt is never captured
run slash "$p" '"/team status"'
[ -z "$OUT" ] || fail slash "expected silence: $OUT"

# 4. whitespace before the slash, raw and JSON-escaped
run slash-space "$p" '"  /team status"'
[ -z "$OUT" ] || fail slash-space "expected silence: $OUT"
run slash-newline "$p" '"\n/team status"'
[ -z "$OUT" ] || fail slash-newline "expected silence: $OUT"

# 5. marker of a closed run: [DONE] anywhere in the first line
p="$(project done)"; marker "$p" bug_fix_y_2026-10-08 "9 Close"; status "$p" bug_fix_y_2026-10-08 "# [DONE] 2026-10-08 — shipped"
run done "$p" '"hello"'
case "$OUT" in *TEAM-MODE-ACTIVE*) fail done "closed run still active: $OUT" ;; esac
case "$OUT" in *TEAM-MODE-STALE*bug_fix_y_2026-10-08*closed*) ;; *) fail done "no stale block: $OUT" ;; esac
case "$OUT" in *'rm -f .dream-team-tracking/.team-mode'*) ;; *) fail done "stale block lacks the delete command: $OUT" ;; esac

# 6. marker of a run with no status.md
p="$(project nostatus)"; marker "$p" bug_fix_z_2026-10-08 "1 Clarify"
run nostatus "$p" '"hello"'
case "$OUT" in *TEAM-MODE-ACTIVE*) fail nostatus "run without status.md still active: $OUT" ;; esac
case "$OUT" in *TEAM-MODE-STALE*bug_fix_z_2026-10-08*missing*) ;; *) fail nostatus "no stale block: $OUT" ;; esac

# 7. legacy directory present: notice on every prompt, slash included, even when empty
p="$(project legacy)"; mkdir -p "$p/.claude-tracking"
run legacy "$p" '"hello"'
case "$OUT" in *TEAM-LEGACY-STATE*'.claude-tracking/'*'/team-setup fix'*) ;; *) fail legacy "no legacy block: $OUT" ;; esac
case "$OUT" in *'<TEAM-MODE-ACTIVE>'*) fail legacy "active block without a marker: $OUT" ;; esac
run legacy-slash "$p" '"/team fix the thing"'
case "$OUT" in *TEAM-LEGACY-STATE*) ;; *) fail legacy-slash "legacy block must survive a slash prompt: $OUT" ;; esac
marker "$p" bug_fix_w_2026-10-08 "2 Research"; status "$p" bug_fix_w_2026-10-08 "# Status: w"
run legacy-open "$p" '"hello"'
case "$OUT" in *TEAM-LEGACY-STATE*'<TEAM-MODE-ACTIVE>'*) ;; *) fail legacy-open "expected legacy then active: $OUT" ;; esac

# 8. JSON escaping of phase text
p="$(project escape)"; marker "$p" bug_fix_q_2026-10-08 '4.1 Batch "A" done \ next'; status "$p" bug_fix_q_2026-10-08 "# Status: q"
run escape "$p" '"hello"'
case "$OUT" in *'Batch \"A\" done \\ next'*) ;; *) fail escape "phase not escaped for JSON: $OUT" ;; esac
n="$(printf '%s' "$OUT" | tr -cd '"' | wc -c)"
[ $((n % 2)) -eq 0 ] || fail escape "odd number of double quotes in output"

# 9. the launcher reaches the same script
p="$(project launcher)"; marker "$p" bug_fix_l_2026-10-08 "3 Design"; status "$p" bug_fix_l_2026-10-08 "# Status: l"
OUT="$(printf '{"prompt":"hello"}' | CLAUDE_PROJECT_DIR="$p" bash "$LAUNCHER" team-mode-prompt)"
case "$OUT" in *TEAM-MODE-ACTIVE*bug_fix_l_2026-10-08*) ;; *) fail launcher "launcher output: $OUT" ;; esac

# 9b. the snippet's command as a harness runs it: from the project root, with
#     CLAUDE_PROJECT_DIR unset. Claude Code runs it under bash; VS Code Copilot
#     reads the same .claude/settings.json entry, ignores its "shell" field and
#     runs the command in the Windows default shell, PowerShell. The command
#     must therefore parse in both, so it carries no bash-only syntax.
SNIPPET_CMD="$(sed -n 's/^[[:space:]]*"command": "\(.*\)",$/\1/p' "$ROOT/hooks/settings-snippet.json" | head -1 | sed 's/\\"/"/g')"
[ -n "$SNIPPET_CMD" ] || fail snippet-cmd "no command line found in settings-snippet.json"
mkdir -p "$p/.claude/hooks"; cp "$ROOT/hooks/run-hook.cmd" "$ROOT/hooks/team-mode-prompt" "$p/.claude/hooks/"
OUT="$(cd "$p" && printf '{"prompt":"hello"}' | env -u CLAUDE_PROJECT_DIR bash -c "$SNIPPET_CMD" 2>&1)"
case "$OUT" in *TEAM-MODE-ACTIVE*bug_fix_l_2026-10-08*) ;; *) fail snippet-bash "snippet command under bash: $OUT" ;; esac
if command -v powershell.exe >/dev/null 2>&1; then
  OUT="$(cd "$p" && printf '{"prompt":"hello"}' | env -u CLAUDE_PROJECT_DIR powershell.exe -NoProfile -NonInteractive -Command "$SNIPPET_CMD" 2>&1)"
  case "$OUT" in *TEAM-MODE-ACTIVE*bug_fix_l_2026-10-08*) ;; *) fail snippet-powershell "snippet command under PowerShell: $OUT" ;; esac
fi

# 10. inbox due: only on a /team <task> prompt, only when the check says so
inbox_project() { # name LEARNINGS-body -> project path with a team root, a manifest and a knowledge dir
  local p; p="$(project "$1")"
  mkdir -p "$p/.claude/knowledge/learnings" "$p/.claude/checks" "$p/.claude/hooks"
  cp "$ROOT/team-manifest.json" "$p/.claude/team-manifest.json"
  cp "$ROOT/checks/verify-learnings-inbox.sh" "$p/.claude/checks/"
  cp "$ROOT/hooks/team-mode-prompt" "$p/.claude/hooks/"
  printf '%s\n' "$2" > "$p/.claude/knowledge/LEARNINGS.md"
  printf '%s' "$p"
}
run_deployed() { # CASE PROJECT PROMPT: runs the hook from its deployed place
  OUT="$(printf '{"prompt":%s}' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$2/.claude/hooks/team-mode-prompt")"; RC=$?
}
due_body='# Inbox

## Index

| Date | Title | Tags |
|------|-------|------|
| 2026-10-01 | A trap | tag |
'
p="$(inbox_project inbox-due "$due_body")"
printf '## [2026-10-01] A trap\n- **Tags:** tag\n[PROMOTE] PROJECT-RULES.md — do the thing\n' > "$p/.claude/knowledge/learnings/2026-10-01-a-trap.md"
run_deployed inbox-due "$p" '"/team fix the crash"'
case "$OUT" in *TEAM-INBOX-DUE*'1 pending marks'*'/generate-knowledge all'*) ;; *) fail inbox-due "expected the inbox block: $OUT" ;; esac
run_deployed inbox-due-plain "$p" '"hello"'
case "$OUT" in *TEAM-INBOX-DUE*) fail inbox-due-plain "inbox block on a plain prompt: $OUT" ;; esac
run_deployed inbox-due-status "$p" '"/team status"'
case "$OUT" in *TEAM-INBOX-DUE*) fail inbox-due-status "inbox block on /team status: $OUT" ;; esac

# 11. inbox clean: silence
p="$(inbox_project inbox-clean "$due_body")"
run_deployed inbox-clean "$p" '"/team fix the crash"'
[ -z "$OUT" ] || fail inbox-clean "expected silence: $OUT"

# 12. inbox check cannot read its limits (old manifest): silence, never a false "due"
p="$(inbox_project inbox-old "$due_body")"
sed -i 's/"learningsIndexMaxRows": [0-9]*,/"learningsIndexMaxRowsX": 30,/' "$p/.claude/team-manifest.json"
printf '## [2026-10-01] A trap\n- **Tags:** tag\n[PROMOTE] PROJECT-RULES.md — do the thing\n' > "$p/.claude/knowledge/learnings/2026-10-01-a-trap.md"
run_deployed inbox-old "$p" '"/team fix the crash"'
[ -z "$OUT" ] || fail inbox-old "expected silence on exit 2: $OUT"

# 13. the guard: PreToolUse on Bash, silent outside a run
json_string() { # raw text -> a JSON string literal
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}
guard() { # CASE PROJECT COMMAND -> sets OUT and RC; COMMAND is raw text, encoded here
  OUT="$(printf '{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' "$(json_string "$3")" \
    | CLAUDE_PROJECT_DIR="$2" bash "$GUARD" 2>&1)"; RC=$?
}
expect_deny() { # CASE PROJECT COMMAND REASON-KEYWORD
  guard "$1" "$2" "$3"
  [ "$RC" = 0 ] || fail "$1" "exit $RC: $OUT"
  case "$OUT" in *'"hookEventName": "PreToolUse"'*'"permissionDecision": "deny"'*) ;; *) fail "$1" "no deny for '$3': $OUT"; return ;; esac
  case "$OUT" in *"$4"*) ;; *) fail "$1" "reason lacks '$4': $OUT" ;; esac
}
expect_silence() { # CASE PROJECT COMMAND
  guard "$1" "$2" "$3"
  [ "$RC" = 0 ] && [ -z "$OUT" ] || fail "$1" "expected silence for '$3', got exit $RC: $OUT"
}
toolchain() { # dir command-cell: a TOOLCHAIN.md whose one row has the given Command cell
  mkdir -p "$1/.claude/knowledge"
  printf '# Toolchain\n\n| Purpose | Command | Verified | Source | Cost |\n|---------|---------|----------|--------|------|\n| Clean build | %s | yes | README | cheap |\n' "$2" > "$1/.claude/knowledge/TOOLCHAIN.md"
}

p="$(project guard-no-marker)"
expect_silence guard-no-marker "$p" 'git push --force origin x'

p="$(project guard)"; marker "$p" bug_fix_g_2026-10-20 "5 Implement"; status "$p" bug_fix_g_2026-10-20 "# Status: g"
expect_deny guard-force-push "$p" 'git push --force origin x' 'force push'
expect_deny guard-force-push-short "$p" 'git push -f origin x' 'force push'
expect_deny guard-force-push-lease "$p" 'git push --force-with-lease origin x' 'force push'
expect_deny guard-force-push-plus "$p" 'git push origin +main' 'force push'
expect_deny guard-pkill "$p" 'pkill -f node' 'by name or pattern'
expect_deny guard-killall "$p" 'killall node' 'by name or pattern'
expect_deny guard-kill-pgrep "$p" 'kill $(pgrep -f node)' 'by name or pattern'
expect_deny guard-xargs-kill "$p" 'pgrep -f node | xargs kill -9' 'by name or pattern'
expect_deny guard-kill-all "$p" 'kill -9 -1' 'by name or pattern'
expect_deny guard-kill-group "$p" 'kill 0' 'by name or pattern'
expect_deny guard-rm-glob "$p" 'rm -rf ./out/*' 'recursive rm'
expect_deny guard-rm-home "$p" 'rm -rf ~/x' 'recursive rm'
expect_deny guard-rm-dotdot "$p" 'rm -rf ../x' 'recursive rm'
expect_deny guard-rm-root "$p" 'rm -r /' 'recursive rm'
expect_deny guard-rm-top "$p" 'rm -rf /usr' 'recursive rm'
expect_deny guard-rm-dot "$p" 'rm -fr .' 'recursive rm'
expect_deny guard-rm-flag-last "$p" 'rm ./out/* -rf' 'recursive rm'
expect_deny guard-git-clean "$p" 'git clean -fd' 'git clean'
expect_deny guard-reset-hard "$p" 'git reset --hard HEAD~1' 'uncommitted work'
expect_deny guard-checkout-dashdash "$p" 'git checkout -- src/a.cs' 'uncommitted work'
expect_deny guard-restore "$p" 'git restore src/a.cs' 'uncommitted work'
expect_deny guard-restore-staged-worktree "$p" 'git restore --staged --worktree src/a.cs' 'uncommitted work'
expect_deny guard-restore-staged-w "$p" 'git restore -W --staged src/a.cs' 'uncommitted work'
expect_deny guard-chained "$p" 'cd src && git push --force' 'force push'
expect_deny guard-newline "$p" 'echo start
rm -rf ./out/*' 'recursive rm'
expect_deny guard-quoted "$p" 'rm -rf "./out/"*' 'recursive rm'
n="$(printf '%s' "$OUT" | tr -cd '"' | wc -c)"
[ $((n % 2)) -eq 0 ] || fail guard-quoted "odd number of double quotes in output"

expect_silence guard-allowed-rm-marker "$p" 'rm -f .dream-team-tracking/.team-mode'
expect_silence guard-allowed-rm-dir "$p" 'rm -rf ./build-out'
expect_silence guard-allowed-rm-deep "$p" 'rm -rf /tmp/dt-build'
expect_silence guard-allowed-push "$p" 'git push origin feature'
expect_silence guard-allowed-restore-staged "$p" 'git restore --staged src/a.cs'
expect_silence guard-allowed-stash "$p" 'git stash'
expect_silence guard-allowed-clean-dry "$p" 'git clean -n'
expect_silence guard-allowed-kill-pid "$p" 'kill 12345'
expect_silence guard-allowed-kill-signal "$p" 'kill -1 12345'
expect_silence guard-allowed-checkout "$p" 'git checkout -b feature'

# the TOOLCHAIN.md exemption: the whole command equals a Command cell, with the
# backticks around the whole cell stripped once; never a prefix or a substring
p="$(project toolchain-row-exempt)"; marker "$p" bug_fix_t_2026-10-20 "5 Implement"; status "$p" bug_fix_t_2026-10-20 "# Status: t"
toolchain "$p" '`rm -rf ./build/*`'
expect_silence toolchain-row-exempt "$p" 'rm -rf ./build/*'
expect_deny toolchain-other-glob "$p" 'rm -rf ./out/*' 'recursive rm'

p="$(project toolchain-row-with-backticks)"; marker "$p" bug_fix_b_2026-10-20 "5 Implement"; status "$p" bug_fix_b_2026-10-20 "# Status: b"
toolchain "$p" '`rm -rf ./build/*` && npm run build'
expect_silence toolchain-row-with-backticks "$p" '`rm -rf ./build/*` && npm run build'
expect_deny toolchain-row-part-not-exempt "$p" 'rm -rf ./build/*' 'recursive rm'

p="$(project toolchain-prefix-not-exempt)"; marker "$p" bug_fix_p_2026-10-20 "5 Implement"; status "$p" bug_fix_p_2026-10-20 "# Status: p"
toolchain "$p" '`rm -rf ./build`'
expect_deny toolchain-prefix-not-exempt "$p" 'rm -rf ./build /' 'recursive rm'

p="$(project toolchain-escapes)"; marker "$p" bug_fix_e_2026-10-20 "5 Implement"; status "$p" bug_fix_e_2026-10-20 "# Status: e"
toolchain "$p" '`rm -rf "./tmp dir"/* && echo "a\b"`'
expect_silence toolchain-escapes "$p" 'rm -rf "./tmp dir"/* && echo "a\b"'
expect_deny toolchain-escapes-differs "$p" 'rm -rf "./tmp dir"/* && echo "a\c"' 'recursive rm'

# the launcher reaches the guard, and so does the snippet's command run from the project root
p="$(project guard-launcher)"; marker "$p" bug_fix_k_2026-10-20 "5 Implement"; status "$p" bug_fix_k_2026-10-20 "# Status: k"
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | CLAUDE_PROJECT_DIR="$p" bash "$LAUNCHER" guard-command 2>&1)"
case "$OUT" in *'"permissionDecision": "deny"'*'force push'*) ;; *) fail guard-launcher "launcher output: $OUT" ;; esac
GUARD_CMD="$(sed -n 's/^[[:space:]]*"command": "\(.*guard-command\)",$/\1/p' "$ROOT/hooks/settings-snippet.json" | head -1)"
[ -n "$GUARD_CMD" ] || fail guard-snippet "no guard-command entry in settings-snippet.json"
mkdir -p "$p/.claude/hooks"; cp "$ROOT/hooks/run-hook.cmd" "$GUARD" "$p/.claude/hooks/" 2>/dev/null
OUT="$(cd "$p" && printf '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | env -u CLAUDE_PROJECT_DIR bash -c "$GUARD_CMD" 2>&1)"
case "$OUT" in *'"permissionDecision": "deny"'*) ;; *) fail guard-snippet "snippet guard command under bash: $OUT" ;; esac

# the Copilot edition's copy: the same patterns and exemption, the project as
# the working directory, its knowledge under .github/dream-team/, both deny forms
COPY="$ROOT/copilot/files/dream-team/hooks/guard-command"
body() { sed -n '/^payload=/,/^  done < "\$TOOLCHAIN"/p' "$1" | tr -d '\r'; }
[ -n "$(body "$GUARD")" ] && [ "$(body "$GUARD")" = "$(body "$COPY")" ] \
  || fail guard-copilot-drift "the patterns or the exemption differ between hooks/guard-command and its Copilot copy"
copy_guard() { # PROJECT COMMAND -> OUT, RC
  OUT="$(cd "$1" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(json_string "$2")" | env -u CLAUDE_PROJECT_DIR bash "$COPY" 2>&1)"; RC=$?
}
p="$(project guard-copilot)"
copy_guard "$p" 'git push --force'
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-no-marker "expected silence, got exit $RC: $OUT"
marker "$p" bug_fix_c_2026-10-20 "5 Implement"; status "$p" bug_fix_c_2026-10-20 "# Status: c"
copy_guard "$p" 'git push --force'
case "$OUT" in '{"permissionDecision":"deny","permissionDecisionReason":"'*'force push'*'"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"'*) ;; *) fail guard-copilot-deny "exit $RC: $OUT" ;; esac
mkdir -p "$p/.github/dream-team/knowledge"
printf '| Purpose | Command |\n|---|---|\n| Clean | `rm -rf ./build/*` |\n' > "$p/.github/dream-team/knowledge/TOOLCHAIN.md"
copy_guard "$p" 'rm -rf ./build/*'
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-toolchain "expected silence, got exit $RC: $OUT"

# the Copilot entry's commands fail open: the CLI denies the call when a
# pre-tool hook exits non-zero, so a missing or crashing script must exit 0
CONFIG="$ROOT/copilot/files/hooks/dream-team.json"
entry_cmd() { # field -> the PreToolUse entry's command string, JSON-unescaped
  sed -n '/"PreToolUse"/,$p' "$CONFIG" | sed -n "s/^[[:space:]]*\"$1\": \"\\(.*\\)\",\$/\\1/p" | head -1 | sed 's/\\"/"/g'
}
COPILOT_BASH="$(entry_cmd bash)"
[ -n "$COPILOT_BASH" ] || fail guard-copilot-entry "no bash command in the PreToolUse entry of dream-team.json"
copilot_entry() { # PROJECT RUNNER... -> OUT, RC: the entry's command run from the project root
  local dir="$1"; shift
  OUT="$(cd "$dir" && printf '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | env -u CLAUDE_PROJECT_DIR "$@" 2>&1)"; RC=$?
}
p="$(project guard-copilot-entry)"; marker "$p" bug_fix_m_2026-10-20 "5 Implement"; status "$p" bug_fix_m_2026-10-20 "# Status: m"
copilot_entry "$p" bash -c "$COPILOT_BASH"
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-entry-missing "bash entry, no script: expected exit 0 and silence, got exit $RC: $OUT"
mkdir -p "$p/.github/dream-team/hooks"
printf '#!/usr/bin/env bash\nexit 3\n' > "$p/.github/dream-team/hooks/guard-command"
copilot_entry "$p" bash -c "$COPILOT_BASH"
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-entry-crash "bash entry, failing script: expected exit 0 and silence, got exit $RC: $OUT"
cp "$COPY" "$p/.github/dream-team/hooks/guard-command"
copilot_entry "$p" bash -c "$COPILOT_BASH"
case "$RC:$OUT" in 0:*'"permissionDecision":"deny"'*) ;; *) fail guard-copilot-entry-bash "bash entry, real script: exit $RC: $OUT" ;; esac
if command -v powershell.exe >/dev/null 2>&1; then
  COPILOT_PS="$(entry_cmd powershell)"
  [ -n "$COPILOT_PS" ] || fail guard-copilot-entry "no powershell command in the PreToolUse entry of dream-team.json"
  copilot_entry "$p" powershell.exe -NoProfile -NonInteractive -Command "$COPILOT_PS"
  [ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-entry-ps-missing "PowerShell entry, no launcher: expected exit 0 and silence, got exit $RC: $OUT"
  printf 'throw "broken"\n' > "$p/.github/dream-team/hooks/guard-command.ps1"
  copilot_entry "$p" powershell.exe -NoProfile -NonInteractive -Command "$COPILOT_PS"
  [ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-entry-ps-crash "PowerShell entry, failing launcher: expected exit 0 and silence, got exit $RC: $OUT"
  cp "$ROOT/copilot/files/dream-team/hooks/guard-command.ps1" "$p/.github/dream-team/hooks/"
  copilot_entry "$p" powershell.exe -NoProfile -NonInteractive -Command "$COPILOT_PS"
  case "$RC:$OUT" in 0:*'"permissionDecision":"deny"'*) ;; *) fail guard-copilot-entry-ps "PowerShell entry, real launcher: exit $RC: $OUT" ;; esac
  # a non-ASCII path must reach bash intact: re-encoded as "?" it reads as a glob
  # and an allowed rm is denied. The name is built from octal escapes so this
  # file stays ASCII.
  name="$(printf 'caf\303\251-d\303\274n')"
  OUT="$(cd "$p" && printf '{"tool_name":"Bash","tool_input":{"command":"rm -r ./%s"}}' "$name" \
    | env -u CLAUDE_PROJECT_DIR powershell.exe -NoProfile -NonInteractive -Command "$COPILOT_PS" 2>&1)"; RC=$?
  [ "$RC" = 0 ] && [ -z "$OUT" ] || fail guard-copilot-entry-ps-utf8 "PowerShell entry, non-ASCII path in an allowed rm: expected silence, got exit $RC: $OUT"
fi

[ "$fails" -eq 0 ] && echo "hook: ok"
exit $(( fails > 0 ))
