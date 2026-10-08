#!/usr/bin/env bash
# Exercises hooks/team-mode-prompt against scratch project directories.
#
#   verify-hook.sh     (run from anywhere; it locates the team root from its own path)
#
# Each case builds a throwaway project, feeds the hook a UserPromptSubmit
# payload on stdin with CLAUDE_PROJECT_DIR pointing at it, and asserts on the
# text the hook prints. No JSON parser: the assertions are greps on the exact
# strings the skill and the harness depend on. Exit 0 = every case passed,
# 1 = at least one failed; each failure names its case.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/team-mode-prompt"
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
case "$OUT" in *TEAM-MODE-ACTIVE*) fail legacy "active block without a marker: $OUT" ;; esac
run legacy-slash "$p" '"/team fix the thing"'
case "$OUT" in *TEAM-LEGACY-STATE*) ;; *) fail legacy-slash "legacy block must survive a slash prompt: $OUT" ;; esac
marker "$p" bug_fix_w_2026-10-08 "2 Research"; status "$p" bug_fix_w_2026-10-08 "# Status: w"
run legacy-open "$p" '"hello"'
case "$OUT" in *TEAM-LEGACY-STATE*TEAM-MODE-ACTIVE*) ;; *) fail legacy-open "expected legacy then active: $OUT" ;; esac

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
run_deployed inbox-old "$p" '"/team fix the crash"'
[ -z "$OUT" ] || fail inbox-old "expected silence on exit 2: $OUT"

[ "$fails" -eq 0 ] && echo "hook: ok"
exit $(( fails > 0 ))
