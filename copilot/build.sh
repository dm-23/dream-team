#!/usr/bin/env bash
# Builds the GitHub Copilot edition of the team from its Claude Code source.
#
#   bash copilot/build.sh <out-dir> [source-root]
#
# source-root defaults to the repository this script lives in. Its copilot/
# directory supplies the data -- rules.tsv, allow.tsv, overrides/, files/ --
# while the engine (lib/) always comes from beside this script, so check.sh
# can point it at fixture or doctored trees. <out-dir> must not exist; it
# receives the files exactly as they sit in a project: .github/agents,
# .github/skills, .github/hooks and .github/dream-team.
#
# Order matters. Overlays run first, on pristine source text, so a renamed
# heading in the source fails the build instead of slipping through. Rules,
# the agent frontmatter rewrite and the platform note follow. A residual scan
# then fails the build if any Claude Code term survived.
#
# Exit 0 = built and clean. 1 = a step failed; every message names its file,
# and <out-dir> is not left behind. 2 = usage error.
set -uo pipefail

OUT="${1:-}"
[ -n "$OUT" ] || { echo "usage: build.sh <out-dir> [source-root]" >&2; exit 2; }
LIB="$(cd "$(dirname "$0")" && pwd)/lib"
SRC="${2:-$(dirname "$LIB")/..}"
SRC="$(cd "$SRC" 2>/dev/null && pwd)" || { echo "build: no source at ${2:-}" >&2; exit 2; }
CFG="$SRC/copilot"
[ ! -e "$OUT" ] || { echo "build: $OUT already exists" >&2; exit 2; }

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT
errors=0
err() { echo "build: $*" >&2; errors=$((errors + 1)); }
stop_on_errors() {
  [ "$errors" -eq 0 ] && return 0
  echo "build: $errors error(s); nothing was produced" >&2
  rm -rf "$OUT"; exit 1
}

# Scripts a deployment runs. The other checks/ scripts test this repository
# itself and are not installed.
RUNTIME_CHECKS="summarize-routing.sh verify-knowledge-integrity.sh verify-learnings-inbox.sh"
NOTE='The question tool is `vscode/askQuestions` in VS Code and `ask_user` in the Copilot CLI. The subagent tool is `runSubagent` in VS Code and `task` in the Copilot CLI.'
SCAN='AskUserQuestion|Agent tool|Skill tool|Artifact|\.claude/|\.claude-tracking|CLAUDE_PROJECT_DIR|claude plugin|/plugin|Claude Code|\b(opus|sonnet|haiku|fable|mythos)\b|settings\.json|`/hooks`|\$ARGUMENTS|cacheTtl|model: inherit'

# --- 1. collect the sources, as LF text ----------------------------------
FILES=()
add_source() {
  [ -f "$SRC/$1" ] || { err "missing source file $1"; return; }
  mkdir -p "$WORK/$(dirname "$1")"
  tr -d '\r' < "$SRC/$1" > "$WORK/$1"
  FILES+=("$1")
}
while IFS= read -r f; do add_source "$f"; done < <(
  cd "$SRC" && { ls agents/*.md tools/*.sh 2>/dev/null; find skills templates -type f 2>/dev/null; } | sort)
for c in $RUNTIME_CHECKS; do add_source "checks/$c"; done
add_source team-manifest.json
add_source .gitignore
stop_on_errors

target_of() {
  case "$1" in
    agents/*.md) local n="${1#agents/}"; printf '.github/agents/%s.agent.md' "${n%.md}" ;;
    skills/*) printf '.github/%s' "$1" ;;
    *) printf '.github/dream-team/%s' "$1" ;;
  esac
}

# --- 2. overlays ------------------------------------------------------------
apply_overlay() { # work-file overlay-file
  local rel="overrides/${2#$CFG/overrides/}" anchor rc
  anchor="$(head -n 1 "$2" | tr -d '\r')"
  case "$1" in
    */team-manifest.json)
      anchor="$(basename "$2" .json)"
      awk -v key="$anchor" -v ov="$2" -f "$LIB/json-overlay.awk" "$1" > "$1.new"; rc=$? ;;
    *) awk -v anchor="$anchor" -v ov="$2" -f "$LIB/md-overlay.awk" "$1" > "$1.new"; rc=$? ;;
  esac
  case "$rc:$1" in
    0:*) mv "$1.new" "$1"; return ;;
    10:*/team-manifest.json) err "$rel: key not found: $anchor" ;;
    10:*) err "$rel: anchor not found: $anchor" ;;
    11:*) err "$rel: anchor found more than once: $anchor" ;;
    12:*) err "$rel: no closing line for key $anchor" ;;
    13:*) err "$rel: cannot delete the last key $anchor" ;;
    *) err "$rel: overlay failed (awk exit $rc)" ;;
  esac
  rm -f "$1.new"
}
if [ -d "$CFG/overrides" ]; then
  while IFS= read -r ov; do
    rel="${ov#$CFG/overrides/}"; target="${rel%/*}"
    [ -f "$WORK/$target" ] || { err "overrides/$rel: no source file $target"; continue; }
    case "$target" in
      team-manifest.json|*.md) apply_overlay "$WORK/$target" "$ov" ;;
      *) err "overrides/$rel: overlays apply to Markdown files and team-manifest.json only" ;;
    esac
  done < <(find "$CFG/overrides" -type f | sort)
