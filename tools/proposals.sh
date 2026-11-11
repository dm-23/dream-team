#!/usr/bin/env bash
# Dream Team — turns chosen entries of a developer's learnings inbox into
# remarks for the whole team: one file per remark under
# <knowledge.dir>/<knowledge.proposalsDir>/, in one new commit on a new branch
# based on the release branch. Only the lead's refresh turns remarks into
# knowledge. See team-manifest.json → knowledge.proposals.
#
#   bash <team-root>/tools/proposals.sh submit [--dry-run] --branch <release-branch> <name> ...
#   bash <team-root>/tools/proposals.sh status [<name> ...]
#                                                      (from the project root)
#
# A <name> is an inbox name, learnings/<file>.md, as tools/inbox.sh prints it.
# This tool reads the entries through the resolver's operative dir itself
# (knowledge.resolver) and never prints that dir's path.
#
# submit
#   Base: refs/remotes/origin/<branch> when it resolves, else
#   refs/heads/<branch>; neither is exit 1. A base with nothing under
#   knowledge.dir is exit 1. An entry that is missing, is not *.md or already
#   carries a [SUBMITTED line is exit 1, all of them listed, nothing written.
#   Each remark's target is <knowledge.dir>/<proposalsDir>/<entry file name>;
#   a target the base holds with the same bytes is skipped as already
#   proposed, one with other bytes moves to the first free -2, -3 ... name.
#   The commit is built with git plumbing in a temporary index, so the working
#   tree, the index, HEAD and the current branch are never touched: the base
#   tree, plus one blob per remark holding the entry's bytes exactly (no
#   filter, so CRLF stays CRLF). Message "knowledge(proposals): <N> remarks",
#   then one body line per target file name. The branch
#   knowledge/proposals-<YYYYMMDD-HHmmss> is created at the commit; only then
#   each submitted entry gets one appended line, in its own line ending,
#   through tools/inbox.sh append:
#     [SUBMITTED YYYY-MM-DD] <new branch> as <target file name>
#   Prints a "skipped: <name>: already proposed as <file>" line per skipped
#   remark, then
#     proposals: <N> remarks committed as <short sha> on <new branch> (base <base>)
#     push: git push -u origin <new branch>
#     pull request: <new branch> → <branch>; one commit, only files under <dir>/
#   or, when every remark is skipped, "proposals: nothing to commit; every
#   remark is already proposed in <base>". --dry-run prints the same lines
#   prefixed "would: " (the first without "as <short sha>") and writes nothing:
#   no object, no branch, no entry.
#
# status
#   For each entry (no name: every entry of the inbox) that carries a
#   [SUBMITTED line, one line "<file name>\t<state>[\t<reason>]": "in force"
#   when HEAD's tree holds the target under the proposals dir; "closed" when a
#   commit reachable from HEAD deleted it, the reason being that commit's
#   first body line naming the target file, when it has one; else "pending".
#
# Never contacts a remote and never pushes: no object is fetched lazily in a
# partial clone (GIT_NO_LAZY_FETCH, and protocol.allow=never for git older
# than 2.44) and no credential prompt can stall the run (GIT_TERMINAL_PROMPT).
#
# Exit 0 = done (status: every named entry found). 1 = refused: no such
# branch, no committed knowledge, an entry missing, not *.md or already
# submitted; status: a named entry missing. 2 = a bad command, name or
# argument, no repository, no configured git identity, a branch that exists
# already, or a failed read or write.
set -uo pipefail
export LC_ALL=C
export GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0
# Git Bash would rewrite an argument such as <ref>:<path> as a Windows path
# list; every path this tool hands git is native already (see native()).
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

die() { echo "proposals: $*" >&2; exit 2; }
usage() { die "usage: proposals.sh submit [--dry-run] --branch <release-branch> <name> ... | status [<name> ...]"; }

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  submit|status) ;;
  *) usage ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || die "no team-manifest.json in the team root"

