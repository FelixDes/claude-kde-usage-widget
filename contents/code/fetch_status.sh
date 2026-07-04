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

args=(-s --max-time 10)
case "$PROXY_MODE" in
    none)   args+=(--noproxy '*') ;;
    custom) [ -n "$PROXY_URL" ] && args+=(--proxy "$PROXY_URL") ;;
    *)      ;;  # env: curl reads HTTP_PROXY/HTTPS_PROXY automatically
esac

BODY=$(curl "${args[@]}" "$STATUS_URL" 2>/dev/null)
[ -n "$BODY" ] || { printf '{"error": "status fetch failed"}\n'; exit 1; }

export BODY
python3 - <<'PYEOF'
import json, os

try:
    d = json.loads(os.environ["BODY"])
except Exception:
    print('{"error": "status parse failed"}')
    raise SystemExit(0)

st = d.get("status", {}) or {}
incidents = []
for it in d.get("incidents", []) or []:
    incidents.append({
        "name": it.get("name", ""),
        "impact": it.get("impact", ""),
        "status": it.get("status", ""),
        "shortlink": it.get("shortlink", ""),
    })

print(json.dumps({
    "indicator": st.get("indicator", ""),
    "description": st.get("description", ""),
    "incidents": incidents,
}))
PYEOF
