#!/usr/bin/env bash
# Dream Team — normalises the first line of status.md files closed in old prose.
#
#   normalize-status.sh [--dry-run] [tracking-dir]
#   (run from the project root; the default is .dream-team-tracking)
#
# Teams before 4.1.0 closed a run with `**[DONE — 2026-08-14]** result`,
# `# [Analyze] Complete — result` or `[DONE]` later in the heading. The hook
# and the preflight read those as closed since 4.5.0, but every tool that
# parses the first line is simpler when it reads `[DONE] YYYY-MM-DD — result`.
# For every <tracking-dir>/*/status.md whose first line does not start with
# `[DONE] ` and contains `[DONE]`, `[DONE —` or `Complete —`, the first line becomes
#
#   [DONE] <date> — <rest>
#
# <date> is the first YYYY-MM-DD in the first line, else the value of the
# file's `**Closed:**` line, else the file's modification date. <rest> is the
# first line without its leading `#` and `*` markers, without the matched
# token (`[DONE]`, `[DONE — date]`, `[DONE —`, `Complete —`) and the `**`
# around it, spaces collapsed, trimmed. The file's line endings are kept:
# the first line keeps its CR when it had one, and every other byte of the
# file is written back as it was.
#
# --dry-run prints `would normalize <path>: <new first line>` per file and
# writes nothing. Without it, `normalized <path>` per file. A file that is
# already normal, an open run, a directory without status.md and anything
# else in the tracking directory are skipped silently. Always exits 0; a
# file that cannot be read or written is skipped, never a reason to stop
# the setup that runs this.
set -uo pipefail

dry=0
dir=""
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    *) dir="$a" ;;
  esac
done
[ -n "$dir" ] || dir=".dream-team-tracking"
[ -d "$dir" ] || exit 0

DATE_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}'

for f in "$dir"/*/status.md; do
  [ -f "$f" ] || continue
  # read, not $(head -1): command substitution drops a trailing CR on this platform
  raw=""; IFS= read -r raw < "$f" 2>/dev/null || [ -n "$raw" ] || continue
  cr=""
  case "$raw" in *$'\r') cr=$'\r' ;; esac
  line="${raw%$'\r'}"
  # The closing tokens, whole: a bare "[DONE" inside a word (a link, a list name) is not one.
  case "$line" in
    '[DONE] '*) continue ;;
    *'[DONE]'*|*'[DONE —'*|*'Complete —'*) ;;
    *) continue ;;
  esac

  date="$(printf '%s' "$line" | grep -oE "$DATE_RE" | head -1)"
  if [ -z "$date" ]; then
    date="$(tr -d '\r' < "$f" | sed -n 's/^\*\*Closed:\*\*[[:space:]]*//p' | head -1 | grep -oE "^$DATE_RE")"
  fi
  if [ -z "$date" ]; then
    date="$(date -r "$f" +%F 2>/dev/null)" || date="$(date +%F)"
  fi

  rest="$(printf '%s' "$line" \
    | sed -E 's/^[#* ]+//' \
    | sed -E 's/\[DONE( — [0-9-]+)?\]?( —)?//; s/Complete —//' \
    | sed -E 's/\*\*//g' \
    | tr -s ' ' \
    | sed -E 's/^[[:space:]—]+//; s/[[:space:]—]+$//')"
  new="[DONE] $date — $rest"

  if [ "$dry" = 1 ]; then
    printf 'would normalize %s: %s\n' "$f" "$new"
    continue
  fi
  tmp="$f.tmp"
  { printf '%s%s\n' "$new" "$cr"; tail -n +2 "$f"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; continue; }
  printf 'normalized %s\n' "$f"
done
exit 0
