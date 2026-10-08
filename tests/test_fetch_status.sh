#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin"' EXIT

cat >"$fake_bin/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"${FAKE_ARGS_FILE:?}"
printf '%s' "${FAKE_STATUS_BODY:-}"
[ "${FAKE_CURL_FAIL:-0}" = "1" ] && exit 7
exit 0
EOF
chmod +x "$fake_bin/curl"

run_fetch() {
    FAKE_ARGS_FILE="$fake_bin/args" PATH="$fake_bin:$PATH" \
        "$project_dir/contents/code/fetch_status.sh" "$@"
}

valid='{"status":{"indicator":"minor","description":"Degraded"},"incidents":[{"name":"Latency","impact":"minor","status":"monitoring"}]}'
output=$(FAKE_STATUS_BODY="$valid" run_fetch none)
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["indicator"] == "minor"; assert d["incidents"][0]["name"] == "Latency"' <<<"$output"
python3 - "$fake_bin/args" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
i = args.index("--noproxy")
assert args[i + 1] == "*"
assert not any("uthorization" in arg for arg in args)
PY

proxy_url='http://proxy.example:8080/path?x=1&y=2'
FAKE_STATUS_BODY="$valid" run_fetch custom "$proxy_url" >/dev/null
python3 - "$fake_bin/args" "$proxy_url" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
i = args.index("--proxy")
assert args[i + 1] == sys.argv[2]
PY

FAKE_STATUS_BODY="$valid" run_fetch env >/dev/null
python3 - "$fake_bin/args" <<'PY'
import sys
args = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert "--proxy" not in args
assert "--noproxy" not in args
PY

if output=$(FAKE_STATUS_BODY='not json' run_fetch none); then
    echo "malformed JSON unexpectedly succeeded" >&2
    exit 1
fi
python3 -c 'import json,sys; assert json.load(sys.stdin)["error"] == "status parse failed"' <<<"$output"

if output=$(FAKE_CURL_FAIL=1 FAKE_STATUS_BODY="$valid" run_fetch none); then
    echo "curl failure unexpectedly succeeded" >&2
    exit 1
fi
python3 -c 'import json,sys; assert json.load(sys.stdin)["error"] == "status fetch failed"' <<<"$output"

echo "fetch_status tests passed"
