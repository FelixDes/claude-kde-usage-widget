#!/usr/bin/env python3
"""Usage history for the Claude Limits widget.

    history.py record          read one fetch result (JSON) on stdin, append a sample
    history.py report [--now]  print what the statistics window needs, as JSON

Samples live in $CLAUDE_WIDGET_HISTORY or
${XDG_DATA_HOME:-~/.local/share}/claude-limits-widget/history.jsonl, one JSON
object per line:

    {"t": 1793120000, "src": "usage", "tier": 5,
     "h5": 18.0, "h5_reset": 1793119200, "d7": 12.0, "d7_reset": 1793430000,
     "fable": 8.0, "fable_reset": 1793430000}

Percentages are of the user's own plan. Usage only grows inside a window until
it resets, so the highest sample of a window is (close to) its final usage even
with sparse sampling.
"""

import argparse
import fcntl
import json
import math
import os
import sys
import time
from datetime import datetime

SESSION_SECONDS = 5 * 3600
WEEK_SECONDS = 7 * 86400
KEEP_SECONDS = 180 * 86400
PLAN_FIT_SECONDS = 30 * 86400
TIERS = (1, 5, 20)


def history_path():
    override = os.environ.get("CLAUDE_WIDGET_HISTORY")
    if override:
        return override
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "claude-limits-widget", "history.jsonl")


def finite(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def epoch(value):
    """Reset timestamps arrive as epoch seconds/ms (number or string) or ISO 8601."""
    if value is None or isinstance(value, bool):
        return None
    number = finite(value)
    if number is None and isinstance(value, str):
        try:
            number = float(value.strip())
        except ValueError:
            try:
                return datetime.fromisoformat(value.strip().replace("Z", "+00:00")).timestamp()
            except ValueError:
                return None
    if number is None or not math.isfinite(number) or number <= 0:
        return None
    return number / 1000 if number >= 1e11 else number


def window_values(window):
    if not isinstance(window, dict):
        return None, None
    utilization = finite(window.get("utilization"))
    if utilization is None:
        return None, None
    return round(utilization * 100, 2), epoch(window.get("reset_ts"))


def sample_from_result(result, now):
    if not isinstance(result, dict) or result.get("error"):
        return None
    h5, h5_reset = window_values(result.get("h5"))
    d7, d7_reset = window_values(result.get("d7"))
    if h5 is None and d7 is None:
        return None

    sample = {"t": int(finite(result.get("updated_at")) or now),
              "src": result.get("source") if isinstance(result.get("source"), str) else ""}
    tier = result.get("tier")
    if isinstance(tier, int) and not isinstance(tier, bool) and tier > 0:
        sample["tier"] = tier
    for key, value, reset in (("h5", h5, h5_reset), ("d7", d7, d7_reset)):
        if value is not None:
            sample[key] = value
            sample[key + "_reset"] = int(round(reset)) if reset else None

    limits = result.get("model_limits")
    for limit in limits if isinstance(limits, list) else []:
        label = limit.get("label") if isinstance(limit, dict) else None
        if isinstance(label, str) and label.lower().startswith("fable"):
            fable, fable_reset = window_values(limit)
            if fable is not None:
                sample["fable"] = fable
                sample["fable_reset"] = int(round(fable_reset)) if fable_reset else None
            break
    return sample


def read_samples(path):
    samples = []
    try:
        with open(path, encoding="utf-8") as history:
            for line in history:
                try:
                    sample = json.loads(line)
                except ValueError:
                    continue
                if isinstance(sample, dict) and finite(sample.get("t")) is not None:
                    samples.append(sample)
    except FileNotFoundError:
        pass
    samples.sort(key=lambda s: s["t"])
    return samples


def record(stdin, now):
    try:
        result = json.load(stdin)
    except ValueError:
        return 1
    sample = sample_from_result(result, now)
    if sample is None:
        return 1

    path = history_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path, "a+", encoding="utf-8") as history:
        fcntl.flock(history, fcntl.LOCK_EX)
        history.write(json.dumps(sample, separators=(",", ":")) + "\n")
        history.flush()
        history.seek(0)
        first = history.readline()
        try:
            oldest = json.loads(first).get("t", now)
        except (ValueError, AttributeError):
            oldest = 0
        # Rewrite rarely: only once the oldest sample is ten days past retention.
        if oldest < now - KEEP_SECONDS - 10 * 86400:
            keep = [s for s in read_samples(path) if s["t"] >= now - KEEP_SECONDS]
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as out:
                for s in keep:
                    out.write(json.dumps(s, separators=(",", ":")) + "\n")
            os.replace(tmp, path)
    return 0


