import QtQuick
import QtTest

import "../contents/ui" as Widget

TestCase {
    id: testCase
    name: "StatusRow"
    when: windowShown
    width: 300
    height: 300
    visible: true

    Widget.StatusRow {
        id: statusRow
        width: 240
        maximumIncidentHeight: 48
    }

    function init() {
        statusRow.indicator = "none"
        statusRow.description = "All systems operational"
        statusRow.incidents = []
        statusRow.errorText = ""
        wait(20)
    }

    function test_remoteSummaryIsPlainText() {
        statusRow.description = "<b>Not markup</b>"
        wait(0)

        var summary = findChild(statusRow, "statusSummary")
        verify(summary !== null)
        compare(summary.text, "<b>Not markup</b>")
        compare(summary.textFormat, Text.PlainText)
    }

    function test_incidentListHeightIsCapped() {
        var incidents = []
        for (var i = 0; i < 12; ++i) {
            incidents.push({
                "name": "Incident " + i,
                "impact": "minor",
                "status": "monitoring"
            })
        }
        statusRow.incidents = incidents
        wait(20)

        var scroll = findChild(statusRow, "statusIncidentScroll")
        verify(scroll !== null)
        verify(scroll.visible,
               "row visible=" + statusRow.visible
               + ", incidents=" + statusRow.incidents.length
               + ", indicator=" + statusRow.indicator
               + ", error=" + statusRow.errorText)
        verify(statusRow.incidentContentHeight > statusRow.maximumIncidentHeight,
               "content=" + statusRow.incidentContentHeight
               + ", maximum=" + statusRow.maximumIncidentHeight
               + ", scroll height=" + scroll.height)
        verify(scroll.height <= statusRow.maximumIncidentHeight + 0.5)
    }

    function test_errorHidesIncidents() {
        statusRow.incidents = [{
            "name": "Old incident",
            "impact": "major",
            "status": "investigating"
        }]
        statusRow.errorText = "status fetch failed"
        wait(0)

        var scroll = findChild(statusRow, "statusIncidentScroll")
        verify(statusRow.hasStatus)
        verify(!scroll.visible)
    }
}
