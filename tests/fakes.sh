# Fake curl and claude binaries for the fetch script tests. Source this file;
# it sets fixture_dir (removed on exit) and puts the fakes first on PATH.
#
# Fake curl:
#   FAKE_BODY       response body (written to -o, or stdout without -o)
#   FAKE_HEADERS    response headers (written to -D)
#   FAKE_CODES      per-token status codes, e.g. "old=401 new=200"
#   FAKE_HTTP_CODE  status code for tokens not in FAKE_CODES (default 200)
#   FAKE_CURL_FAIL  1 = network failure (status 000, exit 7)
#   Records its arguments in $fixture_dir/args, the bearer token it got
#   through --config in $fixture_dir/token and every token in tokens.log.
#
# Fake claude rewrites the credentials file with FAKE_NEW_TOKEN (default
# "new-token") after FAKE_CLAUDE_SLEEP seconds and appends to
# $fixture_dir/claude.log.

fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

export FAKE_DIR="$fixture_dir"
export CREDS_FILE="$fixture_dir/credentials.json"
export CLAUDE_WIDGET_REFRESH_LOCK="$fixture_dir/refresh.lock"
# Never touch the real usage history from tests.
export CLAUDE_WIDGET_HISTORY="$fixture_dir/history.jsonl"

cat >"$fixture_dir/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/args"
out="" headers="" write_code=0 token=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out=$2; shift ;;
        -D) headers=$2; shift ;;
        -w) write_code=1; shift ;;
        --config) [ "$2" = "-" ] && token=$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p'); shift ;;
    esac
    shift
done
printf '%s' "$token" >"$FAKE_DIR/token"
printf '%s\n' "$token" >>"$FAKE_DIR/tokens.log"

if [ "${FAKE_CURL_FAIL:-0}" = 1 ]; then
    [ "$write_code" = 1 ] && printf '000'
    exit 7
fi

code=${FAKE_HTTP_CODE:-200}
for pair in ${FAKE_CODES:-}; do
    [ "${pair%%=*}" = "$token" ] && code=${pair#*=}
done
[ -n "$headers" ] && printf '%s' "${FAKE_HEADERS:-}" >"$headers"
if [ -n "$out" ]; then
    [ "$out" = /dev/null ] || printf '%s' "${FAKE_BODY:-}" >"$out"
else
    printf '%s' "${FAKE_BODY:-}"
fi
[ "$write_code" = 1 ] && printf '%s' "$code"
exit 0
EOF

cat >"$fixture_dir/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DIR/claude.log"
sleep "${FAKE_CLAUDE_SLEEP:-0}"
python3 - "$CREDS_FILE" "${FAKE_NEW_TOKEN:-new-token}" <<'PY'
import json, sys, time
json.dump({"claudeAiOauth": {"accessToken": sys.argv[2], "subscriptionType": "max",
                             "expiresAt": int((time.time() + 3600) * 1000)}},
          open(sys.argv[1], "w"))
PY
EOF
chmod +x "$fixture_dir/curl" "$fixture_dir/claude"
export PATH="$fixture_dir:$PATH"

# write_creds TOKEN [expired|fresh] [PLAN] [RATE_LIMIT_TIER]
write_creds() {
    local offset=3600
    [ "${2:-}" = expired ] && offset=-3600
    python3 - "$CREDS_FILE" "$1" "$offset" "${3:-pro}" "${4:-}" <<'PY'
import json, sys, time
oauth = {"accessToken": sys.argv[2], "subscriptionType": sys.argv[4],
         "expiresAt": int((time.time() + int(sys.argv[3])) * 1000)}
if sys.argv[5]:
    oauth["rateLimitTier"] = sys.argv[5]
json.dump({"claudeAiOauth": oauth}, open(sys.argv[1], "w"))
PY
}

reset_logs() {
    rm -f "$fixture_dir/claude.log" "$fixture_dir/tokens.log" "$fixture_dir/args" "$fixture_dir/token"
}

claude_runs() {
    [ -f "$fixture_dir/claude.log" ] && wc -l <"$fixture_dir/claude.log" || echo 0
}
