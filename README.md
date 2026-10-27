# Claude Limits Widget

KDE Plasma 6 panel widget that shows your Claude API rate limit usage in real time.

Displays the 5-hour and 7-day usage windows, plus the separate Fable weekly limit when it is available for your plan.
Each window has a usage bar, utilization percentage, and time until reset. The popup also shows Claude's service status and any active incidents pulled from
[status.claude.com](https://status.claude.com/), so you stay aware of outages; the panel view flags a degraded status
with a colored dot. Compact view lives in the panel; click to open the full popup.

**KDE Store:** https://www.opendesktop.org/p/2359310

## How it works

On each refresh (every 15 minutes by default, at most every 5) the widget runs a shell script that:

1. Reads Claude Code's OAuth token, refreshing it if needed (see [Authentication](#authentication))
2. Calls Claude's OAuth usage endpoint, the one behind Claude Code's `/usage`. It returns the 5-hour and 7-day
   windows, the separate Fable weekly window (when your plan has one) and this week's usage per client. The request
   does not run a model and **does not cost any tokens**.
3. Returns the parsed values as JSON to the widget and appends them to the usage history

The usage endpoint throttles frequent requests. While it answers HTTP 429, the widget falls back to a minimal
`POST /v1/messages` call (`claude-haiku-4-5-20251001`, `max_tokens: 1`) and reads the
`anthropic-ratelimit-unified-*` response headers instead. That fallback is a real API request and costs a few tokens.

Accounts without a model-scoped Fable allowance simply do not show the Fable row. Fable usage is part of the regular
weekly allowance on eligible plans, not an additional weekly pool.

Failed requests (for example while the network or a VPN is still coming up after login) are retried after 15 s and
then with a doubling delay, up to the regular refresh interval.

Separately, the widget polls `status.claude.com/api/v2/summary.json` for service status and active incidents. The
interval is configurable and defaults to 5 minutes. That request is unauthenticated and **does not cost any tokens**.

## Usage statistics

The chart button in the popup opens a statistics window built from the recorded history
(`~/.local/share/claude-limits-widget/history.jsonl`, one sample per refresh, kept for 180 days). There is no
history API, so the window only knows what the widget has seen since it was installed.

- **Week / Session**: the current window's usage, the even pace to its reset, a projection from the recent burn
  rate, and (for weeks) the previous three weeks for comparison. The header says whether you are on track or when
  you would hit 100% before the reset.
- **Plan fit**: every 5-hour session of the last 30 days as a bar, with lines where Pro (x1), Max 5x and Max 20x
  would run out. Below it, how often each plan would have run out and the price difference (prices are set in the
  widget settings). It needs about two weeks of data to be meaningful.

Plan lines use the nominal 5x/20x session multipliers. Weekly limits are not published per plan, so the weekly
comparisons are approximate (marked with ≈). Above your own plan the data stops at 100%, because you were blocked
there, so the window can only say how often a bigger plan would have saved you from a block.

## Requirements

- KDE Plasma 6
- `curl`, `python3`, `bash`
- An active Claude account with Claude Code installed (provides `~/.claude/.credentials.json`)

## Authentication

The widget uses Claude Code's OAuth token from `~/.claude/.credentials.json`. It lives for a few hours. When it has
expired or is rejected, the widget runs `claude -p` once (with Haiku) so Claude Code refreshes it, then retries. The
token is passed to `curl` on stdin, so it never appears in the process list.

## Installation

```bash
kpackagetool6 --install . --type Plasma/Applet
```

To upgrade after changes:

```bash
kpackagetool6 --upgrade . --type Plasma/Applet
```

Then restart Plasma:

```bash
systemctl --user restart plasma-plasmashell.service
```

## Settings

Right-click the widget → Configure.

| Setting         | Description                                                 |
|-----------------|-------------------------------------------------------------|
| Show title      | Show/hide the "Claude Limits" heading in the popup          |
| Service status  | Show/hide Claude service status and incident warnings       |
| Limits interval | How often to poll the usage endpoint (minutes). Default: 15, minimum: 5 |
| Status interval | How often to poll the public status API (minutes). Default: 5 |
| Proxy mode      | See below                                                   |
| Plan prices     | Monthly prices of Pro, Max 5x and Max 20x, and the currency, for the plan fit |

### Proxy settings

| Mode       | Behavior                                                               |
|------------|------------------------------------------------------------------------|
| No proxy   | Passes `--noproxy '*'` to curl, bypassing any system proxy             |
| System env | curl reads `HTTP_PROXY` / `HTTPS_PROXY` from the environment (default) |
| Custom URL | Uses the URL you provide, e.g. `http://proxy.example.com:8080`         |

## License

MIT

## Releasing

1. Bump `Version` in `metadata.json`.
2. Push a matching tag: `git tag v1.2 && git push origin v1.2`.
3. GitHub Actions runs the tests, builds `claude-limits-widget-v<version>.tar.gz` and attaches it to a GitHub release.
4. KDE Store (store.kde.org / pling.com) has no public upload API, so upload the archive from the release on the
   product's "Files" page by hand.