# The string value of a key placed directly inside the knowledge block.
value_in() {
  tr -d '\r' < "$M" | awk -v k="$1" '
    index($0, "  \"knowledge\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
}
KDIR="$(value_in dir)"; KDIR="${KDIR%/}"
PDIR="$(value_in proposalsDir)"; PDIR="${PDIR%/}"
[ -n "$KDIR" ] || die "knowledge.dir is missing from the manifest; update the team"
[ -n "$PDIR" ] || die "knowledge.proposalsDir is missing from the manifest; update the team"

OP="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" operative 2>/dev/null | tr -d '\r')" || die "the operative dir could not be resolved"
[ -n "$OP" ] || die "the operative dir could not be resolved"
OP="${OP%/}"

[ "$(git rev-parse --is-inside-work-tree 2>/dev/null | tr -d '\r')" = true ] || die "not inside a git working tree"
TOP="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[ -n "$TOP" ] || die "the repository root could not be found"
PREFIX="$(git rev-parse --show-prefix 2>/dev/null | tr -d '\r')"
# Repository-root paths: the project may be a subdirectory of the repository.
KPATH="$PREFIX$KDIR"
PPATH="$KPATH/$PDIR"
# Every git call runs at the repository root with no transport allowed.
rgit() { git -C "$TOP" -c protocol.allow=never "$@"; }

