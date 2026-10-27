#!/bin/bash
# Fetch Claude rate limit headers by making a minimal API call. This costs a
# few tokens, so the widget only uses it when the free usage endpoint
# (fetch_usage.sh) is throttled. Outputs JSON for the QML widget to consume.
#
# Usage: fetch_limits.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_proxy "${1:-env}" "${2:-}"

API_URL="https://api.anthropic.com/v1/messages"
PROBE_BODY='{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'

HEADER_FILE=$(mktemp)
trap 'rm -f "$HEADER_FILE"' EXIT

probe() {
    : >"$HEADER_FILE"
    api_request "$1" -o /dev/null -D "$HEADER_FILE" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$PROBE_BODY" "$API_URL"
}

with_token probe
# A 429 still carries the rate limit headers, so only their presence matters.
HEADERS=$(grep -i '^anthropic-ratelimit' "$HEADER_FILE" | tr -d '\r')
[ -n "$HEADERS" ] || err "$(http_error "$HTTP_CODE")" "$HTTP_CODE"

load_creds || true
SUBSCRIPTION_TYPE="$CREDS_PLAN"
SUBSCRIPTION_TIER="$CREDS_TIER"
export HEADERS SUBSCRIPTION_TYPE SUBSCRIPTION_TIER
OUTPUT=$(python3 - <<'PYEOF'
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

tier = os.environ.get("SUBSCRIPTION_TIER", "")
result = {
    "source": "probe",
    "status": get("anthropic-ratelimit-unified-status"),
    "fallback": get("anthropic-ratelimit-unified-fallback"),
    "fallback_pct": get("anthropic-ratelimit-unified-fallback-percentage"),
    "representative_claim": get("anthropic-ratelimit-unified-representative-claim"),
    "h5": window("5h"),
    "d7": window("7d"),
    "plan": os.environ.get("SUBSCRIPTION_TYPE", ""),
    "tier": int(tier) if tier.isdigit() else None,
    "updated_at": int(time.time()),
}
print(json.dumps(result))
PYEOF
)
printf '%s\n' "$OUTPUT"
record_history "$OUTPUT"
