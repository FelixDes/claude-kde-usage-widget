#!/bin/bash
# Fetch Claude rate limit headers by making a minimal API call.
# Outputs JSON for the QML widget to consume.
#
# Usage: fetch_limits.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

PROXY_MODE="${1:-env}"
PROXY_URL="${2:-}"
CREDS_FILE="${CREDS_FILE:-$HOME/.claude/.credentials.json}"
export CREDS_FILE

API_URL="https://api.anthropic.com/v1/messages"
PROBE_BODY='{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'

err() {
    printf '{"error": "%s"}\n' "$1"
    exit 1
}

# Prints two lines: access token, subscription type.
read_creds() {
    python3 - <<'PYEOF'
import json, os, sys
try:
    with open(os.environ['CREDS_FILE']) as f:
        oauth = json.load(f)['claudeAiOauth']
    print(oauth['accessToken'])
    print(oauth.get('subscriptionType', ''))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
}

load_creds() {
    local creds
    creds=$(read_creds) || return 1
    ACCESS_TOKEN=$(sed -n 1p <<<"$creds")
    SUBSCRIPTION_TYPE=$(sed -n 2p <<<"$creds")
    [ -n "$ACCESS_TOKEN" ]
}

# Prints anthropic-ratelimit-* response headers, empty on failure.
fetch_headers() {
    local args=(-si
        -H "Authorization: Bearer $ACCESS_TOKEN"
        -H "anthropic-version: 2023-06-01"
        -H "content-type: application/json"
        -d "$PROBE_BODY"
        --max-time 10)
    case "$PROXY_MODE" in
        none)   args+=(--noproxy '*') ;;
        custom) [ -n "$PROXY_URL" ] && args+=(--proxy "$PROXY_URL") ;;
        *)      ;;  # env: curl reads HTTP_PROXY/HTTPS_PROXY automatically
    esac
    curl "${args[@]}" "$API_URL" 2>/dev/null | grep -i '^anthropic-ratelimit'
}

[ -f "$CREDS_FILE" ] || err "No credentials file at ~/.claude/.credentials.json"
load_creds || err "Failed to read access token"

HEADERS=$(fetch_headers)

# Token may be stale (e.g. right after boot). Spawn claude briefly to
# trigger OAuth refresh, re-read the token, then retry once.
if [ -z "$HEADERS" ] && command -v claude >/dev/null 2>&1; then
    timeout 5 claude -p "x" >/dev/null 2>&1 || true
    load_creds && HEADERS=$(fetch_headers)
fi

[ -n "$HEADERS" ] || err "API call failed or no rate limit headers"

export HEADERS SUBSCRIPTION_TYPE
python3 - <<'PYEOF'
import json, os, re, time

raw = os.environ['HEADERS']

def get(name):
    m = re.search(rf'{name}:\s*(.+)', raw, re.IGNORECASE)
    return m.group(1).strip() if m else None

def to_float(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0

def fmt_reset(ts_str):
    if not ts_str:
        return None
    try:
        ts = int(ts_str)
        mins = round((ts - time.time()) / 60)
        if mins < 0:
            return "now"
        if mins < 60:
            return f"{mins}m"
        hours = round(mins / 60)
        if hours < 24:
            return f"{hours}h"
        days = round(hours / 24)
        return f"{days}d"
    except Exception:
        return ts_str

def window(prefix):
    reset = get(f"anthropic-ratelimit-unified-{prefix}-reset")
    return {
        "status": get(f"anthropic-ratelimit-unified-{prefix}-status"),
        "utilization": to_float(get(f"anthropic-ratelimit-unified-{prefix}-utilization")),
        "reset_ts": reset,
        "reset_in": fmt_reset(reset),
    }

result = {
    "status": get("anthropic-ratelimit-unified-status"),
    "fallback": get("anthropic-ratelimit-unified-fallback"),
    "fallback_pct": get("anthropic-ratelimit-unified-fallback-percentage"),
    "representative_claim": get("anthropic-ratelimit-unified-representative-claim"),
    "h5": window("5h"),
    "d7": window("7d"),
    "plan": os.environ.get("SUBSCRIPTION_TYPE", ""),
    "updated_at": int(time.time()),
}
print(json.dumps(result))
PYEOF
