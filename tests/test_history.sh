#!/bin/bash
# history.py: recording samples, grouping windows, pace and plan fit.
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

CLAUDE_WIDGET_HISTORY="$work/history.jsonl" python3 -I -B - "$project_dir/contents/code/history.py" <<'PY'
import importlib.util, io, json, os, sys

spec = importlib.util.spec_from_file_location("history", sys.argv[1])
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
path = os.environ["CLAUDE_WIDGET_HISTORY"]
H = 3600
RESET = 1793119200            # 2026-10-27 16:40 UTC
WEEK_RESET = 1793430000


def record(result, now):
    return h.record(io.StringIO(json.dumps(result)), now)


def reset_history(samples=()):
    with open(path, "w") as f:
        for s in samples:
            f.write(json.dumps(s) + "\n")


# --- record ---------------------------------------------------------------
usage = {"source": "usage", "tier": 5, "updated_at": RESET - 2 * H,
         "h5": {"utilization": 0.18, "reset_ts": "2026-10-27T16:40:00.483+00:00"},
         "d7": {"utilization": 0.12, "reset_ts": "2026-10-31T07:00:00.48+00:00"},
         "model_limits": [{"label": "Fable", "utilization": 0.08, "reset_ts": "2026-10-31T07:00:00Z"}]}
probe = {"source": "probe", "tier": 5, "updated_at": RESET - H,
         "h5": {"utilization": 0.25, "reset_ts": str(RESET)},
         "d7": {"utilization": 0.13, "reset_ts": str(WEEK_RESET)}}
assert record(usage, RESET - 2 * H) == 0
assert record(probe, RESET - H) == 0
assert record({"error": "boom"}, RESET) == 1
assert record({"source": "usage"}, RESET) == 1
rows = [json.loads(l) for l in open(path)]
assert len(rows) == 2, rows
assert rows[0] == {"t": RESET - 2 * H, "src": "usage", "tier": 5, "h5": 18.0, "h5_reset": RESET,
                   "d7": 12.0, "d7_reset": WEEK_RESET, "fable": 8.0, "fable_reset": WEEK_RESET}, rows[0]
assert rows[1]["src"] == "probe" and rows[1]["h5_reset"] == RESET

# ISO (with sub-second jitter) and epoch resets land in the same session.
sessions = h.windows(h.read_samples(path), "h5", h.SESSION_SECONDS)
assert len(sessions) == 1 and sessions[0]["peak"] == 25.0, sessions

# Corrupt lines are skipped.
with open(path, "a") as f:
    f.write("not json\n{\"no_t\": 1}\n")
assert len(h.read_samples(path)) == 2

# --- windows, pace --------------------------------------------------------
def sample(t, h5, h5_reset, d7=None, d7_reset=None, tier=5):
    s = {"t": t, "tier": tier, "h5": h5, "h5_reset": h5_reset}
    if d7 is not None:
        s.update(d7=d7, d7_reset=d7_reset)
    return s

old_reset = RESET - 10 * H
reset_history([
    sample(old_reset - 4 * H, 10, old_reset),
    sample(old_reset - 1 * H, 100, old_reset),
    # Outside its own window (stale reset): ignored.
    sample(old_reset + 20 * H, 99, old_reset),
    sample(RESET - 4 * H, 10, RESET),
    sample(RESET - 3 * H, 40, RESET),
    sample(RESET - 2 * H, 70, RESET),
])
now = RESET - 2 * H
r = h.report(now)
assert [s["peak"] for s in r["sessions"]] == [100, 70], r["sessions"]
assert r["session"]["reset"] == RESET
p = r["pace"]["session"]
# 30 %/h over the last hour: 100 % in one more hour, an hour before the reset.
assert p["rate_per_hour"] == 30.0, p
assert p["eta_full"] == RESET - H, p
assert p["projected"] == 130.0 and not p["limited"]
assert p["even"] == 60.0, p

# A finished window is not "current".
assert h.report(RESET + 60)["session"] is None

# --- previous weeks -------------------------------------------------------
W = h.WEEK_SECONDS
reset_history([sample(WEEK_RESET - k * W - W + 3600 * (i + 1), 0, None, d7=10 * (i + 1),
                      d7_reset=WEEK_RESET - k * W) for k in range(4, -1, -1) for i in range(3)])
r = h.report(WEEK_RESET - W + 4 * H)
assert r["week"]["reset"] == WEEK_RESET
assert len(r["prev_weeks"]) == 3
assert r["prev_weeks"][-1]["points"][0] == [3600, 10.0], r["prev_weeks"][-1]
assert r["pace"]["week"]["current"] == 30.0

# --- plan fit -------------------------------------------------------------
reset_history([sample(RESET - k * 6 * H - H, peak, RESET - k * 6 * H, d7=peak / 2,
                      d7_reset=WEEK_RESET)
               for k, peak in enumerate([10, 25, 50, 100])])
fit = h.report(RESET + 60)["plan_fit"]
rows = {row["tier"]: row for row in fit["rows"]}
assert rows[1] == {"tier": 1, "threshold": 20.0, "current": False, "session_hits": 3, "week_hits": 1}, rows[1]
assert rows[5]["current"] and rows[5]["session_hits"] == 1
assert rows[20]["session_hits"] is None and rows[20]["threshold"] == 400.0
assert fit["blocked_sessions"] == 1
assert fit["peak_session"] == 100 and fit["peak_session_pro"] == 5.0
assert fit["peak_week"] == 50

# Unknown tier: nothing to compare against.
reset_history([sample(RESET - H, 50, RESET, tier=None)])
assert h.report(RESET - 60)["plan_fit"] is None

# --- empty history --------------------------------------------------------
os.remove(path)
r = h.report(RESET)
assert r["samples"] == 0 and r["week"] is None and r["session"] is None
assert r["plan_fit"] is None and r["days"] == 0

# --- pruning --------------------------------------------------------------
now = RESET
reset_history([sample(now - 200 * 86400, 1, None), sample(now - 100 * 86400, 2, None)])
assert record(usage, now) == 0
kept = h.read_samples(path)
assert [s["t"] for s in kept] == [now - 100 * 86400, RESET - 2 * H], kept

print("history tests passed")
PY
