# Claude Limits Widget

KDE Plasma 6 panel widget that shows your Claude API rate limit usage in real time.

Displays two windows: 5-hour and 7-day, each with a usage bar, utilization percentage, and time until reset. Compact
view lives in the panel; click to open the full popup.

**KDE Store:** https://www.opendesktop.org/p/2359310

## How it works

On each refresh the widget runs a shell script that:

1. Reads your OAuth token from `~/.claude/.credentials.json` (written by Claude Code)
2. Makes a minimal `POST /v1/messages` call to `api.anthropic.com` using the cheapest model (
   `claude-haiku-4-5-20251001`) with `max_tokens: 1`
3. Extracts the `anthropic-ratelimit-unified-*` response headers
4. Returns the parsed values as JSON to the widget

> **Note:** Every refresh burns real tokens. The call is as small as possible (1 output token), but it is a real API
> request that counts against your usage. Set the refresh interval accordingly.

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

| Setting          | Description                                        |
|------------------|----------------------------------------------------|
| Show title       | Show/hide the "Claude Limits" heading in the popup |
| Refresh interval | How often to poll the API (minutes). Default: 15   |
| Proxy mode       | See below                                          |

### Proxy settings

| Mode       | Behavior                                                               |
|------------|------------------------------------------------------------------------|
| No proxy   | Passes `--noproxy '*'` to curl, bypassing any system proxy             |
| System env | curl reads `HTTP_PROXY` / `HTTPS_PROXY` from the environment (default) |
| Custom URL | Uses the URL you provide, e.g. `http://proxy.example.com:8080`         |

## License

MIT
