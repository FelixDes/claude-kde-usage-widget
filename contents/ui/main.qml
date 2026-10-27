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

    // 5h/7d limits. They normally come from the free OAuth usage endpoint
    // (fetch_usage.sh); the token-costing probe (fetch_limits.sh) is only a
    // fallback while that endpoint is throttled.
    property var limitData: null
    property string errorMsg: ""
    property bool loading: false
    property bool probeLoading: false
    property string lastUpdated: ""
    property double nowMs: Date.now()
    // Consecutive failures, used to back off retries (the network or VPN may
    // still be coming up right after login).
    property int limitsRetries: 0

    // Service status from status.claude.com (free, no token cost).
    property var statusData: null
    property string statusError: ""
    property bool statusLoading: false
    property double statusUpdatedMs: 0

    // Optional per-model weekly limits (currently Fable), from the same usage
    // response. Kept through probe fallbacks; modelLimitsFresh hides old data.
    property var modelLimitData: []
    property double modelLimitsUpdatedMs: 0

    // Bumped after every successful fetch so an open statistics window can
    // reload the history.
    property int historyRevision: 0
    property var statsWindow: null

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

    readonly property bool modelLimitsFresh: modelLimitsUpdatedMs > 0
        && nowMs - modelLimitsUpdatedMs <= (effectiveInterval * 3 + 1) * 60 * 1000
    readonly property var fable: modelLimitsFresh
        ? Utils.findModelLimit(modelLimitData, "fable") : null

    readonly property var h5: limitData ? limitData.h5 : null
    readonly property var d7: limitData ? limitData.d7 : null
    readonly property bool hasData: limitData !== null
    readonly property bool firstLoad: (loading || probeLoading) && !hasData
    readonly property bool anyLoading: loading || probeLoading || statusLoading

    // The usage endpoint is shared with Claude Code and throttles hard, so
    // polling is never faster than every 5 minutes.
    readonly property int effectiveInterval: Math.max(5, Plasmoid.configuration.refreshInterval || 15)
    readonly property bool showTitle: Plasmoid.configuration.showTitle !== false
    readonly property string proxyMode: {
        var configured = Plasmoid.configuration.proxyMode || "env"
        return ["none", "env", "custom"].indexOf(configured) >= 0 ? configured : "env"
    }

    readonly property string usageScriptPath: Qt.resolvedUrl("../code/fetch_usage.sh").toString().replace("file://", "")
    readonly property string probeScriptPath: Qt.resolvedUrl("../code/fetch_limits.sh").toString().replace("file://", "")
    readonly property string statusScriptPath: Qt.resolvedUrl("../code/fetch_status.sh").toString().replace("file://", "")
    readonly property string historyScriptPath: Qt.resolvedUrl("../code/history.py").toString().replace("file://", "")

    function scriptCommand(path) {
        var safePath  = path.replace(/'/g, "'\\''")
        var safeProxy = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        return "bash '" + safePath + "' '" + root.proxyMode + "' '" + safeProxy + "'"
    }

    function parseScriptOutput(data) {
        var stdout = (data["stdout"] || "").trim()
        if (!stdout)
            return { "error": data["stderr"] || "No output from script" }
        try {
            var parsed = JSON.parse(stdout)
            return parsed && typeof parsed === "object" ? parsed : { "error": "Invalid output" }
        } catch (e) {
            return { "error": "Parse error: " + stdout.substring(0, 80) }
        }
    }

    function limitsSucceeded(parsed) {
        root.limitData = parsed
        root.errorMsg = ""
        root.limitsRetries = 0
        limitsRetryTimer.stop()
        root.nowMs = Date.now()
        var now = new Date(root.nowMs)
        root.lastUpdated = now.getHours() + ":" + String(now.getMinutes()).padStart(2, "0")
        root.historyRevision += 1
    }

    function limitsFailed(message) {
        root.errorMsg = message
        limitsRetryTimer.interval = Utils.retryDelayMs(
            root.limitsRetries, 15 * 1000, root.effectiveInterval * 60 * 1000)
        root.limitsRetries += 1
        limitsRetryTimer.restart()
    }

    P5Support.DataSource {
        id: usageExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.loading = false
            disconnectSource(source)

            var parsed = root.parseScriptOutput(data)
            if (parsed.error) {
                // Throttled or odd response: the probe still knows 5h/7d.
                if (parsed.fallback === true)
                    root.fetchProbe()
                else
                    root.limitsFailed(parsed.error)
                return
            }
            if (Array.isArray(parsed.model_limits)) {
                root.modelLimitData = Utils.parseModelLimitsOutput(
                    JSON.stringify({ "model_limits": parsed.model_limits }), "").data || []
                root.modelLimitsUpdatedMs = Date.now()
            }
            root.limitsSucceeded(parsed)
        }
    }

    function fetchUsage() {
        if (root.loading || root.probeLoading) return
        root.loading = true
        usageExecutable.connectSource(root.scriptCommand(root.usageScriptPath))
    }

    P5Support.DataSource {
        id: probeExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            root.probeLoading = false
            disconnectSource(source)

            var parsed = root.parseScriptOutput(data)
            if (parsed.error) {
                root.limitData = null
                root.limitsFailed(parsed.error)
                return
            }
            root.limitsSucceeded(parsed)
        }
    }

    function fetchProbe() {
        if (root.probeLoading) return
        root.probeLoading = true
        probeExecutable.connectSource(root.scriptCommand(root.probeScriptPath))
    }

    // Kept for callers that just want "refresh the limits".
    function fetchLimits() {
        root.fetchUsage()
    }

    Timer {
        id: limitsRetryTimer
        repeat: false
        onTriggered: root.fetchUsage()
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
        statusExecutable.connectSource(root.scriptCommand(root.statusScriptPath))
    }

    function openStats() {
        if (root.statsWindow === null) {
            var component = Qt.createComponent("StatsWindow.qml")
            if (component.status !== Component.Ready) {
                console.warn("StatsWindow:", component.errorString())
                return
            }
            root.statsWindow = component.createObject(null, {
                "historyScriptPath": root.historyScriptPath,
                "revision": Qt.binding(function() { return root.historyRevision }),
                "liveData": Qt.binding(function() { return root.limitData }),
                "prices": Qt.binding(function() {
                    var cfg = Plasmoid.configuration || {}
                    return {
                        "1": cfg.pricePro,
                        "5": cfg.priceMax5,
                        "20": cfg.priceMax20,
                        "currency": cfg.priceCurrency || "$"
                    }
                })
            })
        }
        root.statsWindow.show()
        root.statsWindow.raise()
        root.statsWindow.requestActivate()
    }

    Component.onDestruction: {
        if (root.statsWindow !== null)
            root.statsWindow.destroy()
    }

    Timer {
        interval: root.effectiveInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchUsage()
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
        onTriggered: root.fetchUsage()
    }

    // Service status is free to poll and has its own configurable cadence.
    Timer {
        interval: root.effectiveStatusInterval * 60 * 1000
        running: root.showServiceStatus
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

                PlasmaComponents.Label {
                    text: "Claude Limits"
                    font.bold: true
                    font.pixelSize: 14
                    visible: root.showTitle
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.ToolButton {
                    objectName: "statsButton"
                    icon.name: "office-chart-line"
                    QQC2.ToolTip.text: "Usage statistics"
                    QQC2.ToolTip.visible: hovered
                    onClicked: root.openStats()
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    QQC2.ToolTip.text: "Refresh now"
                    QQC2.ToolTip.visible: hovered
                    enabled: !root.anyLoading
                    onClicked: {
                        root.fetchUsage()
                        root.fetchStatus()
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
                visible: root.errorMsg !== "" && !root.loading && !root.probeLoading
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
                    visible: !!(root.limitData && root.limitData.fallback)

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
                    text: root.limitData && root.limitData.plan
                        ? Utils.planLabel(root.limitData.plan, root.limitData.tier) + " ·" : ""
                    font.pixelSize: 10
                    visible: !!(root.limitData && root.limitData.plan)
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
