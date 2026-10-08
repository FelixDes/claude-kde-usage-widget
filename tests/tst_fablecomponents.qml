import QtQuick
import QtTest

import "../contents/ui" as Widget

TestCase {
    id: testCase
    name: "FableComponents"

    property double baseMs: 1800000000000
    property var fableData: ({
        "label": "Fable",
        "status": "allowed",
        "utilization": 0.42,
        "reset_ts": new Date(baseMs + 2 * 24 * 60 * 60000).toISOString(),
        "reset_in": ""
    })

    Widget.CompactBar {
        id: compactBar
        label: "F"
        windowData: testCase.fableData
        nowMs: testCase.baseMs
    }

    Widget.LimitRow {
        id: limitRow
        label: "Fable weekly"
        windowData: testCase.fableData
        nowMs: testCase.baseMs
        width: 260
    }

    function init() {
        compactBar.nowMs = baseMs
        limitRow.nowMs = baseMs
    }

    function test_percentageAndIsoReset() {
        compare(compactBar.utilization, 0.42)
        compare(limitRow.utilization, 0.42)
        compare(compactBar.resetLabel, "2d")
        compare(limitRow.resetLabel, "2d")
    }

    function test_countdownKeepsMoving() {
        compactBar.nowMs = baseMs + 24 * 60 * 60000
        limitRow.nowMs = baseMs + 24 * 60 * 60000
        compare(compactBar.resetLabel, "1d")
        compare(limitRow.resetLabel, "1d")
    }
}
