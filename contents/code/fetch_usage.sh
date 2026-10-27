#!/bin/bash
# Fetch 5-hour, 7-day and model-scoped weekly limits (for example Fable) from
# Claude's OAuth usage endpoint. This request does not run a model and does not
# consume tokens. Each successful result is also appended to the usage history.
#
# Usage: fetch_usage.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_proxy "${1:-env}" "${2:-}"

USAGE_URL="https://api.anthropic.com/api/oauth/usage"

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

usage_request() {
    : >"$BODY_FILE"
    api_request "$1" -o "$BODY_FILE" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "content-type: application/json" \
        -H "user-agent: claude-kde-usage-widget/1.0" \
        "$USAGE_URL"
}

with_token usage_request
if [ "$HTTP_CODE" != 200 ]; then
    # The endpoint throttles hard; the widget then falls back to the probe.
    fallback=false
    [ "$HTTP_CODE" = 429 ] && fallback=true
    err "$(http_error "$HTTP_CODE")" "$HTTP_CODE" "$fallback"
fi
[ -s "$BODY_FILE" ] || err "Empty response from usage endpoint" 200 true

OUTPUT=$(python3 - "$BODY_FILE" "$CREDS_PLAN" "$CREDS_TIER" <<'PYEOF'
import json
import math
import sys
import time


def fail(message):
    print(json.dumps({"error": message, "http_code": "200", "fallback": True}))
    raise SystemExit(1)


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return max(0.0, float(value))


def text(value):
    return value.strip() if isinstance(value, str) else ""


def reset(value):
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        return None
    return value


def window(percent, reset_ts, severity):
    return {
        "status": "limited" if percent >= 100 else "allowed",
        "severity": severity,
        "utilization": percent / 100.0,
        "reset_ts": reset(reset_ts),
        "reset_in": "",
    }


try:
    with open(sys.argv[1], encoding="utf-8") as body:
        payload = json.load(body)
    if not isinstance(payload, dict):
        raise ValueError("root is not an object")
    raw_limits = payload.get("limits")
    if raw_limits is None:
        raw_limits = []
    elif not isinstance(raw_limits, list):
        raise ValueError("limits is not an array")
except Exception:
    fail("Usage response parse failed")

limits = [item for item in raw_limits if isinstance(item, dict)]


def by_kind(kind):
    return next((item for item in limits if item.get("kind") == kind), None)


def top_window(key, kind):
    """5h/7d from the top-level object, else from the matching limits entry."""
    item = by_kind(kind) or {}
    severity = text(item.get("severity")).lower()
    top = payload.get(key)
    if isinstance(top, dict) and number(top.get("utilization")) is not None:
        return window(number(top["utilization"]), top.get("resets_at"), severity)
    if number(item.get("percent")) is not None:
        return window(number(item["percent"]), item.get("resets_at"), severity)
    return None


h5 = top_window("five_hour", "session")
d7 = top_window("seven_day", "weekly_all")
if h5 is None and d7 is None:
    fail("Usage response has no 5h/7d limits")

model_limits = []
for item in limits:
    if item.get("kind") != "weekly_scoped":
        continue
    scope = item.get("scope")
    model = scope.get("model") if isinstance(scope, dict) else None
    label = text(model.get("display_name")) if isinstance(model, dict) else ""
    percent = number(item.get("percent"))
    if not label or percent is None:
        continue
    entry = window(percent, item.get("resets_at"), text(item.get("severity")).lower())
    entry["label"] = label
    model_limits.append(entry)

# Share of this week's usage per client (Claude Code, chats, ...).
breakdown = []
rows = payload.get("seven_day_breakdown")
rows = rows.get("rows") if isinstance(rows, dict) else None
for row in rows if isinstance(rows, list) else []:
    if not isinstance(row, dict):
        continue
    label = text(row.get("display_name"))
    percent = number(row.get("percent"))
    if label and percent is not None:
        breakdown.append({"key": text(row.get("key")), "label": label, "percent": percent})

tier = sys.argv[3]
print(json.dumps({
    "source": "usage",
    "h5": h5,
    "d7": d7,
    "model_limits": model_limits,
    "breakdown": breakdown,
    "plan": sys.argv[2],
    "tier": int(tier) if tier.isdigit() else None,
    "updated_at": int(time.time()),
}))
PYEOF
) || { printf '%s\n' "$OUTPUT"; exit 1; }

printf '%s\n' "$OUTPUT"
record_history "$OUTPUT"
