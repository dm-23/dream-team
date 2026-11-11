#!/usr/bin/env bash
# Dream Team — the deterministic part of a knowledge refresh: moves the working
# copy onto a branch of its own, and turns what the generator wrote into one
# commit that touches only the committed project knowledge. Run by the lead
# (or a pipeline) on the checked-out release branch, through
# /generate-knowledge refresh. See team-manifest.json → knowledge.refresh.
#
#   bash <team-root>/tools/knowledge-refresh.sh begin                         (from the project root)
#   bash <team-root>/tools/knowledge-refresh.sh finish [--message-file <file>]
#   bash <team-root>/tools/knowledge-refresh.sh abort
#
# The knowledge dir is the resolver's project dir (knowledge.resolver). The
# run's state lives in <tracking.dir>/.knowledge-refresh, three lines:
# branch=<release branch>, base=<40 hex>, work=<work branch>.
#
# begin
#   Refuses with exit 1, changing nothing, when: a state file exists (a
#   refresh is in progress); nothing is tracked under the knowledge dir (the
#   first generation does not use this tool); HEAD is detached;
#   git status --porcelain -- <knowledge dir> prints anything (untracked files
#   included); the run marker (hooks.marker) exists without a state=closed
#   line; the work branch exists already. Otherwise records branch and base
#   (HEAD), runs git switch -c knowledge/refresh-<slug>-<YYYYMMDD-HHmm> at the
#   same commit, where <slug> is the branch name with every run of characters
#   other than letters, digits, "." and "-" turned into one "-", and prints
#     refresh: on <work> from <branch> at <short sha>
#     baseline: <short commit of BASELINE | none>
#     branch line: same | <BASELINE's branch> → <branch> | new
#   The switch keeps every product change in place: modified, staged,
#   untracked.
#
# finish
#   On the work branch only. Writes <knowledge dir>/<knowledge.baselineFile>
#   with LF endings: commit=<base>, date=<committer date of base, YYYY-MM-DD>,
#   branch=<branch>. Runs checks/verify-knowledge-shape.sh and
#   checks/verify-knowledge-neutral.sh of the team root on the knowledge dir;
#   when one fails, prints their lines and exits 1 (2 when one could not
#   read), staying on the work branch with nothing committed. Then
#   git add -A -- <knowledge dir> and git commit -- <knowledge dir> with the
#   subject "knowledge: refresh <branch> to <short base>" and, with
#   --message-file, the file's text as the body: the pathspec keeps anything
#   staged elsewhere out of the commit. A refresh that changed nothing but
#   BASELINE still commits: the baseline moved. Then git switch <branch>,
#   which puts back the branch's own knowledge and carries every product
#   change over, removes the state file and prints
#     refresh: committed <short sha> on <work>
#     push: git push -u origin <work>
#     pull request: <work> → <branch>; knowledge only
#
# abort
#   On the work branch only. git restore --source=<base> --staged --worktree
#   and git clean -fdq on the knowledge dir, git switch <branch>,
#   git branch -D <work>, and removes the state file. Product changes stay.
#
# Never contacts a remote and never pushes: no object is fetched lazily in a
# partial clone (GIT_NO_LAZY_FETCH, and protocol.allow=never for git older
# than 2.44) and no credential prompt can stall the run (GIT_TERMINAL_PROMPT).
#
# Exit 0 = done. 1 = refused (see above; finish and abort: no state file, not
# on the work branch; finish: a check found defects). 2 = a bad argument, no
# repository or manifest, or a git step that failed.
set -uo pipefail
export LC_ALL=C
export GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0
# Git Bash would rewrite an argument such as <ref>:<path> as a Windows path.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
# Every git call: no transport is allowed.
lgit() { git -c protocol.allow=never "$@"; }
# A path native git reads from an argument (the conversion above is off).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

die() { echo "refresh: $*" >&2; exit 2; }
refuse() { echo "refresh: $*" >&2; exit 1; }
usage() { die "usage: knowledge-refresh.sh begin | finish [--message-file <file>] | abort"; }

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
MSGFILE=""
case "$cmd" in
  begin|abort) [ "$#" -eq 0 ] || usage ;;
  finish)
    case "$#" in
      0) ;;
      2) [ "$1" = "--message-file" ] && [ -n "$2" ] || usage; MSGFILE="$2" ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || die "no team-manifest.json in the team root"

