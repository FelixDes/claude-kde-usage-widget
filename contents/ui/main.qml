import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

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

    readonly property string scriptPath: Qt.resolvedUrl("../code/fetch_limits.sh").toString().replace("file://", "")

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
                    var now = new Date()
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
        var safePath    = root.scriptPath.replace(/'/g, "'\\''")
        var safeProxy   = (Plasmoid.configuration.proxyUrl || "").replace(/'/g, "'\\''")
        var proxyMode   = Plasmoid.configuration.proxyMode || "env"
        executable.connectSource("bash '" + safePath + "' '" + proxyMode + "' '" + safeProxy + "'")
    }

    readonly property int effectiveInterval: Math.max(1, Plasmoid.configuration.refreshInterval || 15)

    Timer {
        interval: root.effectiveInterval * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchLimits()
    }

    Timer {
        id: startupTimer
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.fetchLimits()
    }

    // ── Compact (panel bar) ──────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: compactRoot

        // Tell the panel how wide/tall we want to be. Plasma's panel layout
        // reads the Layout.* attached properties; implicitWidth alone is
        // ignored, which is why the applet gets squeezed to icon width.
        readonly property int desiredWidth: 150

        implicitWidth: desiredWidth
        implicitHeight: compactCol.implicitHeight + 4

        Layout.minimumWidth: desiredWidth
        Layout.preferredWidth: desiredWidth
        Layout.maximumWidth: desiredWidth * 2

        onClicked: root.expanded = !root.expanded

        Column {
            id: compactCol
            anchors.centerIn: parent
            spacing: 2

            CompactBar {
                label: "5h"
                utilization: root.limitData ? root.limitData.h5.utilization : 0
                status:      root.limitData ? root.limitData.h5.status : ""
                resetIn:     root.limitData ? root.limitData.h5.reset_in : ""
                visible:     root.limitData !== null
            }
            CompactBar {
                label: "7d"
                utilization: root.limitData ? root.limitData.d7.utilization : 0
                status:      root.limitData ? root.limitData.d7.status : ""
                resetIn:     root.limitData ? root.limitData.d7.reset_in : ""
                visible:     root.limitData !== null
            }

            PlasmaComponents.Label {
                text: root.loading ? "…" : (root.errorMsg ? "!" : "")
                font.pixelSize: 9
                visible: root.loading || root.errorMsg !== ""
            }
        }
    }

    // ── Full popup ───────────────────────────────────────────────────────────
    fullRepresentation: Item {
        implicitWidth: 250
        implicitHeight: 170

        Layout.minimumWidth: 250
        Layout.preferredWidth: 250
        Layout.preferredHeight: 170
        Layout.maximumHeight: 170

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                visible: Plasmoid.configuration.showTitle

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

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.errorMsg
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                visible: root.errorMsg !== "" && !root.loading
            }

            PlasmaComponents.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.loading && root.limitData === null
                running: visible
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                visible: root.limitData !== null

                Item { Layout.fillHeight: true }

                LimitRow {
                    Layout.fillWidth: true
                    label:       "5-hour window"
                    utilization: root.limitData ? root.limitData.h5.utilization : 0
                    status:      root.limitData ? root.limitData.h5.status : ""
                    resetIn:     root.limitData ? root.limitData.h5.reset_in : ""
                    resetTs:     root.limitData ? (root.limitData.h5.reset_ts || "") : ""
                }

                Item { Layout.fillHeight: true }

                LimitRow {
                    Layout.fillWidth: true
                    label:       "7-day window"
                    utilization: root.limitData ? root.limitData.d7.utilization : 0
                    status:      root.limitData ? root.limitData.d7.status : ""
                    resetIn:     root.limitData ? root.limitData.d7.reset_in : ""
                    resetTs:     root.limitData ? (root.limitData.d7.reset_ts || "") : ""
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
                    id: intervalLabel
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
