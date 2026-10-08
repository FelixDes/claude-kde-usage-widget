# Claude Limits Widget

KDE Plasma 6 panel widget that shows your Claude API rate limit usage in real time.

Displays the 5-hour and 7-day usage windows, plus the separate Fable weekly limit when it is available for your plan.
Each window has a usage bar, utilization percentage, and time until reset. The popup also shows Claude's service status and any active incidents pulled from
[status.claude.com](https://status.claude.com/), so you stay aware of outages; the panel view flags a degraded status
with a colored dot. Compact view lives in the panel; click to open the full popup.

**KDE Store:** https://www.opendesktop.org/p/2359310

## How it works

On each refresh the widget runs a shell script that:

1. Reads your OAuth token from `~/.claude/.credentials.json` (written by Claude Code)
2. Makes a minimal `POST /v1/messages` call to `api.anthropic.com` using the cheapest model (
   `claude-haiku-4-5-20251001`) with `max_tokens: 1`
3. Extracts the `anthropic-ratelimit-unified-*` response headers
4. Returns the parsed values as JSON to the widget

The optional Fable weekly window is read separately from Claude's OAuth usage endpoint every 15 minutes. This request
does not run a model or consume tokens. Accounts without a model-scoped Fable allowance simply do not show the Fable
row. Fable usage is part of the regular weekly allowance on eligible plans, not an additional weekly pool.

> **Note:** Every refresh burns real tokens. The call is as small as possible (1 output token), but it is a real API
> request that counts against your usage. Set the refresh interval accordingly.

Separately, the widget polls `status.claude.com/api/v2/summary.json` for service status and active incidents. The
interval is configurable and defaults to 5 minutes. That request is unauthenticated and **does not cost any tokens**.

## Requirements

- KDE Plasma 6
- `curl`, `python3`, `bash`
- An active Claude account with Claude Code installed (provides `~/.claude/.credentials.json`)

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
plasmashell --replace &
```

## Settings

Right-click the widget → Configure.

| Setting         | Description                                                 |
|-----------------|-------------------------------------------------------------|
| Show title      | Show/hide the "Claude Limits" heading in the popup          |
| Service status  | Show/hide Claude service status and incident warnings       |
| Limits interval | How often to poll the limits API (minutes). Default: 15     |
| Status interval | How often to poll the public status API (minutes). Default: 5 |
| Proxy mode      | See below                                                   |

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
2. Push a matching tag: `git tag v1.1 && git push origin v1.1`.
3. GitHub Actions runs the tests, builds `claude-limits-widget-v<version>.tar.gz` and attaches it to a GitHub release.
4. KDE Store (store.kde.org / pling.com) has no public upload API, so upload the archive from the release on the
   product's "Files" page by hand.