# The string value of a key placed directly inside a top-level block.
value_in() {
  tr -d '\r' < "$M" | awk -v b="$1" -v k="$2" '
    index($0, "  \"" b "\": {") == 1 { f = 1; next }
    f && /^  }/ { exit }
    f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
}
need() { # <block> <key>
  local v
  v="$(value_in "$1" "$2")"
  [ -n "$v" ] || die "$1.$2 is missing from the manifest; update the team"
  printf '%s' "${v%/}"
}
TRACK="$(need tracking dir)" || exit 2
MARKER="$(need hooks marker)" || exit 2
BASELINE_NAME="$(need knowledge baselineFile)" || exit 2
STATE="$TRACK/.knowledge-refresh"

[ "$(lgit rev-parse --is-inside-work-tree 2>/dev/null | tr -d '\r')" = true ] || die "not inside a git working tree"
KD="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" project 2>/dev/null | tr -d '\r')"
[ -n "$KD" ] || die "the knowledge dir cannot be resolved (tools/knowledge-dir.sh project)"
KD="${KD%/}"
BASELINE="$KD/$BASELINE_NAME"

current_branch() { lgit symbolic-ref -q --short HEAD 2>/dev/null | tr -d '\r'; }

# Reads the state file into S_BRANCH, S_BASE, S_WORK; refuses without one.
read_state() {
  S_BRANCH="" S_BASE="" S_WORK=""
  [ -f "$STATE" ] || refuse "no refresh in progress ($STATE does not exist); run begin first"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      branch=*) S_BRANCH="${line#branch=}" ;;
      base=*) S_BASE="${line#base=}" ;;
      work=*) S_WORK="${line#work=}" ;;
    esac
  done < "$STATE"
  case "$S_BASE" in *[!0-9a-f]*) S_BASE="" ;; esac
  [ "${#S_BASE}" -eq 40 ] && [ -n "$S_BRANCH" ] && [ -n "$S_WORK" ] \
    || die "$STATE is not a refresh state (branch=, base=, work=); remove it by hand"
  [ "$(current_branch)" = "$S_WORK" ] \
    || refuse "this refresh runs on $S_WORK, but HEAD is $(current_branch || true); switch to $S_WORK and run it again, or remove $STATE by hand"
}

# --- begin ----------------------------------------------------------------------
if [ "$cmd" = begin ]; then
  [ ! -e "$STATE" ] || refuse "a refresh is in progress ($STATE exists); finish or abort it first"
  [ -n "$(lgit ls-files -- "$KD" 2>/dev/null | head -n 1)" ] \
    || refuse "nothing is tracked under $KD; the first generation writes the knowledge without this tool"
  BRANCH="$(current_branch)"
  [ -n "$BRANCH" ] || refuse "HEAD is detached; check out the release branch first"
  ST="$(lgit status --porcelain -- "$KD" 2>/dev/null)" || die "git status failed on $KD"
  [ -z "$ST" ] || refuse "$KD has uncommitted changes; commit or discard them first:
$ST"
  if [ -f "$MARKER" ]; then
    tr -d '\r' < "$MARKER" | grep -qx 'state=closed' \
      || refuse "a team run is open ($MARKER has no state=closed line); close it first"
  fi
  BASE="$(lgit rev-parse --verify -q HEAD 2>/dev/null | tr -d '\r')"
  [ "${#BASE}" -eq 40 ] || die "HEAD does not name a commit"
  SLUG="$(printf '%s' "$BRANCH" | sed -E 's/[^A-Za-z0-9.-]+/-/g')"
  WORKB="knowledge/refresh-$SLUG-$(date +%Y%m%d-%H%M)"
  lgit check-ref-format --branch "$WORKB" >/dev/null 2>&1 || die "$WORKB is not a valid branch name"
  ! lgit show-ref --verify -q "refs/heads/$WORKB" \
    || refuse "branch $WORKB exists already; delete it or wait a minute"

  # What BASELINE says before the refresh.
  B_SHA="" B_BRANCH="" have_baseline=0
  if [ -f "$BASELINE" ]; then
    have_baseline=1
    first=1
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      if [ "$first" = 1 ]; then line="${line#$'\xEF\xBB\xBF'}"; first=0; fi
      case "$line" in
        commit=*) [ -n "$B_SHA" ] || B_SHA="${line#commit=}" ;;
        branch=*) [ -n "$B_BRANCH" ] || B_BRANCH="${line#branch=}" ;;
      esac
    done < "$BASELINE"
  fi

  mkdir -p "$TRACK" 2>/dev/null || die "cannot create $TRACK"
  printf 'branch=%s\nbase=%s\nwork=%s\n' "$BRANCH" "$BASE" "$WORKB" > "$STATE" \
    || die "cannot write $STATE"
  if ! lgit switch -q -c "$WORKB" >/dev/null 2>"$STATE.err"; then
    cat "$STATE.err" >&2; rm -f "$STATE" "$STATE.err"
    die "git switch -c $WORKB failed; nothing changed"
  fi
  rm -f "$STATE.err"

  printf 'refresh: on %s from %s at %s\n' "$WORKB" "$BRANCH" "$(lgit rev-parse --short "$BASE" | tr -d '\r')"
  if [ -n "$B_SHA" ]; then
    printf 'baseline: %s\n' "${B_SHA:0:7}"
  else
    echo "baseline: none"
  fi
  if [ "$have_baseline" = 0 ] || [ -z "$B_BRANCH" ]; then
    echo "branch line: new"
  elif [ "$B_BRANCH" = "$BRANCH" ]; then
    echo "branch line: same"
  else
    printf 'branch line: %s → %s\n' "$B_BRANCH" "$BRANCH"
  fi
  exit 0
