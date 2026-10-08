#!/usr/bin/env bash
# Dream Team — client for the optional decision-routing service
# (Jev, TypeSafe AI). See team-manifest.json → services.
#
#   jev-decide.sh <question-set> <state-file>   ask one question set
#   jev-decide.sh probe [provider]              check a provider's key and endpoint
#
# Prints the service's JSON response on success and nothing otherwise, and
# always exits 0. The team reads silence as "no answer" and carries on exactly
# as it would without the service, so nothing here may stop a run.
#
# Jev is reachable directly or through a provider that relays it; the manifest
# lists each provider's endpoint, model id and credential variable. Nothing
# leaves the machine unless all of these hold:
#   - The last "jev=" line of .dream-team-tracking/.service-consent is
#     "jev=granted <provider> <date>", written by /team-setup fix after the
#     user agreed to that provider. A line without a provider, the shape
#     written before providers existed, means the manifest's defaultProvider.
#     probe is exempt: it sends a fixed word and no user data.
#   - That provider is declared in the manifest, with an https endpoint.
#   - That provider's credential variable is set. The team never writes it.
#   - The question set exists as templates/jev/<name>.json.
# What is sent is the state file's text and that question set, nothing else.
# The key reaches curl on stdin, never on a command line, and goes only to its
# own provider's endpoint: nothing in the environment can redirect it.
set -uo pipefail

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
MAX_STATE_CHARS=8000

command -v curl >/dev/null 2>&1 || exit 0
manifest="$(tr -d '\r' 2>/dev/null < "$TEAM_ROOT/team-manifest.json")" || exit 0
[ "$(printf '%s\n' "$manifest" | grep -c '"providers"[[:space:]]*:')" = 1 ] || exit 0

# One value per key, or nothing is sent.
one_value() { [ "$(printf '%s\n' "$1" | grep -c .)" = 1 ] && printf '%s' "$1"; }

manifest_value() {
  one_value "$(printf '%s\n' "$manifest" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | sed 's/.*"\([^"]*\)"$/\1/')"
}

# A string field of one provider's object inside "providers".
provider_value() {
  one_value "$(printf '%s\n' "$manifest" | awk -v p="$1" -v k="$2" '
    /"providers"[[:space:]]*:[[:space:]]*\{/ { inp = 1; next }
    inp && !inb && $0 ~ "^[[:space:]]*\"" p "\"[[:space:]]*:[[:space:]]*[{]" { inb = 1; next }
    inb && /^[[:space:]]*}/ { exit }
    inb && $0 ~ "^[[:space:]]*\"" k "\"[[:space:]]*:[[:space:]]*\"" {
      v = $0; sub(/^[^:]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*,?[[:space:]]*$/, "", v); print v
    }')"
}

escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

default_provider="$(manifest_value defaultProvider)"

if [ "${1:-}" = probe ]; then
  provider="${2:-$default_provider}"
  state="probe"
  questions='{"probe":{"type":"noul","instructions":"Is this text the single word probe?"}}'
else
  set_name="${1:-}"
  state_file="${2:-}"
  case "$set_name" in ''|*[!a-z_]*) exit 0 ;; esac
  qfile="$TEAM_ROOT/templates/jev/$set_name.json"
  [ -f "$qfile" ] && [ -f "$state_file" ] || exit 0

  consent_line="$(tr -d '\r' 2>/dev/null < "$PROJECT_DIR/.dream-team-tracking/.service-consent" \
    | grep -E '^jev=' | tail -1)"
  read -r consent_state consent_provider _ <<< "$consent_line"
  [ "${consent_state:-}" = jev=granted ] || exit 0
  case "${consent_provider:-}" in
    ''|*[!a-z]*) provider="$default_provider" ;;
    *) provider="$consent_provider" ;;
  esac

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

case "$provider" in ''|*[!a-z]*) exit 0 ;; esac
endpoint="$(provider_value "$provider" endpoint)"
model="$(provider_value "$provider" model)"
credential="$(provider_value "$provider" credential)"
[ -n "$model" ] || exit 0
case "$endpoint" in https://?*) ;; *) exit 0 ;; esac
case "$credential" in ''|[0-9]*|*[!A-Z0-9_]*) exit 0 ;; esac
key="${!credential:-}"
[ -n "$key" ] || exit 0

tmp="$(mktemp -d 2>/dev/null)" || exit 0
trap 'rm -rf "$tmp"' EXIT

printf '{"model":"%s","state":"%s","questions":%s}' \
  "$model" "$(escape_for_json "$state")" "$questions" > "$tmp/body.json"

code="$(printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$key" \
  | curl -sS --max-time 3 -o "$tmp/out.json" -w '%{http_code}' -X POST -H @- \
      --data-binary "@$tmp/body.json" "$endpoint" 2>/dev/null)"

[ "$code" = 200 ] && [ -s "$tmp/out.json" ] && cat "$tmp/out.json"
exit 0
