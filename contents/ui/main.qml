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
    property bool statusLoading: false
    property double statusUpdatedMs: 0

    // Optional per-model weekly limits (currently Fable) from the OAuth usage
    // endpoint. Kept separate so a throttled endpoint cannot break 5h/7d.
    property var modelLimitData: []
    property string modelLimitsError: ""
    property bool modelLimitsLoading: false
    property double modelLimitsUpdatedMs: 0
    property double modelLimitsLastAttemptMs: 0

    readonly property bool showServiceStatus: Plasmoid.configuration.showServiceStatus !== false
    readonly property int effectiveStatusInterval: Math.max(
        1, Plasmoid.configuration.statusRefreshInterval || 5)
    readonly property bool statusFresh: showServiceStatus
        && statusData !== null
        && statusUpdatedMs > 0
        && nowMs - statusUpdatedMs <= (effectiveStatusInterval * 2 + 1) * 60 * 1000
    readonly property var visibleStatusData: statusFresh ? statusData : null
    readonly property var incidents: visibleStatusData && visibleStatusData.incidents
        ? visibleStatusData.incidents : []
    readonly property string statusIndicator: visibleStatusData
        ? (visibleStatusData.indicator || "") : ""
    readonly property string statusDescription: visibleStatusData
        ? (visibleStatusData.description || "") : ""
    readonly property string statusSeverity: Utils.aggregateStatusSeverity(
        statusIndicator, incidents)
    readonly property string statusDisplayError: showServiceStatus
        ? (statusError || (statusData !== null && !statusFresh ? "Status data is stale" : ""))
        : ""
    readonly property bool statusDegraded: statusFresh
        && ((statusIndicator !== "" && statusIndicator !== "none") || incidents.length > 0)

    readonly property int modelLimitsInterval: 15
    readonly property bool modelLimitsFresh: modelLimitsUpdatedMs > 0
        && nowMs - modelLimitsUpdatedMs <= (modelLimitsInterval * 3 + 1) * 60 * 1000
    readonly property var fable: modelLimitsFresh
        ? Utils.findModelLimit(modelLimitData, "fable") : null

    readonly property var h5: limitData ? limitData.h5 : null
    readonly property var d7: limitData ? limitData.d7 : null
    readonly property bool hasData: limitData !== null
    readonly property bool firstLoad: loading && !hasData
    readonly property bool anyLoading: loading || statusLoading || modelLimitsLoading

    readonly property int effectiveInterval: Math.max(1, Plasmoid.configuration.refreshInterval || 15)
    readonly property bool showTitle: Plasmoid.configuration.showTitle !== false
    readonly property string proxyMode: {
        var configured = Plasmoid.configuration.proxyMode || "env"
        return ["none", "env", "custom"].indexOf(configured) >= 0 ? configured : "env"
    }

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch_limits.sh").toString().replace("file://", "")
    readonly property string statusScriptPath: Qt.resolvedUrl("../code/fetch_status.sh").toString().replace("file://", "")
    readonly property string modelLimitsScriptPath: Qt.resolvedUrl("../code/fetch_model_limits.sh").toString().replace("file://", "")

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
        executable.connectSource("bash '" + safePath + "' '" + root.proxyMode + "' '" + safeProxy + "'")
    }

    P5Support.DataSource {
        id: statusExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.statusLoading = false
            disconnectSource(source)

            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            var result = Utils.parseStatusOutput(stdout, stderr)

            // Replace the complete snapshot so a failed refresh can never
            // leave an old green status or stale incidents on screen.
            root.statusData = result.data
            root.statusError = result.error
            root.statusUpdatedMs = result.data ? Date.now() : 0
        }
    }

    function fetchStatus() {
        if (!root.showServiceStatus || root.statusLoading) return
        root.statusLoading = true
        var safePath  = root.statusScriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        statusExecutable.connectSource("bash '" + safePath + "' '" + root.proxyMode + "' '" + safeProxy + "'")
    }

    P5Support.DataSource {
        id: modelLimitsExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.modelLimitsLoading = false
            disconnectSource(source)

            var result = Utils.parseModelLimitsOutput(
                data["stdout"] || "", data["stderr"] || "")
            if (result.data === null) {
                // Keep the last successful snapshot for transient 429/network
                // failures. modelLimitsFresh eventually hides genuinely stale data.
                root.modelLimitsError = result.error
                return
            }

            root.modelLimitData = result.data
            root.modelLimitsError = ""
            root.modelLimitsUpdatedMs = Date.now()
        }
    }

    function fetchModelLimits(force) {
        if (root.modelLimitsLoading) return
        var attemptMs = Date.now()
        if (!force && attemptMs - root.modelLimitsLastAttemptMs < 60 * 1000) return
        root.modelLimitsLoading = true
        root.modelLimitsLastAttemptMs = attemptMs
        var safePath = root.modelLimitsScriptPath.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        modelLimitsExecutable.connectSource(
            "bash '" + safePath + "' '" + root.proxyMode + "' '" + safeProxy + "'")
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

    // Service status is free to poll and has its own configurable cadence.
    Timer {
        interval: root.effectiveStatusInterval * 60 * 1000
        running: root.showServiceStatus
        repeat: true
        triggeredOnStart: true
        onTriggered: root.fetchStatus()
    }

    // The usage endpoint is shared with Claude Code and rate-limits more
    // aggressively than the inference API, so model-scoped weekly limits use
    // a conservative independent cadence.
    Timer {
        interval: root.modelLimitsInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchModelLimits()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.fetchModelLimits()
    }

    // ── Compact (panel bar) ──────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: compactRoot

        // Tell the panel how wide/tall we want to be. Plasma's panel layout
        // reads the Layout.* attached properties; implicitWidth alone is
        // ignored, which is why the applet gets squeezed to icon width.
        readonly property int minimumDesiredWidth: 150
        readonly property int sideContentSpace: compactSide.visible
            ? Math.ceil(compactSide.implicitWidth + 5) : 0
        readonly property int desiredWidth: Math.max(
            minimumDesiredWidth, Math.ceil(compactCol.width + sideContentSpace + 8))

        implicitWidth: desiredWidth
        implicitHeight: Math.max(compactCol.implicitHeight, compactSide.implicitHeight) + (compactCol.dense ? 0 : 4)

        Layout.minimumWidth: desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth: desiredWidth * 2

        onClicked: root.expanded = !root.expanded

        Column {
            id: compactCol
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: -compactRoot.sideContentSpace / 2
            width: Math.max(compactH5.width, compactD7.width, compactFable.width)
            // Three rows (with Fable) use dense bars to fit a 44px panel.
            readonly property bool dense: compactFable.visible
            spacing: dense ? 0 : 2

            CompactBar {
                id: compactH5
                dense: compactCol.dense
                label: "5h"
                windowData: root.h5
                nowMs: root.nowMs
                visible: root.hasData
            }
            CompactBar {
                id: compactD7
                dense: compactCol.dense
                label: "7d"
                windowData: root.d7
                nowMs: root.nowMs
                visible: root.hasData
            }
            CompactBar {
                id: compactFable
                dense: compactCol.dense
                objectName: "compactFable"
                label: "F"
                windowData: root.fable
                nowMs: root.nowMs
                visible: root.fable !== null
            }
            PlasmaComponents.Label {
                text: root.firstLoad ? "…" : (root.errorMsg ? "!" : "")
                font.pixelSize: 9
                visible: !compactCol.dense && (root.firstLoad || root.errorMsg !== "")
            }
        }

        // Service status (and, in dense mode, the error mark) stays beside the
        // bars so it never adds a fourth row.
        Column {
            id: compactSide
            anchors.left: compactCol.right
            anchors.leftMargin: 5
            anchors.verticalCenter: compactCol.verticalCenter
            spacing: 2
            visible: root.statusDegraded || compactErrorMark.visible

            PlasmaComponents.Label {
                id: compactErrorMark
                text: "!"
                font.bold: true
                font.pixelSize: 9
                color: Kirigami.Theme.negativeTextColor
                visible: compactCol.dense && root.errorMsg !== ""
            }

            Row {
                id: statusBadge
                spacing: 3
                visible: root.statusDegraded

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Utils.severityColor(
                        root.statusSeverity,
                        Kirigami.Theme.positiveTextColor,
                        Kirigami.Theme.neutralTextColor,
                        Kirigami.Theme.negativeTextColor,
                        Kirigami.Theme.disabledTextColor)
                }

                PlasmaComponents.Label {
                    text: root.incidents.length > 0 ? "issue" : "degraded"
                    textFormat: Text.PlainText
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Full popup ───────────────────────────────────────────────────────────
    fullRepresentation: Item {
        readonly property int popupWidth: 260
        readonly property int statusExtraHeight: statusRow.visible
            ? Math.ceil(statusRow.implicitHeight + Kirigami.Units.largeSpacing) : 0
        readonly property int limitsExtraHeight: root.fable !== null ? 48 : 0
        readonly property int popupHeight: Math.min(
            400, 190 + limitsExtraHeight + statusExtraHeight)

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
                    QQC2.ToolTip.text: root.modelLimitsError !== ""
                        ? "Refresh now\nFable: " + root.modelLimitsError
                        : "Refresh now"
                    QQC2.ToolTip.visible: hovered
                    enabled: !root.anyLoading
                    onClicked: {
                        root.fetchLimits()
                        root.fetchStatus()
                        root.fetchModelLimits(true)
                    }
                }
            }

            // Service status (status.claude.com)
            StatusRow {
                id: statusRow
                Layout.fillWidth: true
                indicator: root.statusSeverity
                description: root.statusDescription
                incidents: root.incidents
                errorText: root.statusDisplayError
                visible: root.showServiceStatus && hasStatus
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
                visible: !root.hasData && root.fable === null

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
                visible: root.hasData || root.fable !== null

                Item { Layout.fillHeight: true }

                LimitRow {
                    Layout.fillWidth: true
                    label: "5-hour window"
                    windowData: root.h5
                    nowMs: root.nowMs
                    visible: root.hasData
                }

                Item {
                    Layout.fillHeight: true
                    visible: root.hasData
                }

                LimitRow {
                    Layout.fillWidth: true
                    label: "7-day window"
                    windowData: root.d7
                    nowMs: root.nowMs
                    visible: root.hasData
                }

                Item {
                    Layout.fillHeight: true
                    visible: root.fable !== null
                }

                LimitRow {
                    objectName: "fullFable"
                    Layout.fillWidth: true
                    label: root.fable ? (root.fable.label || "Fable") + " weekly" : "Fable weekly"
                    windowData: root.fable
                    nowMs: root.nowMs
                    visible: root.fable !== null
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
                visible: !root.anyLoading

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
                visible: root.anyLoading
            }
        }
    }
}
