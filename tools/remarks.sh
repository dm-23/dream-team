#!/usr/bin/env bash
# Dream Team — copies accepted remarks into the remarks dir (proposals/) and
# lists the remarks of a directory that are not accepted yet. The remarks dir
# is whatever `tools/knowledge-dir.sh remarks` prints. No git operation is ever
# performed: nothing is staged, committed or pushed, and no file but the target
# is touched.
#
#   bash <team-root>/tools/remarks.sh <command> ...     (from the project root)
#
#   accept <file> [<file> ...]   each <file> is a project-root-relative regular
#                                file named *.md, not a symbolic link, with no
#                                .. segment. All sources are validated before
#                                the first write; a bad one is exit 2 and
#                                nothing is written. For each source, in
#                                argument order, one line on stdout:
#                                  added: <remarks dir>/<name>
#                                    copied byte for byte (cp, then cmp),
#                                    creating the remarks dir when absent;
#                                  already there: <remarks dir>/<name>
#                                    a file of that name has the same bytes.
#                                <name> is the base name with -<hash6> before
#                                .md, <hash6> the first six characters of
#                                `git hash-object` of the content; a base name
#                                that already ends in -<hash6> of its own
#                                content is kept. A target of that name with
#                                other bytes is exit 2.
#   pending <dir>                the project-root-relative path of every *.md
#                                directly inside <dir> whose <name> is not a
#                                file in the remarks dir, sorted, one per line.
#                                A missing <dir> prints nothing.
#
# Exit 0 = done. 2 = a bad command, source or directory, or a failed write.
set -uo pipefail
export LC_ALL=C

die() { echo "remarks: $*" >&2; exit 2; }
usage() { die "usage: remarks.sh accept <file> [<file> ...] | pending <dir>"; }

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  accept) [ "$#" -ge 1 ] || usage ;;
  pending) [ "$#" -eq 1 ] || usage ;;
  *) usage ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
[ -f "$TEAM_ROOT/team-manifest.json" ] || die "no team-manifest.json in the team root"

RD=""
IFS= read -r RD < <(bash "$TEAM_ROOT/tools/knowledge-dir.sh" remarks | tr -d '\r')
[ -n "$RD" ] || die "the remarks dir could not be resolved"
RD="${RD%/}"

# has_dotdot <path>: true when a path segment is ..
has_dotdot() {
  case "/$1/" in */../*) return 0 ;; esac
  return 1
}

# target_name <file>: prints the name the file gets in the remarks dir.
target_name() {
  local base stem h
  base="${1##*/}"
  stem="${base%.md}"
  h=""
  IFS= read -r h < <(git hash-object --no-filters -- "$1" | tr -d '\r')
  [ -n "$h" ] || return 1
  h="${h:0:6}"
  case "$stem" in
    *"-$h") printf '%s\n' "$base" ;;
    *) printf '%s-%s.md\n' "$stem" "$h" ;;
  esac
}

if [ "$cmd" = accept ]; then
  names=()
  for f in "$@"; do
    [ -n "$f" ] || die "empty source"
    case "$f" in /*|?:*) die "$f: not project-root-relative" ;; esac
    has_dotdot "$f" && die "$f: a .. segment is not allowed"
    case "$f" in *.md) ;; *) die "$f: not a *.md file" ;; esac
    [ -L "$f" ] && die "$f: a symbolic link"
    [ -f "$f" ] || die "$f: not a regular file"
    name=""
    IFS= read -r name < <(target_name "$f") || true
    [ -n "$name" ] || die "$f: could not hash"
    if [ -e "$RD/$name" ] && ! cmp -s -- "$f" "$RD/$name"; then
      die "$name exists with other content"
    fi
    names+=("$name")
  done
  i=0
  for f in "$@"; do
    name="${names[$i]}"
    i=$((i + 1))
    if [ -f "$RD/$name" ]; then
      echo "already there: $RD/$name"
      continue
    fi
    mkdir -p "$RD" || die "could not create $RD"
    cp -- "$f" "$RD/$name" || die "could not copy $f"
    cmp -s -- "$f" "$RD/$name" || die "$name: the copy differs from the source"
    echo "added: $RD/$name"
  done
  exit 0
fi

# pending
d="${1%/}"
[ -n "$d" ] || die "empty directory"
case "$d" in /*|?:*) die "$d: not project-root-relative" ;; esac
has_dotdot "$d" && die "$d: a .. segment is not allowed"
[ -d "$d" ] || exit 0
list=""
for f in "$d"/*.md; do
  [ -L "$f" ] && continue
  [ -f "$f" ] || continue
  name=""
  IFS= read -r name < <(target_name "$f") || true
  [ -n "$name" ] || die "$f: could not hash"
  [ -f "$RD/$name" ] || list="$list$f"$'\n'
done
[ -z "$list" ] || printf '%s' "$list" | sort
exit 0
