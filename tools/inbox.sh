#!/usr/bin/env bash
# Dream Team — the one way into the operative dir, which holds the learnings
# inbox: one file per entry under learnings/, plus review-exceptions.md. The
# operative dir may lie outside the project, in the developer's profile, and
# GitHub Copilot refuses or asks about a file tool's path, or a path written
# in a command's text, outside the workspace; it never looks inside a script a
# command runs. So no role, reference or skill names that directory: they call
# this tool, which resolves it (team-manifest.json → knowledge.resolver).
#
#   bash <team-root>/tools/inbox.sh <command> ...     (from the project root)
#
# Names: an entry is learnings/<file>.md, <file> without / or \; the one other
# name is review-exceptions.md. Anything else is exit 2.
# Sources: a regular file under .dream-team-tracking/, project-root-relative,
# with no .. segment; or -, standard input. Bytes are copied exactly.
#
#   where                  the operative dir; then "profile (key <key>)",
#                          "per-copy (<profile disabled | no remote | profile
#                          not created>)" or "legacy (<legacyDir>; run
#                          /team-setup)"; then a note while a LEARNINGS.md is
#                          still there. The only command that prints the dir.
#   index [<dir> ...]      the learnings index (knowledge.learningsIndex) of
#                          learnings/ and of each extra project-relative dir;
#                          an inbox row's File reads learnings/<file>.
#   list                   the entries, sorted, then review-exceptions.md.
#   show <name> ...        "==> <name> <==" and the content of each; a missing
#                          one prints "==> <name> <== (missing)" and makes the
#                          exit 1 once all are shown.
#   add <source> [<name>]  copies into learnings/<name> (default: the source's
#                          file name; <name> may omit "learnings/"); a taken
#                          name gets the first free -2, -3 ... before .md.
#                          Creates learnings/. Prints the final name.
#   append <name> <source> appends; a target that does not end in a newline
#                          first gets one in its own line ending (CRLF when it
#                          holds a CRLF, else LF); into a target holding a
#                          CRLF, every appended line ends in CRLF (a missing
#                          last newline stays missing), else the source's
#                          bytes go as they are. A missing entry is exit 1;
#                          review-exceptions.md is created when absent.
#   put <name> <source>    replaces the whole file, creating it when absent.
#   remove <name> ...      removes each; a missing one is exit 1 at the end.
#   check                  checks/verify-learnings-inbox.sh on the dir.
#   backup <dest>          copies learnings/, review-exceptions.md and an
#                          older LEARNINGS.md, those that exist, into <dest>:
#                          under .dream-team-tracking/, not existing yet.
#                          Prints <dest>.
#   verify-backup <dest>   checks/verify-knowledge-integrity.sh <dest> <dir>
#                          inbox.
#
# Outside where, the operative dir's path never appears in what this tool
# prints: the output of the two checks shows it as <inbox>.
#
# Exit 0 = done. 1 = a missing name or a refused write (a backup destination
# that exists). 2 = a bad command, name or source, or a failed write.
set -uo pipefail
export LC_ALL=C

TRACK=".dream-team-tracking"

die() { echo "inbox: $*" >&2; exit 2; }
usage() { die "usage: inbox.sh where|index|list|show|add|append|put|remove|check|backup|verify-backup ..."; }

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
  where|index|list|show|add|append|put|remove|check|backup|verify-backup) ;;
  *) usage ;;
esac

TEAM_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || exit 2
M="$TEAM_ROOT/team-manifest.json"
[ -f "$M" ] || die "no team-manifest.json in the team root"

OP="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" operative | tr -d '\r')" || die "the operative dir could not be resolved"
[ -n "$OP" ] || die "the operative dir could not be resolved"
OP="${OP%/}"

TMP="$(mktemp -d)" || die "no temporary directory"
trap 'rm -rf "$TMP"' EXIT

# --- validation -----------------------------------------------------------------

