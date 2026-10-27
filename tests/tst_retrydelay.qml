import QtQuick
import QtTest

import "../contents/code/utils.js" as Utils

TestCase {
    name: "RetryDelay"

    function test_doublesFromBase() {
        compare(Utils.retryDelayMs(0, 15000, 900000), 15000)
        compare(Utils.retryDelayMs(1, 15000, 900000), 30000)
        compare(Utils.retryDelayMs(3, 15000, 900000), 120000)
    }

    function test_cappedAtMax() {
        compare(Utils.retryDelayMs(6, 15000, 900000), 900000)
        compare(Utils.retryDelayMs(1000, 15000, 900000), 900000)
    }

    function test_badAttemptStartsAtBase() {
        compare(Utils.retryDelayMs(-1, 15000, 900000), 15000)
        compare(Utils.retryDelayMs(undefined, 15000, 900000), 15000)
    }
}
