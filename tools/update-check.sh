#!/usr/bin/env bash
# Dream Team — optional check for a newer version of the team itself.
# See team-manifest.json → updateCheck.
#
#   update-check.sh                prints "<local> <latest>" when a newer
#                                  version exists and was not skipped
#   update-check.sh skip <X.Y.Z>   stops mentioning that version
#   update-check.sh probe          fetches now, ignoring the cache, and
#                                  prints the remote version
#
# Prints nothing otherwise, and always exits 0. The team reads silence as
# "nothing to say" and carries on, so nothing here may stop a run.
#
# What leaves the machine: one HTTPS GET of the manifest's updateCheck.source,
# a public file. No body, no custom header, nothing from the project. Nothing
# is fetched unless the last "update-check=" line of
# .claude-tracking/.service-consent is "update-check=granted <date>", written
# by /team-setup fix after the user agreed. skip sends nothing.
#
# The cache, .claude-tracking/.update-check, holds checked=<epoch seconds>,
# latest=<version> and skipped=<version>. A fetch happens at most once per
# updateCheck.intervalHours whether it succeeded or not, so an offline machine
# pays the timeout once per interval, not once per run.
set -uo pipefail

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 0
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
TRACKING="$PROJECT_DIR/.claude-tracking"
CACHE="$TRACKING/.update-check"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

is_version() { [[ ${1:-} =~ $VERSION_RE ]]; }

# One value per key, or nothing.
one_value() { [ "$(printf '%s\n' "$1" | grep -c .)" = 1 ] && printf '%s' "$1"; }

# The single "version" value in a manifest's text, or nothing.
version_of() {
  local v
  v="$(one_value "$(printf '%s\n' "$1" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed 's/.*"\([^"]*\)"$/\1/')")"
  is_version "$v" && printf '%s' "$v"
}

# The last value of a cache key, or nothing.
cache_value() {
  [ -f "$CACHE" ] || return 0
  tr -d '\r' 2>/dev/null < "$CACHE" | grep -a "^$1=" | tail -1 | cut -d= -f2-
}

write_cache() {
  {
    [ -n "$1" ] && printf 'checked=%s\n' "$1"
    [ -n "$2" ] && printf 'latest=%s\n' "$2"
    [ -n "$3" ] && printf 'skipped=%s\n' "$3"
    :
  } 2>/dev/null > "$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
  rm -f "$CACHE.tmp" 2>/dev/null
}

consented() {
  local line state _
  line="$(tr -d '\r' 2>/dev/null < "$TRACKING/.service-consent" | grep '^update-check=' | tail -1)"
  read -r state _ <<< "$line"
  [ "${state:-}" = update-check=granted ]
}

# Is version $1 greater than version $2? Both already validated.
newer() {
  local IFS=. a b i
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  for i in 0 1 2; do
    (( 10#${a[i]} > 10#${b[i]} )) && return 0
    (( 10#${a[i]} < 10#${b[i]} )) && return 1
  done
  return 1
}

fetch() {
  command -v curl >/dev/null 2>&1 || return 0
  local body
  body="$(curl -fsS --max-time 3 "$source" 2>/dev/null)" || return 0
  version_of "$body"
}

manifest="$(tr -d '\r' 2>/dev/null < "$TEAM_ROOT/team-manifest.json")" || exit 0
local_version="$(version_of "$manifest")"
source="$(one_value "$(printf '%s\n' "$manifest" \
  | grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')")"
interval="$(one_value "$(printf '%s\n' "$manifest" \
  | grep -o '"intervalHours"[[:space:]]*:[[:space:]]*[0-9][0-9]*' | sed 's/.*[^0-9]//')")"
[ -n "$local_version" ] && [ -n "$interval" ] || exit 0
case "$source" in https://?*) ;; *) exit 0 ;; esac

checked="$(cache_value checked)"
[[ $checked =~ ^[0-9]+$ ]] || checked=""
latest="$(cache_value latest)"
is_version "$latest" || latest=""
skipped="$(cache_value skipped)"
is_version "$skipped" || skipped=""

case "${1:-}" in
  skip)
    is_version "${2:-}" && write_cache "$checked" "$latest" "$2"
    exit 0 ;;
  probe)
    consented || exit 0
    fetched="$(fetch)"
    write_cache "$(date +%s)" "${fetched:-$latest}" "$skipped"
    [ -n "$fetched" ] && printf '%s\n' "$fetched"
    exit 0 ;;
  '') ;;
  *) exit 0 ;;
esac

consented || exit 0
now="$(date +%s)"
if [ -z "$checked" ] || [ "$checked" -gt "$now" ] || [ $(( now - checked )) -ge $(( interval * 3600 )) ]; then
  fetched="$(fetch)"
  [ -n "$fetched" ] && latest="$fetched"
  write_cache "$now" "$latest" "$skipped"
fi

if [ -n "$latest" ] && [ "$latest" != "$skipped" ] && newer "$latest" "$local_version"; then
  printf '%s %s\n' "$local_version" "$latest"
fi
exit 0
