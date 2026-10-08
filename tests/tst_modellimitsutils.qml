import QtQuick
import QtTest

import "../contents/code/utils.js" as Utils

TestCase {
    name: "ModelLimitsUtils"

    function test_validResponseIsNormalized() {
        var result = Utils.parseModelLimitsOutput(JSON.stringify({
            "model_limits": [{
                "label": "Fable",
                "status": "allowed",
                "severity": "warning",
                "utilization": 0.11,
                "reset_ts": "2026-10-10T07:00:00Z",
                "reset_in": ""
            }]
        }), "")

        compare(result.error, "")
        compare(result.data.length, 1)
        compare(result.data[0].label, "Fable")
        compare(result.data[0].severity, "warning")
        compare(result.data[0].utilization, 0.11)
        compare(result.data[0].reset_ts, "2026-10-10T07:00:00Z")
    }

    function test_fableLookupIsCaseInsensitiveAndPrefixBased() {
        var limits = [
            { "label": "Opus", "utilization": 0.2 },
            { "label": "FABLE 5.1", "utilization": 0.4 }
        ]
        var fable = Utils.findModelLimit(limits, "fable")
        verify(fable !== null)
        compare(fable.label, "FABLE 5.1")
        compare(fable.utilization, 0.4)
        compare(Utils.findModelLimit(limits, "sonnet"), null)
    }

    function test_emptyListIsAValidPlanWithoutModelLimits() {
        var result = Utils.parseModelLimitsOutput('{"model_limits":[]}', "")
        compare(result.error, "")
        compare(result.data.length, 0)
    }

    function test_errorsFailWithoutInventingData() {
        var apiError = Utils.parseModelLimitsOutput(
            '{"error":"model limits fetch failed"}', "")
        compare(apiError.data, null)
        compare(apiError.error, "model limits fetch failed")

        var malformed = Utils.parseModelLimitsOutput("not json", "")
        compare(malformed.data, null)
        compare(malformed.error, "Model limits parse error")

        var empty = Utils.parseModelLimitsOutput("", "network unavailable")
        compare(empty.data, null)
        compare(empty.error, "network unavailable")
    }

    function test_serverSeverityControlsColorWithoutClaimingLimited() {
        compare(Utils.barColor("allowed", 0.2, "negative", "warning"), Utils.WARN_COLOR)
        compare(Utils.barColor("allowed", 0.2, "negative", "critical"), "negative")
        compare(Utils.barColor("allowed", 0.2, "negative", "normal"), Utils.CLAUDE_COLOR)
    }
}