def windows(samples, key, duration):
    """Groups samples by window (same reset, to the minute; resets jitter by
    under a second between responses)."""
    groups = {}
    for s in samples:
        value, reset = finite(s.get(key)), finite(s.get(key + "_reset"))
        if value is None or reset is None:
            continue
        groups.setdefault(round(reset / 60), []).append((s["t"], value, reset))
    result = []
    for points in groups.values():
        reset = max(p[2] for p in points)
        start = reset - duration
        points = [(t, v) for t, v, _ in points if start - 60 <= t <= reset + 60]
        if points:
            result.append({"start": int(start), "reset": int(reset),
                           "peak": max(v for _, v in points),
                           "points": [[int(t), v] for t, v in points]})
    result.sort(key=lambda w: w["reset"])
    return result


def pace(window, now, duration, lookback, min_span):
    """Even-pace target, recent burn rate and where it leads by the reset."""
    points = window["points"]
    t_last, current = points[-1]
    elapsed = max(1.0, min(now, window["reset"]) - window["start"])
    recent = [p for p in points if p[0] >= t_last - lookback]
    t0, v0 = recent[0]
    if t_last - t0 >= min_span:
        rate = (current - v0) / (t_last - t0)
    else:
        rate = current / max(1.0, t_last - window["start"])
    rate = max(0.0, rate)
    remaining = max(0.0, window["reset"] - t_last)
    projected = current + rate * remaining
    eta = None
    if current < 100 and rate > 0 and projected >= 100:
        eta = int(t_last + (100 - current) / rate)
    return {
        "current": current,
        "even": round(min(100.0, elapsed / duration * 100), 1),
        "rate_per_hour": round(rate * 3600, 2),
        "projected": round(projected, 1),
        "eta_full": eta,
        "limited": current >= 100,
    }


def current_window(all_windows, now):
    if all_windows and all_windows[-1]["reset"] > now:
        return all_windows[-1]
    return None


def plan_fit(sessions, weeks, tier):
    """How often each plan would have run out, given usage on the user's plan.

    Usage on plan m is usage on the user's plan scaled by tier/m, so plan m runs
    out once the user's own usage passes 100 * m / tier percent. Above the
    user's plan the data stops at 100% (the user was blocked there), so larger
    plans can only report how often the user hit the own limit.
    """
    if not tier:
        return None
    rows = []
    for m in TIERS:
        threshold = 100.0 * m / tier
        row = {"tier": m, "threshold": round(threshold, 1), "current": m == tier}
        if m > tier:
            row["session_hits"] = None
            row["week_hits"] = None
        else:
            row["session_hits"] = sum(1 for s in sessions if s["peak"] >= threshold - 0.5)
            row["week_hits"] = sum(1 for w in weeks if w["peak"] >= threshold - 0.5)
        rows.append(row)
    return {
        "rows": rows,
        "sessions": len(sessions),
        "weeks": len(weeks),
        "blocked_sessions": sum(1 for s in sessions if s["peak"] >= 99.5),
        "peak_session": max((s["peak"] for s in sessions), default=None),
        "peak_session_pro": round(max((s["peak"] for s in sessions), default=0) * tier / 100, 2)
        if sessions else None,
        "peak_week": max((w["peak"] for w in weeks), default=None),
    }


def report(now):
    samples = read_samples(history_path())
    tier = next((s["tier"] for s in reversed(samples) if isinstance(s.get("tier"), int)), None)
    sessions = windows(samples, "h5", SESSION_SECONDS)
    weeks = windows(samples, "d7", WEEK_SECONDS)

    week = current_window(weeks, now)
    session = current_window(sessions, now)
    done_weeks = [w for w in weeks if w is not week]
    recent_sessions = [s for s in sessions if s["reset"] >= now - PLAN_FIT_SECONDS]
    fit_weeks = [w for w in weeks if w["reset"] >= now - PLAN_FIT_SECONDS]

    prev_weeks = []
    for w in done_weeks[-3:]:
        prev_weeks.append({"start": w["start"], "reset": w["reset"], "peak": w["peak"],
                           "points": [[t - w["start"], v] for t, v in w["points"]]})

    return {
        "now": int(now),
        "tier": tier,
        "samples": len(samples),
        "first_sample": samples[0]["t"] if samples else None,
        "days": round((now - samples[0]["t"]) / 86400, 1) if samples else 0,
        "week": week,
        "session": session,
        "prev_weeks": prev_weeks,
        "pace": {
            "week": pace(week, now, WEEK_SECONDS, 24 * 3600, 2 * 3600) if week else None,
            "session": pace(session, now, SESSION_SECONDS, 3600, 15 * 60) if session else None,
        },
        "sessions": [{k: s[k] for k in ("start", "reset", "peak")} for s in recent_sessions],
        "weeks": [{k: w[k] for k in ("start", "reset", "peak")} for w in fit_weeks],
        "plan_fit": plan_fit(recent_sessions, fit_weeks, tier),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("record", "report"))
    parser.add_argument("--now", type=float, default=None)
    args = parser.parse_args()
    now = args.now if args.now is not None else time.time()
    if args.command == "record":
        return record(sys.stdin, now)
    print(json.dumps(report(now)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
