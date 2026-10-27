import QtQuick
import QtTest

import "../contents/code/stats.js" as Stats
import "../contents/code/utils.js" as Utils

TestCase {
    name: "Stats"

    // Wed 2026-10-28 12:00 local time
    readonly property double now: new Date(2026, 9, 28, 12, 0, 0).getTime() / 1000

    function test_tierLines() {
        var lines = Stats.tierLines(5)
        compare(lines.length, 3)
        compare(lines[0].y, 20)
        compare(lines[0].label, "Pro")
        compare(lines[1].y, 100)
        compare(lines[1].label, "Max 5x (you)")
        verify(lines[1].current)
        compare(lines[2].y, 400)
        compare(Stats.tierLines(0).length, 0)
    }

    function test_chartYMaxKeepsFarLinesOffScale() {
        var lines = Stats.tierLines(5)
        compare(Stats.chartYMax([40], lines), 110)
        // From Pro, Max 5x (500%) and Max 20x (2000%) stay off-scale.
        compare(Stats.chartYMax([60], Stats.tierLines(1)), 110)
        // From Max 20x, Max 5x at 25% and Pro at 5% are below 100.
        compare(Stats.chartYMax([130], Stats.tierLines(20)), 150)
    }

    function test_paceSummary() {
        var reset = now + 3 * 3600
        var ok = Stats.paceSummary({ "current": 30, "even": 50, "projected": 45, "eta_full": null,
                                     "limited": false }, reset, now)
        compare(ok.level, "ok")
        compare(ok.text, "30% · ~45% by reset 15:00 · below even pace (50%)")

        var ahead = Stats.paceSummary({ "current": 60, "even": 50, "projected": 90, "eta_full": null,
                                        "limited": false }, reset, now)
        compare(ahead.level, "notice")
        verify(ahead.text.indexOf("ahead of even pace") > 0)

        var warn = Stats.paceSummary({ "current": 80, "even": 50, "projected": 140,
                                       "eta_full": now + 3600, "limited": false }, reset, now)
        compare(warn.level, "warn")
        compare(warn.text, "80% · at this pace 100% by 13:00, 2 h before the reset")

        var limited = Stats.paceSummary({ "current": 100, "limited": true }, reset, now)
        compare(limited.level, "critical")
        compare(Stats.paceSummary(null, 0, now).level, "none")
    }

    function test_formatTimeShowsDayForOtherDays() {
        compare(Stats.formatTime(now + 3600, now), "13:00")
        verify(Stats.formatTime(now + 2 * 86400, now).indexOf("13:00") < 0)
        verify(Stats.formatTime(now + 2 * 86400, now).indexOf("12:00") > 0)
    }

    function test_planFitRowsForMax5() {
        var fit = {
            "rows": [
                { "tier": 1, "threshold": 20, "session_hits": 3, "week_hits": 1 },
                { "tier": 5, "threshold": 100, "session_hits": 0, "week_hits": 0 },
                { "tier": 20, "threshold": 400, "session_hits": null, "week_hits": null }
            ],
            "blocked_sessions": 0
        }
        var prices = { "1": 20, "5": 100, "20": 200, "currency": "€" }
        var rows = Stats.planFitRows(fit, 5, prices)
        compare(rows.length, 3)
        compare(rows[0].verdict, "would run out in 3 sessions, 1 week (≈)")
        compare(rows[0].level, "bad")
        compare(rows[0].price, "€20/mo")
        compare(rows[1].name, "Max 5x · you")
        compare(rows[1].verdict, "you never hit the limit")
        compare(rows[2].verdict, "no benefit seen (+€100/mo)")

        fit.rows[0].session_hits = 0
        fit.rows[0].week_hits = 0
        compare(Stats.planFitRows(fit, 5, prices)[0].verdict, "would have been enough, saves €80/mo")

        fit.blocked_sessions = 2
        compare(Stats.planFitRows(fit, 5, prices)[2].verdict, "would have avoided 2 blocks, +€100/mo")
        // A zero price is treated as unknown.
        prices["20"] = 0
        compare(Stats.planFitRows(fit, 5, prices)[2].verdict, "would have avoided 2 blocks")
    }

    function test_breakdownText() {
        compare(Stats.breakdownText([{ "label": "Claude Code", "percent": 96 },
                                     { "label": "Chats", "percent": 4 },
                                     { "label": "Cowork", "percent": 0 }]),
                "Claude Code 96% · Chats 4%")
        compare(Stats.breakdownText(null), "")
    }

    function test_planLabel() {
        compare(Utils.planLabel("max", 5), "Max 5x")
        compare(Utils.planLabel("pro", 1), "Pro")
        compare(Utils.planLabel("", 5), "")
    }
}
