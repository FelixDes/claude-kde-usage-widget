import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "StatsWindow"
    when: windowShown

    readonly property double now: 1793112000
    property var win: null

    function makeReport() {
        var start = now - 2 * 86400
        return {
            "now": now, "tier": 5, "samples": 3, "first_sample": start, "days": 2,
            "week": { "start": start, "reset": start + 7 * 86400, "peak": 30,
                      "points": [[start + 3600, 10], [now - 3600, 30]] },
            "session": null,
            "prev_weeks": [{ "start": start - 7 * 86400, "reset": start, "peak": 50,
                             "points": [[3600, 20], [86400, 50]] }],
            "pace": { "week": { "current": 30, "even": 28.6, "rate_per_hour": 0.4,
                                "projected": 80, "eta_full": null, "limited": false },
                      "session": null },
            "sessions": [{ "start": now - 30 * 3600, "reset": now - 25 * 3600, "peak": 45 },
                         { "start": now - 6 * 3600, "reset": now - 3600, "peak": 100 }],
            "weeks": [{ "start": start, "reset": start + 7 * 86400, "peak": 30 }],
            "plan_fit": {
                "rows": [{ "tier": 1, "threshold": 20, "current": false, "session_hits": 2, "week_hits": 1 },
                         { "tier": 5, "threshold": 100, "current": true, "session_hits": 1, "week_hits": 0 },
                         { "tier": 20, "threshold": 400, "current": false, "session_hits": null,
                           "week_hits": null }],
                "sessions": 2, "weeks": 1, "blocked_sessions": 1,
                "peak_session": 100, "peak_session_pro": 5, "peak_week": 30
            }
        }
    }

    function initTestCase() {
        var component = Qt.createComponent("../contents/ui/StatsWindow.qml")
        compare(component.status, Component.Ready, component.errorString())
        // No historyScriptPath: the window must not try to run anything.
        win = component.createObject(null, {
            "report": makeReport(),
            "liveData": { "breakdown": [{ "label": "Claude Code", "percent": 96 }] },
            "prices": { "1": 20, "5": 100, "20": 200, "currency": "$" }
        })
        verify(win !== null)
        win.show()
        tryCompare(win, "visible", true)
    }

    function cleanupTestCase() {
        win.destroy()
    }

    function test_paceAndBreakdown() {
        var week = findChild(win.contentItem, "weekPace")
        verify(week !== null)
        verify(week.text.indexOf("30%") === 0, week.text)
        compare(findChild(win.contentItem, "sessionPace").text, "no active window")
        compare(findChild(win.contentItem, "breakdown").text, "This week by client: Claude Code 96%")
    }

    function test_charts() {
        var week = findChild(win.contentItem, "weekChart")
        // Current week, even pace, projection, one previous week.
        compare(week.series.length, 4)
        compare(week.series[3].points[0][0], makeReport().week.start + 3600)
        compare(week.hLines.length, 3)
        compare(week.hLines[0].label, "≈ Pro")

        var fit = findChild(win.contentItem, "planFitChart")
        compare(fit.bars.length, 2)
        compare(String(fit.bars[1].color), String(win.theme.negativeTextColor))
    }

    function test_planFitRows() {
        var rows = findChild(win.contentItem, "planFitRows")
        compare(rows.count, 3)
    }
}
