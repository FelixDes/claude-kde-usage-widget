#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
. "$project_dir/tests/fakes.sh"
write_creds test-token fresh max default_claude_max_5x

fetch="$project_dir/contents/code/fetch_usage.sh"
run_fetch() {
    "$fetch" "$@"
}

valid='{
  "five_hour": {"utilization": 18.0, "resets_at": "2026-10-27T16:40:00.48+00:00"},
  "seven_day": {"utilization": 12.0, "resets_at": "2026-10-31T07:00:00.48+00:00"},
  "seven_day_breakdown": {"rows": [
    {"key": "claude_code", "display_name": "Claude Code", "percent": 96},
    {"key": "chat", "display_name": "Chats", "percent": 4},
    {"key": "bad", "display_name": "", "percent": 1}]},
  "limits": [
    {"kind": "session", "percent": 18, "severity": "normal", "resets_at": "2026-10-27T16:40:00Z"},
    {"kind": "weekly_all", "percent": 12, "severity": "warning", "resets_at": "2026-10-31T07:00:00Z"},
    {"kind": "weekly_scoped", "percent": 11, "resets_at": "2026-10-10T07:00:00Z", "severity": "normal",
     "scope": {"model": {"display_name": "Fable"}}},
    {"kind": "weekly_scoped", "percent": 65, "resets_at": null,
     "scope": {"model": {"display_name": "Opus"}}}]}'
output=$(FAKE_BODY="$valid" run_fetch none)
python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["source"] == "usage"
assert d["h5"] == {"status": "allowed", "severity": "normal", "utilization": 0.18,
                   "reset_ts": "2026-10-27T16:40:00.48+00:00", "reset_in": ""}, d["h5"]
assert d["d7"]["utilization"] == 0.12 and d["d7"]["severity"] == "warning"
assert d["plan"] == "max" and d["tier"] == 5
assert [r["label"] for r in d["breakdown"]] == ["Claude Code", "Chats"]
fable, opus = d["model_limits"]
assert fable == {"label": "Fable", "status": "allowed", "severity": "normal", "utilization": 0.11,
                 "reset_ts": "2026-10-10T07:00:00Z", "reset_in": ""}, fable
assert opus["label"] == "Opus" and opus["utilization"] == 0.65 and opus["reset_ts"] is None
' <<<"$output"
[[ "$output" != *test-token* ]]

# Each success is recorded in the history.
python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
assert len(rows) == 1, rows
s = rows[0]
assert s["src"] == "usage" and s["tier"] == 5
assert s["h5"] == 18.0 and s["d7"] == 12.0 and s["fable"] == 11.0
assert s["h5_reset"] == 1793119200, s
' "$CLAUDE_WIDGET_HISTORY"

[ "$(cat "$fixture_dir/token")" = test-token ]
python3 - "$fixture_dir/args" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert args[0] == "-q"
assert "anthropic-beta: oauth-2025-04-20" in args
# The token is passed through stdin, never on the command line.
assert not any("test-token" in arg for arg in args)
i = args.index("--noproxy")
assert args[i + 1] == "*"
PY

proxy_url='http://proxy.example:8080/path?x=1&y=2'
FAKE_BODY="$valid" run_fetch custom "$proxy_url" >/dev/null
python3 - "$fixture_dir/args" "$proxy_url" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
i = args.index("--proxy")
assert args[i + 1] == sys.argv[2]
i = args.index("--noproxy")
assert args[i + 1] == ""
PY

# Only the limits array: 5h/7d come from the session/weekly_all entries.
limits_only='{"limits":[{"kind":"session","percent":30,"resets_at":"2026-10-27T16:40:00Z"},{"kind":"weekly_all","percent":100}]}'
output=$(FAKE_BODY="$limits_only" run_fetch env)
python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["h5"]["utilization"] == 0.3
assert d["d7"]["status"] == "limited" and d["d7"]["reset_ts"] is None
assert d["model_limits"] == [] and d["breakdown"] == []
' <<<"$output"

# Pro has no multiplier in rateLimitTier; unknown plans have no tier.
write_creds test-token fresh pro
FAKE_BODY="$valid" run_fetch env | python3 -c 'import json,sys; assert json.load(sys.stdin)["tier"] == 1'
write_creds test-token fresh team
FAKE_BODY="$valid" run_fetch env | python3 -c 'import json,sys; assert json.load(sys.stdin)["tier"] is None'

expect_error() {
    local expected=$1 fallback=$2
    shift 2
    if output=$("$@"); then
        echo "unexpected success: $output" >&2
        exit 1
    fi
    python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["error"] == sys.argv[1], d
assert d["fallback"] is (sys.argv[2] == "true"), d
' "$expected" "$fallback" <<<"$output"
}

# Missing 5h/7d or a malformed body: the widget should fall back to the probe.
expect_error "Usage response has no 5h/7d limits" true env FAKE_BODY='{"limits":[]}' "$fetch" none
expect_error "Usage response parse failed" true env FAKE_BODY='not json' "$fetch" none
# Throttling falls back too; network errors do not (the probe would fail the same way).
expect_error "Rate limited (HTTP 429)" true env FAKE_HTTP_CODE=429 FAKE_BODY="$valid" "$fetch" none
expect_error "Network error: cannot reach api.anthropic.com" false env FAKE_CURL_FAIL=1 "$fetch" none
expect_error "Custom proxy URL is empty" false "$fetch" custom ""

# Failures are not recorded.
[ "$(wc -l <"$CLAUDE_WIDGET_HISTORY")" = 5 ]

echo "fetch_usage tests passed"
