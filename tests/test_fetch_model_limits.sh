#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

printf '%s\n' '{"claudeAiOauth":{"accessToken":"test-token"}}' >"$fixture_dir/credentials.json"

cat >"$fixture_dir/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"${FAKE_ARGS_FILE:?}"
printf '%s' "${FAKE_USAGE_BODY:-}"
[ "${FAKE_CURL_FAIL:-0}" = "1" ] && exit 7
exit 0
EOF
chmod +x "$fixture_dir/curl"

run_fetch() {
    CREDS_FILE="$fixture_dir/credentials.json" \
    FAKE_ARGS_FILE="$fixture_dir/args" \
    PATH="$fixture_dir:$PATH" \
        "$project_dir/contents/code/fetch_model_limits.sh" "$@"
}

valid='{"limits":[{"kind":"weekly_scoped","group":"weekly","percent":11,"resets_at":"2026-10-10T07:00:00Z","severity":"normal","is_active":false,"scope":{"model":{"display_name":"Fable"}}},{"kind":"weekly_scoped","percent":65,"resets_at":null,"scope":{"model":{"display_name":"Opus"}}},{"kind":"weekly_all","percent":20}]}'
output=$(FAKE_USAGE_BODY="$valid" run_fetch none)
python3 -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["model_limits"]) == 2
fable, opus = d["model_limits"]
assert fable == {
    "label": "Fable", "status": "allowed", "severity": "normal", "utilization": 0.11,
    "reset_ts": "2026-10-10T07:00:00Z", "reset_in": "",
}
assert opus["label"] == "Opus"
assert opus["severity"] == ""
assert opus["utilization"] == 0.65
assert opus["reset_ts"] is None
' <<<"$output"
[[ "$output" != *test-token* ]]

python3 - "$fixture_dir/args" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert args[0] == "-q"
assert "anthropic-beta: oauth-2025-04-20" in args
assert "Authorization: Bearer test-token" in args
i = args.index("--noproxy")
assert args[i + 1] == "*"
PY

proxy_url='http://proxy.example:8080/path?x=1&y=2'
FAKE_USAGE_BODY='{"limits":[]}' run_fetch custom "$proxy_url" >/dev/null
python3 - "$fixture_dir/args" "$proxy_url" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
i = args.index("--proxy")
assert args[i + 1] == sys.argv[2]
i = args.index("--noproxy")
assert args[i + 1] == ""
PY

empty=$(FAKE_USAGE_BODY='{"limits":[]}' run_fetch env)
python3 -c 'import json,sys; assert json.load(sys.stdin) == {"model_limits": []}' <<<"$empty"

nullable=$(FAKE_USAGE_BODY='{"limits":null}' run_fetch env)
python3 -c 'import json,sys; assert json.load(sys.stdin) == {"model_limits": []}' <<<"$nullable"

if output=$(FAKE_USAGE_BODY='not json' run_fetch none); then
    echo "malformed JSON unexpectedly succeeded" >&2
    exit 1
fi
python3 -c 'import json,sys; assert json.load(sys.stdin)["error"] == "model limits parse failed"' <<<"$output"

if output=$(FAKE_CURL_FAIL=1 FAKE_USAGE_BODY="$valid" run_fetch none); then
    echo "curl failure unexpectedly succeeded" >&2
    exit 1
fi
python3 -c 'import json,sys; assert json.load(sys.stdin)["error"] == "model limits fetch failed"' <<<"$output"

if output=$(FAKE_USAGE_BODY="$valid" run_fetch custom ""); then
    echo "empty custom proxy unexpectedly succeeded" >&2
    exit 1
fi
python3 -c 'import json,sys; assert json.load(sys.stdin)["error"] == "Custom proxy URL is empty"' <<<"$output"

echo "fetch_model_limits tests passed"
