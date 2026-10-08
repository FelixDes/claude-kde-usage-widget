#!/bin/bash
# Fetch model-scoped weekly limits (for example Fable) from Claude's OAuth
# usage endpoint. This request does not run a model and does not consume tokens.
#
# Usage: fetch_model_limits.sh [proxy_mode] [proxy_url]
#   proxy_mode: none | env (default) | custom

PROXY_MODE="${1:-env}"
PROXY_URL="${2:-}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS_FILE="${CREDS_FILE:-$CLAUDE_DIR/.credentials.json}"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"

err() {
    printf '{"error": "%s"}\n' "$1"
    exit 1
}

read_token() {
    python3 - "$CREDS_FILE" <<'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as credentials:
        token = json.load(credentials)["claudeAiOauth"]["accessToken"]
    if not isinstance(token, str) or not token:
        raise ValueError("missing access token")
    print(token)
except Exception as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(1)
PYEOF
}

if [ -f "$CREDS_FILE" ]; then
    ACCESS_TOKEN=$(read_token) || err "Failed to read access token"
elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    ACCESS_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"
else
    err "No credentials file at ~/.claude/.credentials.json"
fi

# -q must be curl's first option so a user curlrc cannot add credentials,
# cookies, extra URLs, or other request-changing options.
args=(-q -fsS --max-time 10
    -H "Authorization: Bearer $ACCESS_TOKEN"
    -H "anthropic-beta: oauth-2025-04-20"
    -H "content-type: application/json"
    -H "user-agent: claude-kde-usage-widget/1.0")

case "$PROXY_MODE" in
    none)   args+=(--noproxy '*') ;;
    env)    ;;
    custom)
        [ -n "$PROXY_URL" ] || err "Custom proxy URL is empty"
        # An empty no-proxy list prevents NO_PROXY from bypassing the explicitly
        # selected custom proxy.
        args+=(--noproxy '' --proxy "$PROXY_URL")
        ;;
    *)      err "Invalid proxy mode" ;;
esac

BODY=$(curl "${args[@]}" "$USAGE_URL" 2>/dev/null) || err "model limits fetch failed"
[ -n "$BODY" ] || err "model limits fetch failed"

export BODY
python3 - <<'PYEOF'
import json
import math
import os

try:
    payload = json.loads(os.environ["BODY"])
    if not isinstance(payload, dict):
        raise ValueError("root is not an object")
    raw_limits = payload.get("limits")
    if raw_limits is None:
        raw_limits = []
    elif not isinstance(raw_limits, list):
        raise ValueError("limits is not an array")
except Exception:
    print('{"error": "model limits parse failed"}')
    raise SystemExit(1)

model_limits = []
for item in raw_limits:
    if not isinstance(item, dict) or item.get("kind") != "weekly_scoped":
        continue

    scope = item.get("scope")
    model = scope.get("model") if isinstance(scope, dict) else None
    label = model.get("display_name") if isinstance(model, dict) else None
    percent = item.get("percent")
    if (not isinstance(label, str) or not label.strip()
            or isinstance(percent, bool) or not isinstance(percent, (int, float))
            or not math.isfinite(percent)):
        continue

    percent = max(0.0, float(percent))
    reset_ts = item.get("resets_at")
    if not isinstance(reset_ts, (str, int, float)) or isinstance(reset_ts, bool):
        reset_ts = None

    severity = item.get("severity") if isinstance(item.get("severity"), str) else ""
    severity = severity.lower()
    limited = percent >= 100
    model_limits.append({
        "label": label.strip(),
        "status": "limited" if limited else "allowed",
        "severity": severity,
        "utilization": percent / 100.0,
        "reset_ts": reset_ts,
        "reset_in": "",
    })

print(json.dumps({"model_limits": model_limits}))
PYEOF
