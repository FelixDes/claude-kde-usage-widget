# Shared helpers for the fetch scripts: proxy settings, OAuth tokens and
# authenticated curl requests. Source this file, do not execute it.
#
# The token is Claude Code's short-lived OAuth token from
# ~/.claude/.credentials.json. When it is expired or rejected, the claude CLI is
# run once to refresh it.

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CREDS_FILE="${CREDS_FILE:-$CLAUDE_DIR/.credentials.json}"
REFRESH_LOCK="${CLAUDE_WIDGET_REFRESH_LOCK:-${XDG_RUNTIME_DIR:-/tmp}/claude-limits-widget-refresh.lock}"

# err MESSAGE [HTTP_CODE] [FALLBACK]: prints an error object and exits.
# FALLBACK=true tells the widget another source may still work.
err() {
    printf '{"error": "%s", "http_code": "%s", "fallback": %s}\n' \
        "$1" "${2:-}" "${3:-false}"
    exit 1
}

# Appends a successful result to the usage history; never fails the fetch.
record_history() {
    printf '%s' "$1" | python3 -I "$(dirname "${BASH_SOURCE[0]}")/history.py" record \
        >/dev/null 2>&1 || true
}

# Sets PROXY_ARGS from the widget's proxy mode (none | env | custom).
setup_proxy() {
    PROXY_ARGS=()
    case "$1" in
        none)   PROXY_ARGS=(--noproxy '*') ;;
        env)    ;;  # curl reads HTTP_PROXY/HTTPS_PROXY itself
        custom)
            [ -n "$2" ] || err "Custom proxy URL is empty"
            # An empty no-proxy list prevents NO_PROXY from bypassing the
            # explicitly selected custom proxy.
            PROXY_ARGS=(--noproxy '' --proxy "$2")
            ;;
        *)      err "Invalid proxy mode" ;;
    esac
}

valid_token() {
    [[ "$1" =~ ^[A-Za-z0-9._~+/=-]+$ ]]
}

# Sets CREDS_TOKEN, CREDS_PLAN, CREDS_TIER and CREDS_EXPIRED (1/0) from Claude
# Code's credentials file. CREDS_TIER is the plan's usage multiplier relative to
# Pro (1, 5, 20) or "" when unknown. Returns non-zero without a usable token.
load_creds() {
    CREDS_TOKEN=""
    CREDS_PLAN=""
    CREDS_TIER=""
    CREDS_EXPIRED=0
    [ -f "$CREDS_FILE" ] || return 1

    local creds
    creds=$(python3 - "$CREDS_FILE" <<'PYEOF'
import json
import re
import sys
import time

try:
    with open(sys.argv[1], encoding="utf-8") as credentials:
        oauth = json.load(credentials)["claudeAiOauth"]
    token = oauth["accessToken"]
    if not isinstance(token, str) or not token:
        raise ValueError("missing access token")
except Exception as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(1)

plan = oauth.get("subscriptionType")
plan = plan if isinstance(plan, str) else ""
# rateLimitTier looks like "default_claude_max_5x"; Pro has no multiplier.
rate_tier = oauth.get("rateLimitTier")
match = re.search(r"(\d+)x\b", rate_tier) if isinstance(rate_tier, str) else None
tier = match.group(1) if match else ("1" if plan == "pro" else "")
expires_at = oauth.get("expiresAt")
# A token that expires within a minute is treated as already expired.
expired = (isinstance(expires_at, (int, float)) and not isinstance(expires_at, bool)
           and expires_at / 1000 < time.time() + 60)
print(token)
print(plan)
print(1 if expired else 0)
print(tier)
PYEOF
) || return 1

    CREDS_TOKEN=$(sed -n 1p <<<"$creds")
    CREDS_PLAN=$(sed -n 2p <<<"$creds")
    CREDS_EXPIRED=$(sed -n 3p <<<"$creds")
    CREDS_TIER=$(sed -n 4p <<<"$creds")
    valid_token "$CREDS_TOKEN" || { CREDS_TOKEN=""; return 1; }
}

# Runs the claude CLI so it refreshes its OAuth token, then reloads the
# credentials. $1 is the token that failed. A lock keeps parallel fetches from
# spawning claude twice; whoever waited reuses the already refreshed token.
refresh_creds() {
    command -v claude >/dev/null 2>&1 || return 1
    (
        if command -v flock >/dev/null 2>&1; then
            flock -w 60 9 || exit 1
        fi
        if load_creds && [ "$CREDS_EXPIRED" = 0 ] && [ "$CREDS_TOKEN" != "$1" ]; then
            exit 0
        fi
        timeout 30 claude -p x --model haiku >/dev/null 2>&1 || true
    ) 9>"$REFRESH_LOCK"
    load_creds
}

# Runs curl with the proxy settings and a bearer token, passing the remaining
# arguments through. The token goes in via stdin so it never appears in the
# process list. Sets HTTP_CODE ("000" when the request did not complete).
api_request() {
    local token=$1
    shift
    # -q must be curl's first option so a user curlrc cannot add credentials,
    # cookies, extra URLs, or other request-changing options.
    HTTP_CODE=$(printf 'header = "Authorization: Bearer %s"\n' "$token" |
        curl -q -sS --max-time 10 --config - "${PROXY_ARGS[@]}" \
            -w '%{http_code}' "$@" 2>/dev/null) || true
    [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || HTTP_CODE=000
}

# Calls "$1 <token>" (a function that sets HTTP_CODE) with Claude Code's
# token, refreshing it first when it has expired and once more on a 401.
with_token() {
    local request=$1 refreshed=0
    HTTP_CODE=000

    load_creds || err "No Claude Code credentials at ~/.claude/.credentials.json: log in to Claude Code"

    if [ "$CREDS_EXPIRED" = 1 ]; then
        refresh_creds "$CREDS_TOKEN" || true
        refreshed=1
    fi
    "$request" "$CREDS_TOKEN"
    if [ "$HTTP_CODE" = 401 ] && [ "$refreshed" = 0 ] && refresh_creds "$CREDS_TOKEN"; then
        "$request" "$CREDS_TOKEN"
    fi
}

# Maps a failed HTTP status to a short user-facing message.
http_error() {
    case "$1" in
        000) printf 'Network error: cannot reach api.anthropic.com' ;;
        401) printf 'Token expired or revoked: open Claude Code to log in again' ;;
        403) printf 'Access denied (HTTP 403)' ;;
        429) printf 'Rate limited (HTTP 429)' ;;
        *)   printf 'Request failed (HTTP %s)' "$1" ;;
    esac
}
