#!/usr/bin/env bash
# Installs or updates the GitHub Copilot edition of the team in a project.
#
#   bash copilot/install.sh <project-dir> [--dry-run] [--force]
#
# Builds the edition from this repository (build.sh), compares it with the
# project and with the project's ownership record, prints the plan, and only
# then writes. It replaces the team's own files and nothing else: knowledge,
# learnings, CAPABILITIES.md, run state, consent records, git configuration
# and every file it did not install are never written, moved or deleted.
#
#   add              absent in the project               written
#   unchanged        identical to the build              left alone (adopted into the record)
#   update           ours, untouched since installed     replaced
#   modified         ours, edited by hand                refused; --force backs it up and replaces it
#   conflict         present, not ours                   refused, always
#   remove           ours, no longer shipped, untouched  deleted
#   orphan-modified  ours, no longer shipped, edited     kept, reported
#
# Every write and delete is also checked against a fixed allowlist, so a
# broken rule or a hand-edited record can never reach project state.
#
# Exit 0 = installed (or planned, with --dry-run). 1 = refused: the build
# failed, a foreign file is in the way, or a team file was edited by hand.
# 2 = usage or internal error.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
bs=$'\x5c'
RECORD=".github/dream-team/.installed"
project="" dry=0 force=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --force) force=1 ;;
    -*) echo "install: unknown option $a" >&2; exit 2 ;;
    *) [ -z "$project" ] || { echo "install: one project directory only" >&2; exit 2; }; project="$a" ;;
  esac
done
[ -n "$project" ] || { echo "usage: install.sh <project-dir> [--dry-run] [--force]" >&2; exit 2; }
P="$(cd "$project" 2>/dev/null && pwd)" || { echo "install: $project is not a directory" >&2; exit 2; }
git -C "$P" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || echo "install: warning: $P is not a git work tree" >&2

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT
B="$TMP/out"
bash "$HERE/build.sh" "$B" > "$TMP/build.log" \
  || { echo "install: build failed; $P was not touched" >&2; exit 1; }
M="$B/.github/dream-team/team-manifest.json"

