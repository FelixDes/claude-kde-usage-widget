#!/bin/bash
# Fetch Claude rate limit headers by making a minimal API call.
# Outputs JSON for the QML widget to consume.

PROXY_MODE="${1:-env}"
PROXY_URL="${2:-}"
CREDS_FILE="$HOME/.claude/.credentials.json"

if [ ! -f "$CREDS_FILE" ]; then
    echo '{"error": "No credentials file at ~/.claude/.credentials.json"}'
    exit 1
fi

# Read creds — pass file path via env, not shell expansion inside Python string
export CREDS_FILE
CREDS_JSON=$(python3 - <<'PYEOF'
import json, sys, os
try:
    with open(os.environ['CREDS_FILE']) as f:
        d = json.load(f)
    oauth = d['claudeAiOauth']
    print(oauth['accessToken'])
    print(oauth.get('subscriptionType', ''))
except Exception as e:
    print('', file=sys.stdout)
    print(str(e), file=sys.stderr)
    sys.exit(1)
PYEOF
)

ACCESS_TOKEN=$(echo "$CREDS_JSON" | sed -n '1p')
SUBSCRIPTION_TYPE=$(echo "$CREDS_JSON" | sed -n '2p')

if [ -z "$ACCESS_TOKEN" ]; then
    echo '{"error": "Failed to read access token"}'
    exit 1
fi

CURL_ARGS=(-si
    -H "Authorization: Bearer $ACCESS_TOKEN"
    -H "anthropic-version: 2023-06-01"
    -H "content-type: application/json"
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
    --max-time 10)

case "$PROXY_MODE" in
    none)   CURL_ARGS+=(--noproxy '*') ;;
    custom) [[ -n "$PROXY_URL" ]] && CURL_ARGS+=(--proxy "$PROXY_URL") ;;
    *)      ;;  # env: curl reads HTTP_PROXY/HTTPS_PROXY automatically
esac

RESPONSE=$(curl "${CURL_ARGS[@]}" "https://api.anthropic.com/v1/messages" 2>/dev/null)

HEADERS=$(echo "$RESPONSE" | grep -i "^anthropic-ratelimit")

if [ -z "$HEADERS" ]; then
    echo '{"error": "API call failed or no rate limit headers"}'
    exit 1
fi

python3 - <<PYEOF
import sys, re, json, time, os

raw = """$HEADERS"""

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

result = {
    "status": get("anthropic-ratelimit-unified-status"),
    "fallback": get("anthropic-ratelimit-unified-fallback"),
    "fallback_pct": get("anthropic-ratelimit-unified-fallback-percentage"),
    "representative_claim": get("anthropic-ratelimit-unified-representative-claim"),
    "h5": {
        "status": get("anthropic-ratelimit-unified-5h-status"),
        "utilization": to_float(get("anthropic-ratelimit-unified-5h-utilization")),
        "reset_ts": get("anthropic-ratelimit-unified-5h-reset"),
        "reset_in": fmt_reset(get("anthropic-ratelimit-unified-5h-reset")),
    },
    "d7": {
        "status": get("anthropic-ratelimit-unified-7d-status"),
        "utilization": to_float(get("anthropic-ratelimit-unified-7d-utilization")),
        "reset_ts": get("anthropic-ratelimit-unified-7d-reset"),
        "reset_in": fmt_reset(get("anthropic-ratelimit-unified-7d-reset")),
    },
    "plan": "$SUBSCRIPTION_TYPE",
    "updated_at": int(time.time()),
}
print(json.dumps(result))
PYEOF
