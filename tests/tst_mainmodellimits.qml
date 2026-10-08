import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "MainModelLimits"
    when: windowShown
    width: 600
    height: 500

    property double baseMs: 1800000000000

    Loader {
        id: widgetLoader
        source: "../contents/ui/main.qml"
    }

    function initTestCase() {
        tryCompare(widgetLoader, "status", Loader.Ready)
        verify(widgetLoader.item !== null)
    }

    function init() {
        widgetLoader.item.nowMs = baseMs
        widgetLoader.item.modelLimitData = []
        widgetLoader.item.modelLimitsUpdatedMs = 0
        wait(0)
    }

    function fableWindow() {
        return {
            "label": "Fable",
            "status": "allowed",
            "utilization": 0.11,
            "reset_ts": new Date(baseMs + 2 * 24 * 60 * 60000).toISOString(),
            "reset_in": ""
        }
    }

    function test_optionalWindowChangesBothRepresentations() {
        var widget = widgetLoader.item
        var compact = widget.compactRepresentation.createObject(testCase, {
            "width": 320,
            "height": 80
        })
        var full = widget.fullRepresentation.createObject(testCase)
        verify(compact !== null)
        verify(full !== null)
        wait(0)

        compare(full.popupHeight, 190)
        compare(widget.fable, null)

        widget.modelLimitData = [fableWindow()]
        widget.modelLimitsUpdatedMs = baseMs
        wait(0)

        verify(widget.fable !== null)
        compare(widget.fable.label, "Fable")
        compare(full.popupHeight, 238)
        var compactFable = findChild(compact, "compactFable")
        var fullFable = findChild(full, "fullFable")
        verify(compactFable !== null)
        verify(fullFable !== null)
        verify(compactFable.windowData !== null)
        verify(fullFable.windowData !== null)
        compare(compactFable.windowData.label, "Fable")
        compare(fullFable.windowData.label, "Fable")

        compact.destroy()
        full.destroy()
    }

    function test_staleWindowIsHidden() {
        var widget = widgetLoader.item
        widget.modelLimitData = [fableWindow()]
        widget.modelLimitsUpdatedMs = baseMs
        verify(widget.fable !== null)

        widget.nowMs = baseMs + 47 * 60 * 1000
        compare(widget.fable, null)
    }
}
