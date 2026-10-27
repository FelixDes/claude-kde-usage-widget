.pragma library

// Text and geometry helpers for the statistics window. Inputs are the JSON
// produced by history.py report (times in epoch seconds, usage in percent of
// the user's own plan).

var TIERS = [1, 5, 20]

function tierName(tier) {
    return tier === 1 ? "Pro" : "Max " + tier + "x"
}

function formatDuration(seconds) {
    var mins = Math.max(0, Math.round(seconds / 60))
    if (mins < 60)
        return mins + " min"
    var hours = Math.round(mins / 60)
    if (hours < 48)
        return hours + " h"
    var days = Math.floor(hours / 24)
    var rest = hours % 24
    return days + " d" + (rest > 0 ? " " + rest + " h" : "")
}

// "14:05" today, "Thu 14:05" on other days.
function formatTime(seconds, nowSeconds) {
    var date = new Date(seconds * 1000)
    var now = new Date(nowSeconds * 1000)
    var sameDay = date.getFullYear() === now.getFullYear()
        && date.getMonth() === now.getMonth()
        && date.getDate() === now.getDate()
    return Qt.formatDateTime(date, sameDay ? "HH:mm" : "ddd HH:mm")
}

// One line on where the current window is heading. level: ok | warn | critical.
function paceSummary(pace, reset, nowSeconds) {
    if (!pace)
        return { "text": "no active window", "level": "none" }
    var current = Math.round(pace.current) + "%"
    if (pace.limited)
        return {
            "text": current + " · limit reached, resets " + formatTime(reset, nowSeconds),
            "level": "critical"
        }
    if (pace.eta_full) {
        return {
            "text": current + " · at this pace 100% by " + formatTime(pace.eta_full, nowSeconds)
                + ", " + formatDuration(reset - pace.eta_full) + " before the reset",
            "level": "warn"
        }
    }
    var relation = pace.current > pace.even + 1 ? "ahead of"
        : (pace.current < pace.even - 1 ? "below" : "on")
    return {
        "text": current + " · ~" + Math.round(Math.min(pace.projected, 100)) + "% by reset "
            + formatTime(reset, nowSeconds) + " · " + relation + " even pace ("
            + Math.round(pace.even) + "%)",
        "level": pace.current > pace.even + 1 ? "notice" : "ok"
    }
}

// Where each plan would run out, in percent of the user's plan.
function tierLines(tier) {
    if (!tier)
        return []
    var lines = []
    for (var i = 0; i < TIERS.length; ++i) {
        var m = TIERS[i]
        lines.push({
            "tier": m,
            "y": 100 * m / tier,
            "label": tierName(m) + (m === tier ? " (you)" : ""),
            "current": m === tier
        })
    }
    return lines
}

// Y axis top: room for the data and the nearest plan line above it, but a far
// away plan (Max 20x seen from Pro is at 2000%) stays off-scale.
function chartYMax(values, lines) {
    var top = 100
    for (var i = 0; i < values.length; ++i)
        top = Math.max(top, Number(values[i]) || 0)
    var withLines = top
    for (var j = 0; j < lines.length; ++j) {
        if (lines[j].y > top && lines[j].y <= top * 2.5) {
            withLines = Math.max(withLines, lines[j].y)
            break
        }
    }
    // The epsilon keeps 100 * 1.1 (= 110.00000000000001) from rounding up to 120.
    return Math.ceil(withLines * 1.1 / 10 - 1e-9) * 10
}

function priceText(prices, tier) {
    if (!prices)
        return ""
    var price = Number(prices[String(tier)])
    if (!isFinite(price) || price <= 0)
        return ""
    return (prices.currency || "$") + price + "/mo"
}

function priceDelta(prices, from, to) {
    if (!prices)
        return null
    var a = Number(prices[String(from)])
    var b = Number(prices[String(to)])
    return isFinite(a) && isFinite(b) && a > 0 && b > 0 ? b - a : null
}

function plural(n, word) {
    return n + " " + word + (n === 1 ? "" : "s")
}

// Rows for the plan fit table: what each plan would have meant over the
// recorded sessions/weeks. level: good | bad | neutral.
function planFitRows(fit, tier, prices) {
    if (!fit || !tier)
        return []
    var rows = []
    var currency = prices && prices.currency ? prices.currency : "$"
    for (var i = 0; i < fit.rows.length; ++i) {
        var row = fit.rows[i]
        var delta = priceDelta(prices, tier, row.tier)
        var verdict, level
        if (row.tier < tier) {
            if (row.session_hits === 0 && row.week_hits === 0) {
                verdict = "would have been enough"
                    + (delta !== null ? ", saves " + currency + (-delta) + "/mo" : "")
                level = "good"
            } else {
                var parts = []
                if (row.session_hits > 0)
                    parts.push(plural(row.session_hits, "session"))
                if (row.week_hits > 0)
                    parts.push(plural(row.week_hits, "week") + " (≈)")
                verdict = "would run out in " + parts.join(", ")
                level = "bad"
            }
        } else if (row.tier === tier) {
            verdict = fit.blocked_sessions > 0
                ? "you hit the limit in " + plural(fit.blocked_sessions, "session")
                : "you never hit the limit"
            level = fit.blocked_sessions > 0 ? "bad" : "good"
        } else {
            if (fit.blocked_sessions > 0) {
                verdict = "would have avoided " + plural(fit.blocked_sessions, "block")
                    + (delta !== null ? ", +" + currency + delta + "/mo" : "")
                level = "neutral"
            } else {
                verdict = "no benefit seen" + (delta !== null ? " (+" + currency + delta + "/mo)" : "")
                level = "neutral"
            }
        }
        rows.push({
            "tier": row.tier,
            "name": tierName(row.tier) + (row.tier === tier ? " · you" : ""),
            "price": priceText(prices, row.tier),
            "threshold": row.threshold,
            "verdict": verdict,
            "level": level
        })
    }
    return rows
}

function breakdownText(breakdown) {
    // Lists handed over through QML properties are array-like, not Arrays.
    if (!breakdown || typeof breakdown.length !== "number")
        return ""
    var parts = []
    for (var i = 0; i < breakdown.length; ++i) {
        var row = breakdown[i]
        if (row && row.percent > 0)
            parts.push(row.label + " " + Math.round(row.percent) + "%")
    }
    return parts.join(" · ")
}

// Daily ticks for a week chart, every 30/60 min for a session chart.
function timeTicks(start, end, nowSeconds) {
    var span = end - start
    var ticks = []
    var step, format
    if (span > 2 * 86400) {
        step = 86400
        format = "ddd"
    } else {
        step = span > 6 * 3600 ? 3 * 3600 : 3600
        format = "HH:mm"
    }
    var first = Math.ceil(start / step) * step
    if (step === 86400) {
        // Local midnights rather than UTC ones.
        var d = new Date(start * 1000)
        d.setHours(24, 0, 0, 0)
        first = d.getTime() / 1000
    }
    for (var t = first; t < end; t += step)
        ticks.push({ "x": t, "label": Qt.formatDateTime(new Date(t * 1000), format) })
    return ticks
}
