#!/bin/bash
# Fetch Claude service status and any active incidents from the public
# status page (Atlassian Statuspage). This is an unauthenticated, free
# request — it does NOT burn API tokens, unlike fetch_limits.sh.
#
# Usage: fetch_status.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

PROXY_MODE="${1:-env}"
PROXY_URL="${2:-}"

# summary.json bundles overall status + unresolved incidents in one call.
STATUS_URL="https://status.claude.com/api/v2/summary.json"

err() {
    printf '{"error": "%s"}\n' "$1"
    exit 1
}

args=(-fsS --max-time 10)
case "$PROXY_MODE" in
    none)   args+=(--noproxy '*') ;;
    custom) [ -n "$PROXY_URL" ] && args+=(--proxy "$PROXY_URL") ;;
    *)      ;;  # env: curl reads HTTP_PROXY/HTTPS_PROXY automatically
esac

BODY=$(curl "${args[@]}" "$STATUS_URL" 2>/dev/null) || err "status fetch failed"
[ -n "$BODY" ] || err "status fetch failed"

export BODY
python3 - <<'PYEOF'
import json, os

try:
    d = json.loads(os.environ["BODY"])
    if not isinstance(d, dict):
        raise ValueError("root is not an object")

    st = d.get("status")
    if not isinstance(st, dict) or not isinstance(st.get("indicator"), str) or not st["indicator"]:
        raise ValueError("missing status indicator")

    raw_incidents = d.get("incidents", [])
    if not isinstance(raw_incidents, list):
        raw_incidents = []
except Exception:
    print('{"error": "status parse failed"}')
    raise SystemExit(1)

incidents = []
for it in raw_incidents:
    if not isinstance(it, dict):
        continue
    incidents.append({
        "name": it.get("name", "") if isinstance(it.get("name", ""), str) else "",
        "impact": it.get("impact", "") if isinstance(it.get("impact", ""), str) else "",
        "status": it.get("status", "") if isinstance(it.get("status", ""), str) else "",
        "shortlink": it.get("shortlink", "") if isinstance(it.get("shortlink", ""), str) else "",
    })

print(json.dumps({
    "indicator": st.get("indicator", ""),
    "description": st.get("description", "") if isinstance(st.get("description", ""), str) else "",
    "incidents": incidents,
}))
PYEOF
