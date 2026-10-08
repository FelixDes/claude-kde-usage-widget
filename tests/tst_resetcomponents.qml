import QtQuick
import QtTest

import "../contents/ui" as Widget

TestCase {
    id: testCase
    name: "ResetComponents"

    property double baseMs: 1800000000000
    property double nowMs: baseMs

    Widget.CompactBar {
        id: compactBar
        label: "5h"
        nowMs: testCase.nowMs
    }

    Widget.LimitRow {
        id: limitRow
        label: "5-hour window"
        nowMs: testCase.nowMs
        width: 260
    }

    function init() {
        nowMs = baseMs
        var data = {
            "status": "allowed",
            "utilization": 0.25,
            "reset_ts": String((baseMs + 90 * 60000) / 1000),
            "reset_in": "stale"
        }
        compactBar.windowData = data
        limitRow.windowData = data
    }

    function test_bothRepresentationsReactToClock() {
        compare(compactBar.resetLabel, "1h 30m")
        compare(limitRow.resetLabel, "1 hr 30 min")

        nowMs += 60 * 60000
        compare(compactBar.resetLabel, "30m")
        compare(limitRow.resetLabel, "30 min")

        nowMs += 31 * 60000
        compare(compactBar.resetLabel, "now")
        compare(limitRow.resetLabel, "now")
    }

    function test_compactReportsCountdownWidth() {
        compactBar.windowData = {
            "status": "allowed",
            "utilization": 0.25,
            "reset_ts": String((baseMs + (23 * 60 + 59) * 60000) / 1000),
            "reset_in": "stale"
        }
        compare(compactBar.resetLabel, "23h 59m")
        wait(0)
        var resetGroup = compactBar.children[4]
        var resetText = resetGroup.children[1]
        var textRight = resetText.mapToItem(compactBar, resetText.width, 0).x
        verify(textRight <= compactBar.width + 0.5,
               "reset text ends at " + textRight
               + " but the row reports " + compactBar.width + " px; group x="
               + resetGroup.x + ", width=" + resetGroup.width
               + ", implicitWidth=" + resetGroup.implicitWidth
               + ", text x=" + resetText.x + ", width=" + resetText.width)
    }
}