TMP="$(mktemp -d)" || die "no temporary directory"
trap 'rm -rf "$TMP"' EXIT
# A path native git reads from an argument or from the environment.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# check_name <name>: an inbox entry name, learnings/<file>, <file> without / or
# \; anything else is exit 2. Whether <file> ends in .md is checked with the
# entries, so it is listed with the other refusals.
check_name() {
  local n
  case "$1" in learnings/?*) ;; *) die "bad name '$1': learnings/<file>.md" ;; esac
  n="${1#learnings/}"
  case "$n" in .md|*/*|*\\*|*$'\n'*|*$'\r'*) die "bad name '$1': learnings/<file>.md" ;; esac
}
# Whether a file carries a [SUBMITTED line.
submitted() { { tr -d '\r' < "$1"; } 2>/dev/null | grep -q -E '^[[:space:]]*(- )?\[SUBMITTED '; }
# Whether a file holds a CR directly before an LF.
has_crlf() { od -An -v -tx1 "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | grep -q ' 0d 0a'; }

# --- status -----------------------------------------------------------------------
if [ "$cmd" = status ]; then
  NAMES=()
  if [ "$#" -gt 0 ]; then
    for n in "$@"; do check_name "$n"; NAMES+=("$n"); done
  elif [ -d "$OP/learnings" ]; then
    for f in "$OP"/learnings/*.md; do
      [ -f "$f" ] && NAMES+=("learnings/${f##*/}")
    done
  fi
  missing=0
  for n in ${NAMES[@]+"${NAMES[@]}"}; do
    f="$OP/$n"; file="${n#learnings/}"
    if [ ! -f "$f" ]; then
      echo "proposals: $n: missing" >&2
      missing=1
      continue
    fi
    line="$({ tr -d '\r' < "$f"; } 2>/dev/null | grep -E '^[[:space:]]*(- )?\[SUBMITTED ' | tail -n 1)"
    [ -n "$line" ] || continue
    target="${line##* as }"
    target="${target%"${target##*[![:space:]]}"}"
    case "$target" in
      "$line"|''|*/*|*\\*) printf '%s\tpending\tthe [SUBMITTED line names no target file\n' "$file"; continue ;;
    esac
    path="$PPATH/$target"
    if rgit cat-file -e "HEAD:$path" 2>/dev/null; then
      printf '%s\tin force\n' "$file"
      continue
    fi
    c="$(rgit log -1 --diff-filter=D --format=%h HEAD -- ":(literal)$path" 2>/dev/null | tr -d '\r')"
    if [ -n "$c" ]; then
      reason="$(rgit log -1 --format=%b "$c" 2>/dev/null | tr -d '\r' | grep -F -- "$target" | head -n 1)"
      if [ -n "$reason" ]; then
        printf '%s\tclosed\t%s\n' "$file" "$reason"
      else
        printf '%s\tclosed\n' "$file"
      fi
      continue
    fi
    printf '%s\tpending\n' "$file"
  done
  exit "$missing"
fi

# --- submit: arguments --------------------------------------------------------------
DRY=0 BRANCH="" NAMES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --branch) [ "$#" -ge 2 ] || usage; BRANCH="$2"; shift 2 ;;
    --*) usage ;;
    *) NAMES+=("$1"); shift ;;
  esac
done
[ -n "$BRANCH" ] || usage
[ "${#NAMES[@]}" -gt 0 ] || usage
git check-ref-format "refs/heads/$BRANCH" >/dev/null 2>&1 || die "bad branch name '$BRANCH'"
for n in "${NAMES[@]}"; do check_name "$n"; done
dups="$(printf '%s\n' "${NAMES[@]}" | sort | uniq -d | head -n 1)"
[ -z "$dups" ] || die "$dups is named twice"

# --- the base -----------------------------------------------------------------------
BASE="" BASESHA=""
for r in "refs/remotes/origin/$BRANCH" "refs/heads/$BRANCH"; do
  s="$(rgit rev-parse -q --verify "$r^{commit}" 2>/dev/null | tr -d '\r')"
  if [ -n "$s" ]; then BASE="$r"; BASESHA="$s"; break; fi
done
if [ -z "$BASE" ]; then
  echo "proposals: no local ref for $BRANCH" >&2
  exit 1
fi
rgit ls-tree -r --name-only "$BASESHA" -- "$KPATH" > "$TMP/ktree" 2>/dev/null || die "the tree of $BASE could not be read"
if [ ! -s "$TMP/ktree" ]; then
  echo "proposals: $BRANCH has no committed knowledge (nothing under $KPATH/ in $BASE)" >&2
  exit 1
fi

# --- the entries ----------------------------------------------------------------------
: > "$TMP/refused"
for n in "${NAMES[@]}"; do
  f="$OP/$n"
  if [ ! -f "$f" ]; then echo "  $n: missing" >> "$TMP/refused"
  elif [ "${n%.md}" = "$n" ]; then echo "  $n: not an entry (*.md)" >> "$TMP/refused"
  elif [ ! -r "$f" ]; then echo "  $n: unreadable" >> "$TMP/refused"
  elif submitted "$f"; then echo "  $n: submitted already (it carries a [SUBMITTED line)" >> "$TMP/refused"
  fi
done
if [ -s "$TMP/refused" ]; then
  { echo "proposals: refused, nothing written:"; cat "$TMP/refused"; } >&2
  exit 1
fi

# --- identity and the branch name -----------------------------------------------------
{ rgit var GIT_AUTHOR_IDENT && rgit var GIT_COMMITTER_IDENT; } >/dev/null 2>&1 \
  || die "no git identity is configured: set user.name and user.email, then run again"
STAMP="$(date +%Y%m%d-%H%M%S)"
TODAY="${STAMP:0:4}-${STAMP:4:2}-${STAMP:6:2}"
NEWB="knowledge/proposals-$STAMP"
if rgit rev-parse -q --verify "refs/heads/$NEWB" >/dev/null 2>&1; then
  die "the branch $NEWB exists already; run again in a second"
fi

# --- targets ------------------------------------------------------------------------------
# Each entry's bytes are read once, into a snapshot that is hashed and
# committed, so the blob is exactly what was compared.
: > "$TMP/plan"; : > "$TMP/taken"; : > "$TMP/skipped"
i=0
for n in "${NAMES[@]}"; do
  i=$((i + 1))
  { cat "$OP/$n" > "$TMP/e$i"; } 2>/dev/null || die "$n could not be read"
  blob="$(rgit hash-object --no-filters --stdin < "$TMP/e$i" 2>/dev/null | tr -d '\r')"
  [ -n "$blob" ] || die "$n could not be hashed"
  file="${n#learnings/}"; stem="${file%.md}"
  cand="$file"; k=1; target=""
  while :; do
    if ! grep -qxF -- "$cand" "$TMP/taken"; then
      have="$(rgit rev-parse -q --verify "$BASESHA:$PPATH/$cand" 2>/dev/null | tr -d '\r')"
      if [ -z "$have" ]; then target="$cand"; break; fi
      if [ "$have" = "$blob" ]; then
        printf 'skipped: %s: already proposed as %s\n' "$n" "$cand" >> "$TMP/skipped"
        break
      fi
    fi
    k=$((k + 1))
    [ "$k" -le 999 ] || die "no free name for $file under $PPATH/"
    cand="$stem-$k.md"
  done
  if [ -n "$target" ]; then
    printf '%s\n' "$target" >> "$TMP/taken"
    printf '%s\t%s\t%s\t%s\n' "$i" "$n" "$blob" "$target" >> "$TMP/plan"
  fi
done
N="$(wc -l < "$TMP/plan" | tr -d ' ')"

W=""; [ "$DRY" = 1 ] && W="would: "
while IFS= read -r l; do printf '%s%s\n' "$W" "$l"; done < "$TMP/skipped"
if [ "$N" -eq 0 ]; then
  printf '%sproposals: nothing to commit; every remark is already proposed in %s\n' "$W" "$BASE"
  exit 0
fi
PUSH="push: git push -u origin $NEWB"
PR="pull request: $NEWB → $BRANCH; one commit, only files under $PPATH/"
if [ "$DRY" = 1 ]; then
  printf 'would: proposals: %s remarks committed on %s (base %s)\n' "$N" "$NEWB" "$BASE"
  printf 'would: %s\n' "$PUSH" "$PR"
  exit 0
fi

# --- the commit ---------------------------------------------------------------------------
IDX="$(native "$TMP/index")"
MSG="$TMP/message"
{
  printf 'knowledge(proposals): %s remarks\n\n' "$N"
  cut -f4 "$TMP/plan"
} > "$MSG"
GIT_INDEX_FILE="$IDX" rgit read-tree "$BASESHA" 2>/dev/null || die "the tree of $BASE could not be read"
while IFS="$(printf '\t')" read -r i n blob target; do
  w="$(rgit hash-object -w --no-filters --stdin < "$TMP/e$i" 2>/dev/null | tr -d '\r')"
  [ "$w" = "$blob" ] || die "$n could not be written to the object store"
  GIT_INDEX_FILE="$IDX" rgit update-index --add --cacheinfo "100644,$blob,$PPATH/$target" 2>/dev/null \
    || die "$n could not be staged in the temporary index"
done < "$TMP/plan"
TREE="$(GIT_INDEX_FILE="$IDX" rgit write-tree 2>/dev/null | tr -d '\r')"
rm -f "$TMP/index" "$TMP/index.lock"
[ -n "$TREE" ] || die "the tree could not be written"
COMMIT="$(rgit commit-tree "$TREE" -p "$BASESHA" -F "$(native "$MSG")" 2>/dev/null | tr -d '\r')"
[ -n "$COMMIT" ] || die "the commit could not be written (is a git identity configured?)"
# An empty old value: the ref is created only when it does not exist yet.
rgit update-ref -m "proposals: $N remarks" "refs/heads/$NEWB" "$COMMIT" "" 2>/dev/null \
  || die "the branch $NEWB could not be created (it exists already?); nothing was marked"
SHORT="$(rgit rev-parse --short "$COMMIT" 2>/dev/null | tr -d '\r')"

# --- marking the entries ------------------------------------------------------------------
: > "$TMP/unmarked"
while IFS="$(printf '\t')" read -r i n blob target; do
  if has_crlf "$TMP/e$i"; then eol=$'\r\n'; else eol=$'\n'; fi
  printf '[SUBMITTED %s] %s as %s%s' "$TODAY" "$NEWB" "$target" "$eol" \
    | bash "$TEAM_ROOT/tools/inbox.sh" append "$n" - >/dev/null 2>&1 \
    || printf '  %s: [SUBMITTED %s] %s as %s\n' "$n" "$TODAY" "$NEWB" "$target" >> "$TMP/unmarked"
done < "$TMP/plan"

printf 'proposals: %s remarks committed as %s on %s (base %s)\n' "$N" "$SHORT" "$NEWB" "$BASE"
printf '%s\n' "$PUSH" "$PR"
if [ -s "$TMP/unmarked" ]; then
  { echo "proposals: the branch exists, but these entries could not be marked; append the line to each by hand:"; cat "$TMP/unmarked"; } >&2
  exit 2
fi
exit 0