fi
stop_on_errors

# --- 3. literal rules ---------------------------------------------------------
unescape() { # var-name text
  local s="${2//\\n/$'\n'}"
  printf -v "$1" '%s' "${s//\\t/$'\t'}"
}
[ -f "$CFG/rules.tsv" ] || err "missing copilot/rules.tsv"
n=0
while IFS= read -r row || [ -n "$row" ]; do
  n=$((n + 1)); row="${row%$'\r'}"
  case "$row" in ''|'#'*) continue ;; esac
  glob="${row%%$'\t'*}"; rest="${row#*$'\t'}"
  case "$rest" in
    *$'\t'*) ;;
    *) err "rules.tsv:$n: expected file-glob<TAB>from<TAB>to"; continue ;;
  esac
  unescape from "${rest%%$'\t'*}"; unescape to "${rest#*$'\t'}"
  hit=0
  for f in "${FILES[@]}"; do
    [[ $f == $glob ]] || continue
    IFS= read -r -d '' content < "$WORK/$f"
    new="${content//"$from"/"$to"}"
    [ "$new" = "$content" ] && continue
    printf '%s' "$new" > "$WORK/$f"; hit=1
  done
  [ "$hit" = 1 ] || err "rules.tsv:$n matched nothing in $glob: ${from:0:60}"
done < "$CFG/rules.tsv"
stop_on_errors

# --- 4. agent frontmatter and the platform note -------------------------------
for f in "${FILES[@]}"; do
  case "$f" in
    agents/*.md)
      awk -f "$LIB/agent-frontmatter.awk" "$WORK/$f" > "$WORK/$f.new" 2> "$WORK/fm.err"; rc=$?
      case $rc in
        0) mv "$WORK/$f.new" "$WORK/$f" ;;
        4) err "$f: $(cat "$WORK/fm.err")" ;;
        *) err "$f: frontmatter not rewritable (awk exit $rc)" ;;
      esac ;;
  esac
  case "$f" in
    agents/*.md|skills/*/SKILL.md)
      grep -qE 'the question tool|subagent tool|subagent call' "$WORK/$f" || continue
      awk -v note="$NOTE" 'NR == 1 { print; next }
        !done && /^---[ \t]*$/ { print; print ""; print note; done = 1; next }
        { print }' "$WORK/$f" > "$WORK/$f.new" && mv "$WORK/$f.new" "$WORK/$f" ;;
  esac
done
stop_on_errors

# --- 5. place, validate, scan ---------------------------------------------------
mkdir -p "$OUT" || exit 2
for f in "${FILES[@]}"; do
  t="$(target_of "$f")"
  mkdir -p "$OUT/$(dirname "$t")" && cp "$WORK/$f" "$OUT/$t"
done
if [ -d "$CFG/files" ]; then
  while IFS= read -r f; do
    rel="${f#$CFG/files/}"
    case "$rel" in
      hooks/*|dream-team/*) t=".github/$rel" ;;
      *) err "files/$rel: only files/hooks/ and files/dream-team/ are installed"; continue ;;
    esac
    [ ! -e "$OUT/$t" ] || { err "files/$rel collides with a translated file at $t"; continue; }
    mkdir -p "$OUT/$(dirname "$t")" && tr -d '\r' < "$f" > "$OUT/$t"
  done < <(find "$CFG/files" -type f | sort)
fi

json_ok() {
  if command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$1" 2>/dev/null
    return
  fi
  local py
  for py in python3 python py; do
    "$py" -c 'import json' >/dev/null 2>&1 || continue
    "$py" -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" 2>/dev/null
    return
  done
  echo "build: warning: neither node nor python found; JSON not validated" >&2
}
for j in .github/dream-team/team-manifest.json .github/hooks/dream-team.json; do
  [ ! -f "$OUT/$j" ] || json_ok "$OUT/$j" || err "$j is not valid JSON"
done

while IFS= read -r f; do
  rel="${f#$OUT/}"
  IFS= read -r -d '' content < "$f"
  if [ -f "$CFG/allow.tsv" ]; then
    while IFS=$'\t' read -r g s || [ -n "$g" ]; do
      s="${s%$'\r'}"
      case "$g" in ''|'#'*) continue ;; esac
      [[ $rel == $g ]] && content="${content//"$s"/}"
    done < "$CFG/allow.tsv"
  fi
  hits="$(printf '%s' "$content" | grep -nE -- "$SCAN")" || continue
  while IFS= read -r h; do err "residual Claude term in $rel:${h:0:160}"; done <<< "$hits"
done < <(find "$OUT" -type f | sort)
stop_on_errors

echo "build: ${#FILES[@]} translated files in $OUT"
