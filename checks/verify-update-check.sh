#!/usr/bin/env bash
# tools/update-check.sh asks GitHub whether a newer team version exists.
# This runs it against a fake curl placed first on PATH and checks what it
# promises: nothing is fetched without recorded consent; at most one fetch per
# interval, whether it succeeded or not; a newer version is reported as
# "<local> <latest>" and never once skipped; every failure is silent with
# exit 0. It runs a copy of the script beside a minimal manifest, so the
# numbers here do not move with each release, and then the real script once,
# to prove the real manifest carries what the script needs.
#
#   verify-update-check.sh   (run from anywhere; it locates the team root
#                             from its own path)
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
real="$(pwd)/tools/update-check.sh"
[ -f "$real" ] || { echo "FAIL: tools/update-check.sh not found" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/log" "$tmp/team/tools" "$tmp/project/.claude-tracking"
cp "$real" "$tmp/team/tools/update-check.sh"
cat > "$tmp/team/team-manifest.json" <<'EOF'
{
  "team": {
    "version": "3.9.0"
  },
  "updateCheck": {
    "source": "https://example.invalid/team-manifest.json",
    "intervalHours": 24
  }
}
EOF

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: counts calls, records its arguments, prints $FAKE_BODY, exits $FAKE_EXIT.
echo x >> "$FAKE_LOG/calls"
printf '%s\n' "$@" > "$FAKE_LOG/args"
printf '%s' "${FAKE_BODY:-}"
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$tmp/bin/curl"

export FAKE_LOG="$tmp/log" CLAUDE_PROJECT_DIR="$tmp/project" PATH="$tmp/bin:$PATH"
script="$tmp/team/tools/update-check.sh"
consent="$tmp/project/.claude-tracking/.service-consent"
cache="$tmp/project/.claude-tracking/.update-check"
status=0
fail() { echo "FAIL: $*" >&2; status=1; }
remote() { export FAKE_BODY="{\"team\": {\"version\": \"$1\"}}" FAKE_EXIT=0; }
fresh() { rm -f "$tmp/log/"* "$cache"; }
calls() { if [ -f "$tmp/log/calls" ]; then wc -l < "$tmp/log/calls" | tr -d ' '; else echo 0; fi; }
run() {
  out="$(bash "$script" "$@" 2>"$tmp/err")"; code=$?
  [ "$code" = 0 ] || fail "exit $code for: ${*:-check}"
  [ -s "$tmp/err" ] && fail "stderr for '${*:-check}': $(head -1 "$tmp/err")"
}

# 1. no consent, a decline, a malformed line, another service's line, a
#    later decline: nothing fetched, nothing printed, probe included
remote 4.0.0
for c in '' 'update-check=declined 2026-10-05' 'update-check=grantedx 2026-10-05' \
         'jev=granted 2026-10-05' $'update-check=granted 2026-10-01\nupdate-check=declined 2026-10-05'; do
  if [ -n "$c" ]; then printf '%s\n' "$c" > "$consent"; else rm -f "$consent"; fi
  fresh; run
  [ "$(calls)" = 0 ] || fail "consent '$c': curl was called"
  [ -z "$out" ] || fail "consent '$c': printed '$out'"
  run probe
  [ "$(calls)" = 0 ] || fail "consent '$c': probe called curl"
done

# 2. granted (CRLF line), no cache: one fetch from the manifest's source,
#    the answer printed and cached
printf 'update-check=granted 2026-10-05\r\n' > "$consent"
fresh; remote 4.0.0; run
[ "$(calls)" = 1 ] || fail "no cache: expected 1 call, got $(calls)"
[ "$out" = "3.9.0 4.0.0" ] || fail "no cache: printed '$out'"
grep -qx 'https://example.invalid/team-manifest.json' "$tmp/log/args" 2>/dev/null \
  || fail "no cache: not fetched from the manifest's source"
grep -qx 'latest=4.0.0' "$cache" 2>/dev/null || fail "no cache: latest not cached"
grep -qE '^checked=[0-9]+$' "$cache" 2>/dev/null || fail "no cache: checked not written"

# 3. fresh cache: no second fetch, same answer
remote 5.0.0; run
[ "$(calls)" = 1 ] || fail "fresh cache: curl was called again"
[ "$out" = "3.9.0 4.0.0" ] || fail "fresh cache: printed '$out'"

# 4. stale cache, and a checked time in the future: fetched again
for c in 0 99999999999; do
  rm -f "$tmp/log/"*; printf 'checked=%s\nlatest=4.0.0\n' "$c" > "$cache"; remote 4.1.0; run
  [ "$(calls)" = 1 ] || fail "checked=$c: curl was not called"
  [ "$out" = "3.9.0 4.1.0" ] || fail "checked=$c: printed '$out'"
done

# 5. ordering is numeric per component, never textual
while read -r r want; do
  fresh; remote "$r"; run
  [ "$out" = "$want" ] || fail "remote $r: printed '$out', expected '$want'"
done <<'EOF'
3.10.0 3.9.0 3.10.0
3.9.1 3.9.0 3.9.1
10.0.0 3.9.0 10.0.0
3.9.0
3.8.99
2.99.99
EOF

# 6. skip: sends nothing, suppresses that version only, survives a fetch
fresh; remote 4.0.0; run skip 4.0.0
[ "$(calls)" = 0 ] || fail "skip: curl was called"
grep -qx 'skipped=4.0.0' "$cache" 2>/dev/null || fail "skip: not recorded"
run
[ -z "$out" ] || fail "skipped 4.0.0: still printed '$out'"
grep -qx 'skipped=4.0.0' "$cache" 2>/dev/null || fail "skip: lost on the next fetch"
printf 'checked=0\nlatest=4.0.0\nskipped=4.0.0\n' > "$cache"; remote 4.0.1; run
[ "$out" = "3.9.0 4.0.1" ] || fail "skipped 4.0.0: newer 4.0.1 printed '$out'"
fresh
for bad in '' 4.0 v4.0.0 '4.0.0 x' $'4.0.0\n5.0.0' ../x; do
  run skip "$bad"
  [ -e "$cache" ] && { fail "skip '$bad': wrote the cache"; rm -f "$cache"; }
done

# 7. a failed fetch is silent, advances checked, keeps the earlier answer,
#    and is not retried inside the interval
fresh; export FAKE_BODY='' FAKE_EXIT=22; run
[ -z "$out" ] || fail "failed fetch: printed '$out'"
grep -qE '^checked=[0-9]+$' "$cache" 2>/dev/null || fail "failed fetch: checked not advanced"
grep -q '^latest=' "$cache" 2>/dev/null && fail "failed fetch: latest written"
run
[ "$(calls)" = 1 ] || fail "failed fetch: retried inside the interval"
printf 'checked=0\nlatest=4.0.0\n' > "$cache"; run
[ "$out" = "3.9.0 4.0.0" ] || fail "failed fetch: the cached answer was lost, printed '$out'"

# 8. bodies that carry no single valid version: silence
for body in 'not json' '<html>404</html>' '{"version": "4.0"}' '{"version": "4.0.0-beta"}' \
            '{"a": {"version": "4.0.0"}, "b": {"version": "5.0.0"}}'; do
  fresh; export FAKE_BODY="$body" FAKE_EXIT=0; run
  [ -z "$out" ] || fail "body '$body': printed '$out'"
  grep -q '^latest=' "$cache" 2>/dev/null && fail "body '$body': latest written"
done

# 9. a corrupt cache counts as no cache
fresh; printf 'checked=abc\nlatest=x.y.z\nskipped=;rm -rf /\n\377\376\n' > "$cache"; remote 4.0.0; run
[ "$(calls)" = 1 ] || fail "corrupt cache: curl was not called"
[ "$out" = "3.9.0 4.0.0" ] || fail "corrupt cache: printed '$out'"

# 9a. a checked value too large for shell arithmetic counts as no cache
fresh; printf 'checked=99999999999999999999999\n' > "$cache"; remote 4.0.0; run
[ "$(calls)" = 1 ] || fail "overflowing checked: curl was not called"
[ "$out" = "3.9.0 4.0.0" ] || fail "overflowing checked: printed '$out'"

# 9b. a cache that cannot be written: the answer is still printed, and
#     nothing reaches stderr
fresh; mkdir "$cache.tmp"; remote 4.0.0; run
[ "$out" = "3.9.0 4.0.0" ] || fail "unwritable cache: printed '$out'"
rmdir "$cache.tmp"

# 10. probe ignores a fresh cache and prints the remote version alone
remote 4.2.0; rm -f "$tmp/log/"*; run probe
[ "$(calls)" = 1 ] || fail "probe: curl was not called"
[ "$out" = "4.2.0" ] || fail "probe: printed '$out'"

# 11. a source that is not https: nothing fetched
sed 's#https://example.invalid#http://example.invalid#' "$tmp/team/team-manifest.json" > "$tmp/m.json" \
  && mv "$tmp/m.json" "$tmp/team/team-manifest.json"
fresh; remote 4.0.0; run; run probe
[ "$(calls)" = 0 ] || fail "http source: curl was called"

# 12. the real script against the real manifest
fresh; remote 99.0.0
out="$(bash "$real" 2>"$tmp/err")"
case "$out" in [0-9]*.[0-9]*.[0-9]*' 99.0.0') ;; *) fail "real manifest: printed '$out'" ;; esac
grep -qx 'https://raw.githubusercontent.com/dm-23/dream-team/main/team-manifest.json' "$tmp/log/args" 2>/dev/null \
  || fail "real manifest: not fetched from the repository's raw manifest"

[ "$status" -eq 0 ] && echo "update check: ok"
exit "$status"