# A name the inbox holds: learnings/<file>.md or review-exceptions.md.
valid_name() {
  local n
  case "$1" in
    review-exceptions.md) return 0 ;;
    learnings/*.md)
      n="${1#learnings/}"
      case "$n" in
        .md|*/*|*\\*) return 1 ;;
      esac
      case "$n" in *$'\n'*|*$'\r'*) return 1 ;; esac
      return 0 ;;
  esac
  return 1
}
check_name() { valid_name "$1" || die "bad name '$1': learnings/<file>.md or review-exceptions.md"; }

# A project-relative path under .dream-team-tracking/ with no .. segment.
valid_tracking_path() {
  case "$1" in
    "$TRACK"/?*) ;;
    *) return 1 ;;
  esac
  case "/$1/" in */../*|*/./*) return 1 ;; esac
  case "$1" in *\\*|*$'\n'*|*$'\r'*) return 1 ;; esac
  return 0
}

# check_source <source>: sets SRC to a readable file holding the content;
# standard input is staged first, so its bytes are read once.
check_source() {
  if [ "$1" = "-" ]; then
    SRC="$TMP/stdin"
    cat > "$SRC" || die "standard input could not be read"
    return 0
  fi
  valid_tracking_path "$1" || die "bad source '$1': a file under $TRACK/, project-root-relative, or -"
  [ -f "$1" ] && [ -r "$1" ] || die "source '$1' is not a readable file"
  SRC="$1"
}

# Print a file's output with the operative dir's path shown as <inbox>.
hide() {
  HIDE_OP="$OP" awk '
    BEGIN { p = ENVIRON["HIDE_OP"]; n = length(p) }
    {
      line = $0; out = ""
      if (n > 0) {
        while ((i = index(line, p)) > 0) { out = out substr(line, 1, i - 1) "<inbox>"; line = substr(line, i + n) }
      }
      print out line
    }' "$1"
}

# run_hidden <command...>: its stdout and stderr, path hidden, and its exit.
run_hidden() {
  local rc
  "$@" > "$TMP/o" 2> "$TMP/e"; rc=$?
  hide "$TMP/o"
  hide "$TMP/e" >&2
  return "$rc"
}

# The last byte of a file, as two hex digits, or nothing for an empty file.
last_byte() { tail -c 1 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
# Whether a file holds a CR directly before an LF.
has_crlf() { od -An -v -tx1 "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' ' | grep -q ' 0d 0a'; }

# --- commands -------------------------------------------------------------------

case "$cmd" in
  where)
    [ "$#" -eq 0 ] || usage
    value_in() {
      tr -d '\r' < "$M" | awk -v k="$1" '
        index($0, "  \"knowledge\": {") == 1 { f = 1; next }
        f && /^  }/ { exit }
        f && index($0, "    \"" k "\":") == 1 { sub(/^[^:]*:[ \t]*"/, ""); sub(/".*$/, ""); print; exit }'
    }
    LEGACY="$(value_in legacyDir)"; LEGACY="${LEGACY%/}"
    OPD="$(value_in operativeDir)"; OPD="${OPD%/}"
    PROFILE="$(value_in profileDir)"
    printf '%s\n' "$OP"
    if [ -n "$LEGACY" ] && [ "$OP" = "$LEGACY" ]; then
      printf 'legacy (%s; run /team-setup)\n' "$LEGACY"
    elif [ -z "$PROFILE" ]; then
      echo "per-copy (profile disabled)"
    elif ! KEY="$(bash "$TEAM_ROOT/tools/knowledge-dir.sh" key 2>/dev/null | tr -d '\r')" || [ -z "$KEY" ]; then
      echo "per-copy (no remote)"
    elif [ "$OP" = "$OPD" ]; then
      echo "per-copy (profile not created)"
    else
      printf 'profile (key %s)\n' "$KEY"
    fi
    [ -f "$OP/LEARNINGS.md" ] && echo "note: LEARNINGS.md is still here; /team-setup moves the inbox"
    exit 0
    ;;

  index)
    for d in "$@"; do
      case "$d" in
        ''|/*|[A-Za-z]:*|*\\*) die "bad dir '$d': a project-relative path" ;;
      esac
      case "/$d/" in */../*) die "bad dir '$d': a project-relative path" ;; esac
    done
    bash "$TEAM_ROOT/tools/learnings-index.sh" "$OP/learnings" "$@" > "$TMP/index" 2> "$TMP/e"; rc=$?
    hide "$TMP/e" >&2
    [ "$rc" -eq 0 ] || exit 2
    # The File cell of an inbox row reads learnings/<file>. learnings-index.sh
    # writes a | in a cell as / and a tab as a space; the prefix is matched
    # the same way, as the last "| <prefix>" of the row (a cell never holds
    # "| ", so it starts the File cell).
    HIDE_OP="$OP" awk '
      BEGIN {
        p = ENVIRON["HIDE_OP"]; gsub(/\t/, " ", p); gsub(/\|/, "/", p)
        pre = "| " p "/learnings/"; n = length(pre)
      }
      {
        line = $0; at = 0; s = line; base = 0
        while ((i = index(s, pre)) > 0) { at = base + i; base += i; s = substr(s, i + 1) }
        if (at > 0) line = substr(line, 1, at - 1) "| learnings/" substr(line, at + n)
        print line
      }' "$TMP/index"
    exit 0
    ;;

  list)
    [ "$#" -eq 0 ] || usage
    if [ -d "$OP/learnings" ]; then
      for f in "$OP"/learnings/*.md; do
        [ -f "$f" ] || continue
        printf 'learnings/%s\n' "${f##*/}"
      done
    fi
    [ -f "$OP/review-exceptions.md" ] && echo "review-exceptions.md"
    exit 0
    ;;

  show)
    [ "$#" -gt 0 ] || usage
    for n in "$@"; do check_name "$n"; done
    missing=0
    for n in "$@"; do
      if [ -f "$OP/$n" ]; then
        printf '==> %s <==\n' "$n"
        { cat "$OP/$n"; } 2>/dev/null || die "$n could not be read"
        b="$(last_byte "$OP/$n")"
        [ -z "$b" ] || [ "$b" = "0a" ] || printf '\n'
      else
        printf '==> %s <== (missing)\n' "$n"
        missing=1
      fi
    done
    exit "$missing"
    ;;

  add)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
    if [ "$#" -eq 2 ]; then
      name="$2"
      case "$name" in learnings/*) ;; *) name="learnings/$name" ;; esac
    else
      [ "$1" != "-" ] || die "add from standard input needs a name"
      name="learnings/${1##*/}"
    fi
    check_name "$name"
    [ "$name" != "review-exceptions.md" ] || die "add writes entries only"
    check_source "$1"
    mkdir -p "$OP/learnings" 2>/dev/null && [ -d "$OP/learnings" ] || die "learnings/ could not be created in the operative dir"
    base="${name%.md}"
    try="$name"; i=1
    while :; do
      # noclobber: two copies adding the same name never write one file. The
      # name is claimed empty first, so a failed copy is told apart from a
      # taken name: it removes its own file and stops.
      if ( set -C; : > "$OP/$try" ) 2>/dev/null; then
        if { cat "$SRC" > "$OP/$try"; } 2>/dev/null; then
          printf '%s\n' "$try"
          exit 0
        fi
        rm -f "$OP/$try" 2>/dev/null
        die "$try could not be written"
      fi
      [ -e "$OP/$try" ] || die "$try could not be written"
      i=$((i + 1))
      [ "$i" -le 999 ] || die "no free name for $name"
      try="$base-$i.md"
    done
    ;;

  append)
    [ "$#" -eq 2 ] || usage
    check_name "$1"
    check_source "$2"
    target="$OP/$1"
    # Every redirect below is wrapped in { ...; } 2>/dev/null: bash's own
    # message for a failed redirect names the full path.
    if [ -e "$target" ] && [ ! -f "$target" ]; then
      die "$1 is not a file"
    fi
    if [ ! -f "$target" ]; then
      if [ "$1" != "review-exceptions.md" ]; then
        echo "inbox: $1: missing" >&2
        exit 1
      fi
      mkdir -p "$OP" 2>/dev/null || die "the operative dir could not be created"
      { cat "$SRC" > "$target"; } 2>/dev/null || die "$1 could not be written"
      exit 0
    fi
    crlf=0; ! has_crlf "$target" || crlf=1
    b="$(last_byte "$target")"
    if [ -n "$b" ] && [ "$b" != "0a" ]; then
      if [ "$crlf" = 1 ]; then eol='\r\n'; else eol='\n'; fi
      { printf '%b' "$eol" >> "$target"; } 2>/dev/null || die "$1 could not be written"
    fi
    if [ "$crlf" = 1 ]; then
      # The appended lines take the target's CRLF; a missing last newline
      # stays missing (BINMODE=3: gawk on Windows otherwise drops the CR).
      nonl=0; [ ! -s "$SRC" ] || [ "$(last_byte "$SRC")" = 0a ] || nonl=1
      awk -v BINMODE=3 -v nonl="$nonl" '
        { if (have) printf "%s\r\n", pl; sub(/\r$/, ""); pl = $0; have = 1 }
        END { if (have) printf "%s%s", pl, (nonl ? "" : "\r\n") }' "$SRC" > "$TMP/append" 2>/dev/null \
        || die "$1 could not be written"
      SRC="$TMP/append"
    fi
    { cat "$SRC" >> "$target"; } 2>/dev/null || die "$1 could not be written"
    exit 0
    ;;

  put)
    [ "$#" -eq 2 ] || usage
    check_name "$1"
    check_source "$2"
    dir="$OP"
    case "$1" in learnings/*) dir="$OP/learnings" ;; esac
    if [ -e "$OP/$1" ] && [ ! -f "$OP/$1" ]; then
      die "$1 is not a file"
    fi
    mkdir -p "$dir" 2>/dev/null && [ -d "$dir" ] || die "the directory for $1 could not be created"
    staged="$dir/.inbox-put-$$"
    if ! { cat "$SRC" > "$staged"; } 2>/dev/null; then rm -f "$staged" 2>/dev/null; die "$1 could not be written"; fi
    if ! mv -f "$staged" "$OP/$1" 2>/dev/null; then rm -f "$staged" 2>/dev/null; die "$1 could not be written"; fi
    exit 0
    ;;

  remove)
    [ "$#" -gt 0 ] || usage
    for n in "$@"; do check_name "$n"; done
    missing=0
    for n in "$@"; do
      if [ -f "$OP/$n" ]; then
        rm -f "$OP/$n" 2>/dev/null || die "$n could not be removed"
      else
        echo "inbox: $n: missing" >&2
        missing=1
      fi
    done
    exit "$missing"
    ;;

  check)
    [ "$#" -eq 0 ] || usage
    run_hidden bash "$TEAM_ROOT/checks/verify-learnings-inbox.sh" "$OP"
    exit $?
    ;;

  backup)
    [ "$#" -eq 1 ] || usage
    dest="${1%/}"
    valid_tracking_path "$dest" || die "bad destination '$1': a path under $TRACK/, project-root-relative"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      echo "inbox: $dest exists already; choose a new destination" >&2
      exit 1
    fi
    mkdir -p "$dest" 2>/dev/null || die "$dest could not be created"
    if [ -d "$OP/learnings" ]; then
      cp -R "$OP/learnings" "$dest/learnings" 2>/dev/null || die "learnings/ could not be copied to $dest"
    fi
    for f in review-exceptions.md LEARNINGS.md; do
      if [ -f "$OP/$f" ]; then
        cp "$OP/$f" "$dest/$f" 2>/dev/null || die "$f could not be copied to $dest"
      fi
    done
    printf '%s\n' "$dest"
    exit 0
    ;;

  verify-backup)
    [ "$#" -eq 1 ] || usage
    dest="${1%/}"
    valid_tracking_path "$dest" || die "bad backup '$1': a path under $TRACK/, project-root-relative"
    run_hidden bash "$TEAM_ROOT/checks/verify-knowledge-integrity.sh" "$dest" "$OP" inbox
    exit $?
    ;;
esac
