#!/usr/bin/env bash
# Every agent and skill starts with a YAML frontmatter block. A value with a
# bare colon in it (description: a: b) is not valid YAML: the file loads in
# nothing that parses it strictly and the role or skill silently disappears.
# This parses the block of every agents/*.md and skills/*/SKILL.md with a real
# YAML parser, prints "FAIL: <file>: <error>" for each one that does not parse
# and exits 1.
#
#   verify-frontmatter.sh [<team-root>]   (default: the parent of checks/)
#
# Needs an interpreter with the yaml module (python3, python or py). When none
# is found it prints "frontmatter: skipped (no YAML parser)" and exits 0,
# except when CI is non-empty, where a skipped check is a failure.
set -uo pipefail
export LC_ALL=C

ROOT="${1:-$(dirname "$0")/..}"
cd "$ROOT" || exit 1

PY=""
for cand in python3 python py; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import yaml' >/dev/null 2>&1; then
    PY="$cand"; break
  fi
done
if [ -z "$PY" ]; then
  echo "frontmatter: skipped (no YAML parser)"
  [ -n "${CI:-}" ] && exit 1
  exit 0
fi

"$PY" - <<'PYEOF'
import glob, sys, yaml

status = 0
files = sorted(glob.glob("agents/*.md") + glob.glob("skills/*/SKILL.md"))
files = [f.replace("\\", "/") for f in files]
for f in files:
    text = open(f, encoding="utf-8").read().replace("\r\n", "\n")
    if not text.startswith("---\n"):
        print("FAIL: %s: no frontmatter block" % f, file=sys.stderr)
        status = 1
        continue
    end = text.find("\n---", 4)
    if end < 0:
        print("FAIL: %s: frontmatter is not closed" % f, file=sys.stderr)
        status = 1
        continue
    try:
        data = yaml.safe_load(text[4:end])
    except yaml.YAMLError as e:
        msg = " ".join(str(e).split())
        print("FAIL: %s: %s" % (f, msg), file=sys.stderr)
        status = 1
        continue
    if not isinstance(data, dict):
        print("FAIL: %s: frontmatter is not a mapping" % f, file=sys.stderr)
        status = 1
if status == 0:
    print("frontmatter: ok")
sys.exit(status)
PYEOF
