#!/usr/bin/env bash
# tools/jev-decide.sh is the only code that sends anything off the machine.
# This runs it against a fake curl placed first on PATH and checks the three
# promises it makes: nothing is sent without a key and recorded consent,
# the key never appears on a command line, and every failure is silent with
# exit 0. It also checks that awkward task text produces an escaped body.
#
#   verify-jev-decide.sh     (run from anywhere; it locates the team root
#                             from its own path)
set -uo pipefail
export LC_ALL=C

cd "$(dirname "$0")/.." || exit 1
script="$(pwd)/tools/jev-decide.sh"
[ -f "$script" ] || { echo "FAIL: tools/jev-decide.sh not found" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/log" "$tmp/project/.claude-tracking"

cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Fake curl: records its arguments, headers and body; answers $FAKE_CODE with $FAKE_BODY.
: > "$FAKE_LOG/called"
printf '%s\n' "$@" > "$FAKE_LOG/args"
out=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    --data-binary) data="${2#@}"; shift ;;
    -H) [ "$2" = "@-" ] && cat > "$FAKE_LOG/headers"; shift ;;
    -w|-X|--max-time) shift ;;
  esac
  shift
done
[ -n "$data" ] && cp "$data" "$FAKE_LOG/body"
[ -n "$out" ] && printf '%s' "${FAKE_BODY:-}" > "$out"
printf '%s' "${FAKE_CODE:-200}"
EOF
chmod +x "$tmp/bin/curl"

export FAKE_LOG="$tmp/log" CLAUDE_PROJECT_DIR="$tmp/project" PATH="$tmp/bin:$PATH"
export FAKE_BODY='{"answers":{"workflow":{"type":"choice","choice":"bug_fix","confidence":0.9}}}'
consent="$tmp/project/.claude-tracking/.service-consent"
state="$tmp/state.txt"
status=0
fail() { echo "FAIL: $*" >&2; status=1; }
reset() { rm -f "$tmp/log/"*; }
ask() {
  out="$(bash "$script" "$@" 2>"$tmp/err")"; code=$?
  [ "$code" = 0 ] || fail "exit $code for: $*"
  [ -s "$tmp/err" ] && fail "stderr for '$*': $(head -1 "$tmp/err")"
}
sent() { [ -e "$tmp/log/called" ]; }

printf 'fix the login bug\n' > "$state"
printf 'jev=granted 2026-09-29\n' > "$consent"

# 1. no key: nothing sent, nothing printed. A consent line without a provider
#    (the shape written before providers existed) means the default one.
unset TYPESAFE_API_KEY OPENROUTER_API_KEY
reset; ask workflow "$state"
[ -z "$out" ] || fail "no key: printed output"
sent && fail "no key: curl was called"

export TYPESAFE_API_KEY=test-key-123

# 2. no consent file
rm -f "$consent"; reset; ask workflow "$state"
sent && fail "no consent: curl was called"
[ -z "$out" ] || fail "no consent: printed output"

# 3. consent declined
printf 'jev=declined 2026-09-29\n' > "$consent"; reset; ask workflow "$state"
sent && fail "declined: curl was called"

printf 'jev=granted 2026-09-29\r\n' > "$consent"

# 4. unknown or path-like question set, missing or empty state
for bad in nosuchset ../templates/jev/workflow "" WORKFLOW; do
  reset; ask "$bad" "$state"; sent && fail "question set '$bad': curl was called"
done
reset; ask workflow "$tmp/missing.txt"; sent && fail "missing state: curl was called"
: > "$tmp/empty.txt"; reset; ask workflow "$tmp/empty.txt"; sent && fail "empty state: curl was called"

# 5. success: escaped body, key only on stdin, response printed
printf 'say "hi" \\back\tslash\r\nline two caf\303\251\n' > "$state"
reset; ask workflow "$state"
sent || fail "success: curl was not called"
[ "$out" = "$FAKE_BODY" ] || fail "success: printed '$out'"
body="$(cat "$tmp/log/body" 2>/dev/null)"
for want in '"model":"jev-1.13.0"' 'say \"hi\" \\back\tslash\nline two caf' '"questions":{' '"type": "choice"'; do
  printf '%s' "$body" | grep -qF -- "$want" || fail "success: body lacks $want"
done
printf '%s' "$body" | grep -q $'\303\251' || fail "success: non-ASCII text was not passed through"
printf '%s' "$body" | grep -q $'\r' && fail "success: body carries a raw CR"
grep -qF 'test-key-123' "$tmp/log/args" 2>/dev/null && fail "success: the key is on the command line"
grep -qF 'Authorization: Bearer test-key-123' "$tmp/log/headers" 2>/dev/null \
  || fail "success: no auth header on stdin"
grep -qx 'https://api.typesafe.ai/v1/systemone' "$tmp/log/args" 2>/dev/null \
  || fail "success: not sent to the manifest's endpoint"

# 5b. the environment cannot redirect the key elsewhere
reset; JEV_ENDPOINT=http://127.0.0.1:1/ ask workflow "$state"
grep -qF '127.0.0.1' "$tmp/log/args" 2>/dev/null && fail "JEV_ENDPOINT redirected the request"

