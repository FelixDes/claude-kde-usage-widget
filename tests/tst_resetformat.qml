import QtQuick
import QtTest

import "../contents/code/utils.js" as Utils

TestCase {
    name: "ResetFormat"

    property double baseMs: 1800000000000
    property double nowMs: baseMs
    property string resetTs: String((baseMs + 90 * 60000) / 1000)
    readonly property string fullLabel: Utils.formatReset(resetTs, "stale", nowMs, false)
    readonly property string compactLabel: Utils.formatReset(resetTs, "stale", nowMs, true)

    function init() {
        nowMs = baseMs
        resetTs = String((baseMs + 90 * 60000) / 1000)
    }

    function test_reactsToClock() {
        compare(fullLabel, "1 hr 30 min")
        compare(compactLabel, "1h 30m")

        nowMs += 60 * 60000
        compare(fullLabel, "30 min")
        compare(compactLabel, "30m")

        nowMs = baseMs + 91 * 60000
        compare(fullLabel, "now")
        compare(compactLabel, "now")
    }

    function test_boundaries() {
        resetTs = String((baseMs + 60000) / 1000)
        compare(fullLabel, "1 min")
        compare(compactLabel, "1m")

        resetTs = String((baseMs + 59000) / 1000)
        compare(fullLabel, "< 1 min")
        compare(compactLabel, "<1m")

        resetTs = String(baseMs / 1000)
        compare(fullLabel, "now")
        compare(compactLabel, "now")

        resetTs = String((baseMs + (23 * 60 + 31) * 60000) / 1000)
        compare(fullLabel, "23 hr 31 min")
        compare(compactLabel, "23h 31m")

        resetTs = String((baseMs + 24 * 60 * 60000) / 1000)
        compare(fullLabel, "1d")
        compare(compactLabel, "1d")

        resetTs = String((baseMs + (24 * 60 + 1) * 60000) / 1000)
        compare(fullLabel, "1d 1 min")
        compare(compactLabel, "1d 1h")

        resetTs = String((baseMs + (6 * 24 * 60 + 23 * 60 + 59) * 60000) / 1000)
        compare(fullLabel, "6d 23 hr 59 min")
        compare(compactLabel, "7d")
    }

    function test_timestampFormatsAndFallback() {
        resetTs = String(baseMs + 90 * 60000)
        compare(fullLabel, "1 hr 30 min")

        resetTs = new Date(baseMs + 90 * 60000).toISOString()
        compare(fullLabel, "1 hr 30 min")

        resetTs = "invalid"
        compare(fullLabel, "stale")

        resetTs = "0"
        compare(fullLabel, "stale")

        resetTs = "-1"
        compare(fullLabel, "stale")

        resetTs = ""
        compare(fullLabel, "stale")
        compare(Utils.formatReset(resetTs, "", baseMs, false), "")

        resetTs = String((baseMs + 60000) / 1000)
        compare(Utils.formatReset(resetTs, "stale", 0, false), "stale")
    }
}