fi

# --- finish -----------------------------------------------------------------------
if [ "$cmd" = finish ]; then
  read_state
  if [ -n "$MSGFILE" ]; then
    [ -f "$MSGFILE" ] && [ -r "$MSGFILE" ] || die "cannot read the message file: $MSGFILE"
  fi
  TMP="$(mktemp -d)" || die "no temporary directory"
  trap 'rm -rf "$TMP"' EXIT

  DATE="$(lgit log -1 --format=%cs "$S_BASE" 2>/dev/null | tr -d '\r')"
  case "$DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "the committer date of $S_BASE cannot be read" ;;
  esac
  mkdir -p "$KD" || die "cannot create $KD"
  printf 'commit=%s\ndate=%s\nbranch=%s\n' "$S_BASE" "$DATE" "$S_BRANCH" > "$BASELINE" \
    || die "cannot write $BASELINE"

  bash "$TEAM_ROOT/checks/verify-knowledge-shape.sh" "$KD" > "$TMP/shape" 2>&1; rs=$?
  bash "$TEAM_ROOT/checks/verify-knowledge-neutral.sh" "$KD" > "$TMP/neutral" 2>&1; rn=$?
  if [ "$rs" -ne 0 ] || [ "$rn" -ne 0 ]; then
    [ "$rs" -eq 0 ] || cat "$TMP/shape"
    [ "$rn" -eq 0 ] || cat "$TMP/neutral"
    echo "refresh: nothing committed; still on $S_WORK. Fix the knowledge and run finish again, or abort."
    if [ "$rs" -ge 2 ] || [ "$rn" -ge 2 ]; then exit 2; fi
    exit 1
  fi

  SHORT_BASE="$(lgit rev-parse --short "$S_BASE" | tr -d '\r')"
  {
    printf 'knowledge: refresh %s to %s\n' "$S_BRANCH" "$SHORT_BASE"
    if [ -n "$MSGFILE" ]; then
      printf '\n'
      tr -d '\r' < "$MSGFILE"
    fi
  } > "$TMP/message" || die "cannot write the commit message"
  lgit add -A -- "$KD" || die "git add failed on $KD; nothing committed, still on $S_WORK"
  lgit commit -q --cleanup=whitespace -F "$(native "$TMP/message")" -- "$KD" \
    || die "git commit failed; nothing committed, still on $S_WORK"
  SHA="$(lgit rev-parse --short HEAD | tr -d '\r')"
  rm -f "$STATE"
  # The work branch differs from the release branch only under the knowledge
  # dir, so the switch rewrites that dir to the branch's version and carries
  # every other change over.
  lgit switch -q "$S_BRANCH" \
    || die "committed $SHA on $S_WORK, but git switch $S_BRANCH failed; switch back by hand"
  printf 'refresh: committed %s on %s\n' "$SHA" "$S_WORK"
  printf 'push: git push -u origin %s\n' "$S_WORK"
  printf 'pull request: %s → %s; knowledge only\n' "$S_WORK" "$S_BRANCH"
  exit 0
fi

# --- abort ------------------------------------------------------------------------
read_state
lgit restore --source="$S_BASE" --staged --worktree -- "$KD" \
  || die "git restore of $KD from $S_BASE failed; still on $S_WORK"
lgit clean -fdq -- "$KD" || die "git clean of $KD failed; still on $S_WORK"
lgit switch -q "$S_BRANCH" || die "git switch $S_BRANCH failed; still on $S_WORK"
lgit branch -q -D "$S_WORK" || die "git branch -D $S_WORK failed; delete it by hand"
rm -f "$STATE"
printf 'refresh: aborted; back on %s, %s deleted\n' "$S_BRANCH" "$S_WORK"
exit 0