# 5c. bytes that are not UTF-8 are dropped, valid text around them kept
printf 'bad \377\376 bytes caf\303\251\n' > "$state"
reset; ask workflow "$state"
grep -q $'\377' "$tmp/log/body" 2>/dev/null && fail "invalid UTF-8: raw bytes sent"
grep -qF 'bad  bytes caf' "$tmp/log/body" 2>/dev/null || fail "invalid UTF-8: surrounding text lost"
printf 'say "hi" \\back\tslash\r\nline two caf\303\251\n' > "$state"

# 6. HTTP error: silent
FAKE_CODE=529 ask workflow "$state"
[ -z "$out" ] || fail "http 529: printed output"

# 7. long state is cut to 8000 characters
head -c 9000 /dev/zero | tr '\0' 'a' > "$state"
reset; ask difficulty "$state"
n="$(sed -n 's/.*"state":"\(a*\)".*/\1/p' "$tmp/log/body" 2>/dev/null | tr -d '\n' | wc -c | tr -d ' ')"
[ "$n" = 8000 ] || fail "long state: sent $n characters, expected 8000"

# 8. probe needs a key but no consent, and sends no user data
rm -f "$consent"; reset; ask probe
sent || fail "probe: curl was not called"
grep -qF '"state":"probe"' "$tmp/log/body" 2>/dev/null || fail "probe: unexpected body"

# 9. providers: consent names who receives the text, and only that
#    provider's key, endpoint and model are used
printf 'fix the login bug\n' > "$state"
export OPENROUTER_API_KEY=or-key-456
printf 'jev=granted openrouter 2026-09-30\n' > "$consent"
reset; ask workflow "$state"
sent || fail "openrouter: curl was not called"
grep -qx 'https://openrouter.ai/api/v1/systemone' "$tmp/log/args" 2>/dev/null \
  || fail "openrouter: not sent to the openrouter endpoint"
grep -qF '"model":"typesafe/jev-1.13"' "$tmp/log/body" 2>/dev/null || fail "openrouter: wrong model id"
grep -qF 'Authorization: Bearer or-key-456' "$tmp/log/headers" 2>/dev/null || fail "openrouter: wrong key"
grep -qF 'test-key-123' "$tmp/log/headers" 2>/dev/null && fail "openrouter: the typesafe key was sent"
grep -qF 'or-key-456' "$tmp/log/args" 2>/dev/null && fail "openrouter: the key is on the command line"

# consent for openrouter with only the typesafe key set: nothing is sent
unset OPENROUTER_API_KEY
reset; ask workflow "$state"; sent && fail "openrouter consent, no openrouter key: curl was called"

# consent for typesafe with only the openrouter key set: nothing is sent
export OPENROUTER_API_KEY=or-key-456; unset TYPESAFE_API_KEY
printf 'jev=granted typesafe 2026-09-30\n' > "$consent"
reset; ask workflow "$state"; sent && fail "typesafe consent, no typesafe key: curl was called"

# with both keys set from here on, only the consent line can stop a request
export TYPESAFE_API_KEY=test-key-123

# a provider the manifest does not declare: nothing is sent
printf 'jev=granted elsewhere 2026-09-30\n' > "$consent"
reset; ask workflow "$state"; sent && fail "undeclared provider: curl was called"

# the last line for the service wins, so a later decline revokes
printf 'jev=granted openrouter 2026-09-30\njev=declined 2026-10-01\n' > "$consent"
reset; ask workflow "$state"; sent && fail "later decline: curl was called"

# probe takes the provider as its argument
rm -f "$consent"; reset; ask probe openrouter
grep -qx 'https://openrouter.ai/api/v1/systemone' "$tmp/log/args" 2>/dev/null \
  || fail "probe openrouter: not sent to the openrouter endpoint"
reset; ask probe elsewhere; sent && fail "probe of an undeclared provider: curl was called"

# /team-setup offers every provider, key or not, and tells the user where to
# get the missing key: each provider needs an https keyUrl, and the entry
# needs the keySetup text that says where to put it.
manifest="$(tr -d '\r' < team-manifest.json)"
no_url="$(printf '%s\n' "$manifest" | awk '
  /"providers"[[:space:]]*:[[:space:]]*\{/ { inp = 1; next }
  inp && !p && /^[[:space:]]*}/ { exit }
  inp && !p && /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\{/ {
    p = $0; sub(/^[[:space:]]*"/, "", p); sub(/".*/, "", p); url = 0; next
  }
  p && /"keyUrl"[[:space:]]*:[[:space:]]*"https:\/\/[^"]+"/ { url = 1 }
  p && /^[[:space:]]*}/ { if (!url) print p; p = "" }')"
[ -z "$no_url" ] || fail "providers without an https keyUrl: $(printf '%s' "$no_url" | tr '\n' ' ')"
printf '%s\n' "$manifest" | grep -q '"keySetup"[[:space:]]*:[[:space:]]*"[^"]' \
  || fail "the service entry has no keySetup text"

[ "$status" -eq 0 ] && echo "jev client: ok"
exit "$status"
