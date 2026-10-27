#!/bin/bash
# Token loading and refresh in common.sh, exercised through both fetch scripts.
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
. "$project_dir/tests/fakes.sh"

limits() { "$project_dir/contents/code/fetch_limits.sh" none; }
model_limits() { "$project_dir/contents/code/fetch_usage.sh" none; }

export FAKE_HEADERS=$'HTTP/2 200\r\nanthropic-ratelimit-unified-status: allowed\r\nanthropic-ratelimit-unified-5h-utilization: 0.25\r\nanthropic-ratelimit-unified-7d-utilization: 0.5\r\n\r\n'
export FAKE_BODY='{"five_hour":{"utilization":25,"resets_at":"2026-10-27T16:40:00Z"},"limits":[{"kind":"weekly_scoped","percent":10,"scope":{"model":{"display_name":"Fable"}}}]}'

check_limits() {
    python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["h5"]["utilization"] == 0.25, d
assert d["d7"]["utilization"] == 0.5, d
assert d["plan"] == sys.argv[1], d
' "$1"
}

# An expired Claude Code token is refreshed before the request.
reset_logs
write_creds old-token expired
limits | check_limits max
[ "$(cat "$fixture_dir/tokens.log")" = new-token ]
[ "$(claude_runs)" = 1 ]
grep -q -- '--model haiku' "$fixture_dir/claude.log"

# A rejected (401) token is refreshed once and the request retried.
reset_logs
write_creds old-token
FAKE_CODES="old-token=401" model_limits >/dev/null
[ "$(paste -sd, "$fixture_dir/tokens.log")" = old-token,new-token ]
[ "$(claude_runs)" = 1 ]

# If the refreshed token is rejected too, report it instead of looping.
reset_logs
write_creds old-token
if output=$(FAKE_CODES="old-token=401 new-token=401" model_limits); then
    echo "rejected token unexpectedly succeeded" >&2
    exit 1
fi
[[ "$output" == *"Token expired or revoked"* ]]
[ "$(claude_runs)" = 1 ]

# Network failures do not spawn claude: a refresh cannot help.
reset_logs
write_creds old-token
if output=$(FAKE_CURL_FAIL=1 limits); then
    echo "network failure unexpectedly succeeded" >&2
    exit 1
fi
[[ "$output" == *"Network error"* ]]
[ "$(claude_runs)" = 0 ]

# Region blocks and similar 403s are reported, not retried with a refresh.
reset_logs
if output=$(FAKE_HTTP_CODE=403 FAKE_HEADERS="" model_limits); then
    echo "403 unexpectedly succeeded" >&2
    exit 1
fi
[[ "$output" == *"HTTP 403"* ]]
[ "$(claude_runs)" = 0 ]

# A 429 still carries rate limit headers, which is what the limits probe needs.
reset_logs
write_creds creds-token
FAKE_HTTP_CODE=429 limits | check_limits pro

# Parallel fetches with an expired token refresh it only once.
reset_logs
write_creds old-token expired
FAKE_CLAUDE_SLEEP=1 limits >"$fixture_dir/out1" &
FAKE_CLAUDE_SLEEP=1 model_limits >"$fixture_dir/out2" &
wait
check_limits max <"$fixture_dir/out1"
grep -q Fable "$fixture_dir/out2"
[ "$(claude_runs)" = 1 ]

# Nothing to authenticate with.
reset_logs
rm -f "$CREDS_FILE"
if output=$(limits); then
    echo "missing credentials unexpectedly succeeded" >&2
    exit 1
fi
[[ "$output" == *"No Claude Code credentials"* ]]

# A credentials file without a usable token is rejected up front.
reset_logs
printf '{"claudeAiOauth":{"accessToken":"bad\\"token"}}' >"$CREDS_FILE"
if output=$(limits); then
    echo "malformed token unexpectedly succeeded" >&2
    exit 1
fi
[[ "$output" == *"No Claude Code credentials"* ]]
[ ! -f "$fixture_dir/tokens.log" ]

echo "auth tests passed"