hash_of() { # via stdin: native git.exe mishandles some characters in path arguments
  local h
  h="$(git hash-object --stdin < "$1")" && [ -n "$h" ] \
    || { echo "install: could not hash $1" >&2; return 1; }
  printf '%s\n' "$h"
}
list_of() { # $1 = array name, $2 = manifest; top-level array → one value per line
  awk -v k="$1" 'index($0, "  \"" k "\": [") == 1 { f = 1; next }
    f && /^  \]/ { exit }
    f { gsub(/[",[:space:]]/, ""); if ($0 != "") print }' "$2"
}
AGENTS=" $(list_of agents "$M" | tr '\n' ' ') "
SKILLS=" $(list_of skills "$M" | tr '\n' ' ') "
VERSION="$(sed -n 's/^    "version": "\([^"]*\)".*/\1/p' "$M" | head -1)"
[ -n "$VERSION" ] && [ "$AGENTS" != "  " ] && [ "$SKILLS" != "  " ] \
  || { echo "install: internal error: the built manifest has no version, agents or skills" >&2; exit 2; }
# Record-side paths may also name roles and skills the installed version shipped.
AGENTS_REC="$AGENTS" SKILLS_REC="$SKILLS"
IM="$P/.github/dream-team/team-manifest.json"
if [ -f "$IM" ]; then
  AGENTS_REC="$AGENTS $(list_of agents "$IM" | tr '\n' ' ') "
  SKILLS_REC="$SKILLS $(list_of skills "$IM" | tr '\n' ' ') "
fi

allowed() { # $1 = relative path, $2 = "rec" to accept names from the installed manifest too
  local agents="$AGENTS" skills="$SKILLS" seg rest="$1" lp="${1,,}"
  [ "${2:-}" = rec ] && { agents="$AGENTS_REC"; skills="$SKILLS_REC"; }
  agents="${agents,,}" skills="${skills,,}"
  # Shape: every segment is plain [A-Za-z0-9._-]+, never "." or "..". No empty
  # segments, backslashes, "~" (8.3 short names), spaces or globs.
  while :; do
    seg="${rest%%/*}"
    [[ $seg =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    case "$seg" in .|..) return 1 ;; esac
    [ "$seg" = "$rest" ] && break
    rest="${rest#*/}"
  done
  # The file system may be case-insensitive: compare lowercased.
  case "$lp" in
    .github/dream-team/knowledge|.github/dream-team/knowledge/*|"${RECORD,,}") return 1 ;;
    .github/dream-team/*|.github/hooks/dream-team.json) return 0 ;;
    .github/agents/*.agent.md)
      local a="${lp#.github/agents/}"; a="${a%.agent.md}"; [ -n "$a" ] && [[ $agents == *" $a "* ]] ;;
    .github/skills/*/*)
      local s="${lp#.github/skills/}"; s="${s%%/*}"; [ -n "$s" ] && [[ $skills == *" $s "* ]] ;;
    *) return 1 ;;
  esac
}

# The record without its header: "hash path" per line.
if [ -f "$P/$RECORD" ]; then tr -d '\r' < "$P/$RECORD" | grep -v '^#' | grep -v '^$' > "$TMP/record"
else : > "$TMP/record"; fi
rec_hash() { awk -v p="$1" '$2 == p { print $1; exit }' "$TMP/record"; }

# --- plan -------------------------------------------------------------------
(cd "$B" && find . -type f | sed 's|^\./||' | sort) > "$TMP/new"
: > "$TMP/plan"
while IFS= read -r p; do
  allowed "$p" || { echo "install: internal error: the build produced $p, outside the team's paths" >&2; exit 2; }
  cur="$P/$p"
  if [ ! -e "$cur" ]; then st=add
  elif [ ! -f "$cur" ]; then st=conflict
  else
    hc="$(hash_of "$cur")" || exit 2; hn="$(hash_of "$B/$p")" || exit 2; hr="$(rec_hash "$p")"
    if [ "$hc" = "$hn" ]; then st=unchanged
    elif [ -z "$hr" ]; then st=conflict
    elif [ "$hc" = "$hr" ]; then st=update
    else st=modified; fi
  fi
  printf '%s %s\n' "$st" "$p" >> "$TMP/plan"
done < "$TMP/new"
while IFS=' ' read -r hr p; do
  grep -qxF -- "$p" "$TMP/new" && continue
  allowed "$p" rec || { echo "install: internal error: $RECORD names $p, outside the team's paths; remove that line and run again" >&2; exit 2; }
  [ -f "$P/$p" ] || continue
  hc="$(hash_of "$P/$p")" || exit 2
  if [ "$hc" = "$hr" ]; then st=remove; else st=orphan-modified; fi
  printf '%s %s\n' "$st" "$p" >> "$TMP/plan"
done < "$TMP/record"

count() { grep -c "^$1 " "$TMP/plan"; }
grep -v '^unchanged ' "$TMP/plan"
echo "Dream Team $VERSION for GitHub Copilot → $P"
for s in add update unchanged remove modified orphan-modified conflict; do echo "  $s $(count "$s")"; done

if [ "$(count conflict)" -gt 0 ]; then
  echo "install: refused — these paths hold files the team did not install. Rename or remove them, then run again:" >&2
  sed -n 's/^conflict /  /p' "$TMP/plan" >&2; exit 1
fi
if [ "$(count modified)" -gt 0 ] && [ "$force" = 0 ]; then
  echo "install: refused — these team files were edited by hand. Run again with --force to back them up and replace them:" >&2
  sed -n 's/^modified /  /p' "$TMP/plan" >&2; exit 1
fi
[ "$dry" = 0 ] || { echo "install: dry run; nothing was written"; exit 0; }

# --- apply ------------------------------------------------------------------
STAMP="$(date +%Y%m%d-%H%M%S)"
write_file() {
  mkdir -p "$(dirname "$P/$1")" && cp "$B/$1" "$P/$1" \
    || { echo "install: could not write $1; run again to finish" >&2; exit 2; }
  case "$1" in .github/dream-team/tools/*|.github/dream-team/checks/*|.github/dream-team/hooks/*) chmod +x "$P/$1" ;; esac
}
while IFS=' ' read -r st p; do
  case "$st" in
    add|update) write_file "$p" ;;
    modified)
      bk="$P/.dream-team-tracking/install-backup-$STAMP/$p"
      mkdir -p "$(dirname "$bk")" && cp "$P/$p" "$bk" \
        || { echo "install: could not back up $p; stopped before replacing it" >&2; exit 2; }
      write_file "$p" ;;
    remove)
      rm -f "$P/$p"; d="$(dirname "$p")"
      while case "${d,,}" in .|.github|.github/agents|.github/skills|.github/hooks|.github/dream-team|*"$bs"*) false ;; *) true ;; esac && rmdir "$P/$d" 2>/dev/null; do d="$(dirname "$d")"; done ;;
  esac
done < "$TMP/plan"

{
  echo "# dream-team $VERSION"
  while IFS= read -r p; do h="$(hash_of "$B/$p")" || exit 2; printf '%s %s\n' "$h" "$p"; done < "$TMP/new"
  sed -n 's/^orphan-modified //p' "$TMP/plan" | while IFS= read -r p; do printf '%s %s\n' "$(rec_hash "$p")" "$p"; done
} > "$TMP/record.new"
cmp -s "$TMP/record.new" "$P/$RECORD" 2>/dev/null || cp "$TMP/record.new" "$P/$RECORD"

[ "$(count modified)" = 0 ] || echo "Edited files were backed up to .dream-team-tracking/install-backup-$STAMP/"
[ "$(count orphan-modified)" = 0 ] || echo "Kept, because they were edited: files this version no longer ships (orphan-modified above). Delete them when you no longer need them."
cat <<'EOF'
Next:
  1. Reopen VS Code, or restart the Copilot CLI, so the new agents and commands load.
  2. In VS Code, turn on the chat.useHooks setting (hooks are a preview feature).
  3. Run /team-setup fix.
  4. Run /generate-knowledge if this project has no knowledge yet.
EOF
