import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

import "../code/utils.js" as Utils

PlasmoidItem {
    id: root

    // Let Plasma pick automatically:
    //   - compact on a panel
    //   - full on the desktop
    // Setting preferredRepresentation: fullRepresentation here forces the
    // popup to render inline in the panel — don't do it.

    property var limitData: null
    property string errorMsg: ""
    property bool loading: false
    property string lastUpdated: ""
    property double nowMs: Date.now()

    // Service status from status.claude.com (free, no token cost).
    property var statusData: null
    property string statusError: ""

    readonly property var incidents: statusData && statusData.incidents ? statusData.incidents : []
    readonly property string statusIndicator: statusData ? (statusData.indicator || "") : ""
    // Anything other than "none" (or a missing/unknown status) is degraded.
    readonly property bool statusDegraded: statusData !== null
        && statusIndicator !== "" && statusIndicator !== "none"

    readonly property var h5: limitData ? limitData.h5 : null
    readonly property var d7: limitData ? limitData.d7 : null
    readonly property bool hasData: limitData !== null
    readonly property bool firstLoad: loading && !hasData

    readonly property int effectiveInterval: Math.max(1, Plasmoid.configuration.refreshInterval || 15)
    readonly property bool showTitle: Plasmoid.configuration.showTitle !== false

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch_limits.sh").toString().replace("file://", "")
    readonly property string statusScriptPath: Qt.resolvedUrl("../code/fetch_status.sh").toString().replace("file://", "")

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.loading = false
            disconnectSource(source)

            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""

            if (!stdout.trim()) {
                root.errorMsg = stderr || "No output from script"
                return
            }
            try {
                var parsed = JSON.parse(stdout.trim())
                if (parsed.error) {
                    root.errorMsg = parsed.error
                    root.limitData = null
                } else {
                    root.limitData = parsed
                    root.errorMsg = ""
                    root.nowMs = Date.now()
                    var now = new Date(root.nowMs)
                    root.lastUpdated = now.getHours() + ":" + String(now.getMinutes()).padStart(2, "0")
                }
            } catch(e) {
                root.errorMsg = "Parse error: " + stdout.substring(0, 80)
            }
        }
    }

    function fetchLimits() {
        if (root.loading) return
        root.loading = true
        var safePath  = root.scriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        var proxyMode = Plasmoid.configuration.proxyMode || "env"
        executable.connectSource("bash '" + safePath + "' '" + proxyMode + "' '" + safeProxy + "'")
    }

    P5Support.DataSource {
        id: statusExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)

            var stdout = (data["stdout"] || "").trim()
            var stderr = data["stderr"] || ""

            if (!stdout) {
                root.statusError = stderr || "No status output"
                return
            }
            try {
                var parsed = JSON.parse(stdout)
                if (parsed.error) {
                    root.statusError = parsed.error
                } else {
                    root.statusData = parsed
                    root.statusError = ""
                }
            } catch(e) {
                root.statusError = "Status parse error"
            }
        }
    }

    function fetchStatus() {
        var safePath  = root.statusScriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        var proxyMode = Plasmoid.configuration.proxyMode || "env"
        statusExecutable.connectSource("bash '" + safePath + "' '" + proxyMode + "' '" + safeProxy + "'")
    }

    Timer {
        interval: root.effectiveInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchLimits()
    }

    // Keep reset countdowns moving without making extra API requests.
    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Delayed first fetch: give the network / session a moment after login
    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.fetchLimits()
    }

    // Service status is free to poll, so refresh it on a fixed short cadence
    // regardless of the (token-burning) limits refresh interval.
    Timer {
        interval: 2 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchStatus()
    }

    // ── Compact (panel bar) ──────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: compactRoot

        // Tell the panel how wide/tall we want to be. Plasma's panel layout
        // reads the Layout.* attached properties; implicitWidth alone is
        // ignored, which is why the applet gets squeezed to icon width.
        readonly property int minimumDesiredWidth: 150
        readonly property int desiredWidth: Math.max(
            minimumDesiredWidth, Math.ceil(compactCol.width + 8))

        implicitWidth: desiredWidth
        implicitHeight: compactCol.implicitHeight + 4

        Layout.minimumWidth: desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth: desiredWidth * 2

        onClicked: root.expanded = !root.expanded

        Column {
            id: compactCol
            anchors.centerIn: parent
            width: Math.max(compactH5.width, compactD7.width)
            spacing: 2

            CompactBar {
                id: compactH5
                label: "5h"
                windowData: root.h5
                nowMs: root.nowMs
                visible: root.hasData
            }
            CompactBar {
                id: compactD7
                label: "7d"
                windowData: root.d7
                nowMs: root.nowMs
                visible: root.hasData
            }

            // Service-status warning: only shown when Claude is degraded.
            Row {
                spacing: 3
                visible: root.statusDegraded

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Utils.severityColor(
                        root.statusIndicator,
                        Kirigami.Theme.positiveTextColor,
                        Kirigami.Theme.neutralTextColor,
                        Kirigami.Theme.negativeTextColor,
                        Kirigami.Theme.disabledTextColor)
                }

                PlasmaComponents.Label {
                    text: root.incidents.length > 0 ? "issue" : "degraded"
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            PlasmaComponents.Label {
                text: root.firstLoad ? "…" : (root.errorMsg ? "!" : "")
                font.pixelSize: 9
                visible: root.firstLoad || root.errorMsg !== ""
            }
        }
    }

    // ── Full popup ───────────────────────────────────────────────────────────
    fullRepresentation: Item {
        readonly property int popupWidth: 260
        // Grow to fit the status line plus one row per active incident.
        readonly property int popupHeight: 215 + root.incidents.length * 16

        implicitWidth: popupWidth
        implicitHeight: popupHeight

        Layout.minimumWidth: popupWidth
        Layout.preferredWidth: popupWidth
        Layout.minimumHeight: popupHeight
        Layout.preferredHeight: popupHeight
        Layout.maximumHeight: popupHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // Title — first item in layout, always at top
            RowLayout {
                Layout.fillWidth: true
                visible: root.showTitle

                PlasmaComponents.Label {
                    text: "Claude Limits"
                    font.bold: true
                    font.pixelSize: 14
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    QQC2.ToolTip.text: "Refresh now"
                    QQC2.ToolTip.visible: hovered
                    enabled: !root.loading
                    onClicked: root.fetchLimits()
                }
            }

            // Service status (status.claude.com)
            StatusRow {
                Layout.fillWidth: true
                indicator: root.statusIndicator
                description: root.statusData ? (root.statusData.description || "") : ""
                incidents: root.incidents
                errorText: root.statusError
                visible: hasStatus
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.errorMsg
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                visible: root.errorMsg !== "" && !root.loading
            }

            // Placeholder fills the bars' space before first data arrives,
            // keeping title at top and footer at bottom
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.hasData

                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    visible: root.firstLoad
                    running: visible
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: "Waiting for first update…"
                    opacity: 0.6
                    visible: !root.firstLoad && root.errorMsg === ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                visible: root.hasData

                Item { Layout.fillHeight: true }

                LimitRow {
                    Layout.fillWidth: true
                    label: "5-hour window"
                    windowData: root.h5
                    nowMs: root.nowMs
                }

                Item { Layout.fillHeight: true }

                LimitRow {
                    Layout.fillWidth: true
                    label: "7-day window"
                    windowData: root.d7
                    nowMs: root.nowMs
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.limitData && root.limitData.fallback

                    PlasmaComponents.Label {
                        text: "Fallback:"
                        opacity: 0.7
                        font.pixelSize: 11
                    }
                    PlasmaComponents.Label {
                        text: {
                            if (!root.limitData) return ""
                            var t = root.limitData.fallback || ""
                            if (root.limitData.fallback_pct)
                                t += " (" + Math.round(parseFloat(root.limitData.fallback_pct) * 100) + "% capacity)"
                            return t
                        }
                        font.pixelSize: 11
                        color: (root.limitData && root.limitData.fallback === "available")
                               ? Kirigami.Theme.positiveTextColor
                               : Kirigami.Theme.neutralTextColor
                    }
                }
            }

            // Footer: plan · interval · last update
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4
                opacity: 0.6
                visible: !root.loading

                PlasmaComponents.Label {
                    text: root.limitData && root.limitData.plan ? (root.limitData.plan.charAt(0).toUpperCase() + root.limitData.plan.slice(1)) + " ·" : ""
                    font.pixelSize: 10
                    visible: root.limitData && root.limitData.plan
                }

                Kirigami.Icon {
                    source: "view-refresh"
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    Layout.alignment: Qt.AlignVCenter
                }

                PlasmaComponents.Label {
                    text: root.effectiveInterval + " min ·"
                    font.pixelSize: 10
                }

                PlasmaComponents.Label {
                    text: root.lastUpdated ? "Updated " + root.lastUpdated : ""
                    font.pixelSize: 10
                    visible: root.lastUpdated !== ""
                }
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                text: "Refreshing…"
                font.pixelSize: 10
                opacity: 0.6
                visible: root.loading
            }
        }
    }
}
