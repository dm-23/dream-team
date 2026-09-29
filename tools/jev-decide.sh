#!/usr/bin/env bash
# Dream Team — client for the optional decision-routing service
# (Jev, TypeSafe AI). See team-manifest.json → services.
#
#   jev-decide.sh <question-set> <state-file>   ask one question set
#   jev-decide.sh probe                         check the key and the endpoint
#
# Prints the service's JSON response on success and nothing otherwise, and
# always exits 0. The team reads silence as "no answer" and carries on exactly
# as it would without the service, so nothing here may stop a run.
#
# Nothing leaves the machine unless all of these hold:
#   - TYPESAFE_API_KEY is set. The team never writes it anywhere.
#   - .claude-tracking/.service-consent carries the line "jev=granted ...",
#     written by /team-setup fix after the user agreed. probe is exempt: it
#     sends a fixed word and no user data.
#   - The question set exists as templates/jev/<name>.json.
# What is sent is the state file's text and that question set, nothing else.
# The key reaches curl on stdin, never on a command line, and goes only to the
# manifest's endpoint over https: nothing in the environment can redirect it.
set -uo pipefail

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
MAX_STATE_CHARS=8000

[ -n "${TYPESAFE_API_KEY:-}" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# One value per key in the manifest, or nothing is sent.
manifest_value() {
  local v
  v="$(grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$TEAM_ROOT/team-manifest.json" 2>/dev/null \
    | sed 's/.*"\([^"]*\)"$/\1/')"
  [ "$(printf '%s\n' "$v" | grep -c .)" = 1 ] && printf '%s' "$v"
}
model="$(manifest_value pinnedModel)"
endpoint="$(manifest_value endpoint)"
[ -n "$model" ] || exit 0
case "$endpoint" in https://?*) ;; *) exit 0 ;; esac

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

if [ "${1:-}" = probe ]; then
  state="probe"
  questions='{"probe":{"type":"noul","instructions":"Is this text the single word probe?"}}'
else
  set_name="${1:-}"
  state_file="${2:-}"
  case "$set_name" in ''|*[!a-z_]*) exit 0 ;; esac
  qfile="$TEAM_ROOT/templates/jev/$set_name.json"
  [ -f "$qfile" ] && [ -f "$state_file" ] || exit 0
  tr -d '\r' 2>/dev/null < "$PROJECT_DIR/.claude-tracking/.service-consent" \
    | grep -qE '^jev=granted([[:space:]]|$)' || exit 0
  questions="$(tr -d '\r' 2>/dev/null < "$qfile")"
  # Control characters other than tab and newline are dropped; CR goes with
  # them. Bytes that are not valid UTF-8 would make the body invalid JSON, so
  # they are dropped too where iconv exists.
  state="$(tr -d '\000-\010\013-\037' 2>/dev/null < "$state_file")"
  if command -v iconv >/dev/null 2>&1; then
    state="$(printf '%s' "$state" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)"
  fi
  state="$( { LC_ALL=C.UTF-8; printf '%s' "${state:0:$MAX_STATE_CHARS}"; } 2>/dev/null )"
  [ -n "$state" ] || exit 0
fi

tmp="$(mktemp -d 2>/dev/null)" || exit 0
trap 'rm -rf "$tmp"' EXIT

printf '{"model":"%s","state":"%s","questions":%s}' \
  "$model" "$(escape_for_json "$state")" "$questions" > "$tmp/body.json"

code="$(printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$TYPESAFE_API_KEY" \
  | curl -sS --max-time 3 -o "$tmp/out.json" -w '%{http_code}' -X POST -H @- \
      --data-binary "@$tmp/body.json" "$endpoint" 2>/dev/null)"

[ "$code" = 200 ] && [ -s "$tmp/out.json" ] && cat "$tmp/out.json"
exit 0
