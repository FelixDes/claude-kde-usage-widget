import QtQuick
import QtTest

import "../contents/code/utils.js" as Utils

TestCase {
    name: "StatusUtils"

    function test_validResponseIsNormalized() {
        var result = Utils.parseStatusOutput(JSON.stringify({
            "indicator": "minor",
            "description": "Degraded performance",
            "incidents": [{
                "name": "API latency",
                "impact": "minor",
                "status": "monitoring",
                "shortlink": "https://stspg.io/example"
            }]
        }), "ignored stderr")

        compare(result.error, "")
        verify(result.data !== null)
        compare(result.data.indicator, "minor")
        compare(result.data.description, "Degraded performance")
        compare(result.data.incidents.length, 1)
        compare(result.data.incidents[0].name, "API latency")
    }

    function test_errorPayloadDoesNotExposeOldData() {
        var result = Utils.parseStatusOutput('{"error":"status fetch failed"}', "")
        compare(result.data, null)
        compare(result.error, "status fetch failed")
    }

    function test_invalidAndEmptyOutputFailClosed() {
        var invalid = Utils.parseStatusOutput("not json", "")
        compare(invalid.data, null)
        compare(invalid.error, "Status parse error")

        var empty = Utils.parseStatusOutput("", "network unavailable")
        compare(empty.data, null)
        compare(empty.error, "network unavailable")

        var whitespace = Utils.parseStatusOutput("", "   ")
        compare(whitespace.data, null)
        compare(whitespace.error, "No status output")
    }

    function test_invalidSchemaFailsClosed() {
        var missingIndicator = Utils.parseStatusOutput('{"incidents":[]}', "")
        compare(missingIndicator.data, null)
        compare(missingIndicator.error, "Invalid status response")

        var wrongRoot = Utils.parseStatusOutput('[]', "")
        compare(wrongRoot.data, null)
        compare(wrongRoot.error, "Invalid status response")
    }

    function test_severityColors() {
        compare(Utils.severityColor("none", "good", "neutral", "bad", "off"), "good")
        compare(Utils.severityColor("minor", "good", "neutral", "bad", "off"), "neutral")
        compare(Utils.severityColor("critical", "good", "neutral", "bad", "off"), "bad")
        compare(Utils.severityColor("unknown", "good", "neutral", "bad", "off"), "off")
    }

    function test_incidentImpactRaisesAggregateSeverity() {
        compare(Utils.aggregateStatusSeverity("none", []), "none")
        compare(Utils.aggregateStatusSeverity("none", [{ "impact": "major" }]), "major")
        compare(Utils.aggregateStatusSeverity("minor", [
            { "impact": "critical" },
            { "impact": "major" }
        ]), "critical")
        compare(Utils.aggregateStatusSeverity("major", [{ "impact": "minor" }]), "major")
    }
}
