import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/utils.js" as Utils

Row {
    id: root

    property string label: ""
    // One window object from fetch_limits.sh output (h5 or d7)
    property var windowData: null

    readonly property real utilization: windowData ? windowData.utilization : 0
    readonly property string resetIn: windowData ? (windowData.reset_in || "") : ""
    readonly property string resetTs: windowData ? (windowData.reset_ts || "") : ""
    property double nowMs: Date.now()
    // Dense mode squeezes rows so three bars fit a 44px horizontal panel.
    property bool dense: false
    readonly property int fontSize: 10
    readonly property string resetLabel: Utils.formatReset(resetTs, resetIn, nowMs, true)
    readonly property color barColor: Utils.barColor(
        windowData ? windowData.status : "", utilization,
        Kirigami.Theme.negativeTextColor,
        windowData ? (windowData.severity || "") : "")

    spacing: 2
    width: 16 + 60 + 3 + 25 + resetGroup.implicitWidth + spacing * 4
    height: dense ? 11 : implicitHeight

    PlasmaComponents.Label {
        text: root.label
        font.pixelSize: root.fontSize
        width: 16
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0.8
    }

    Rectangle {
        width: 60
        height: root.dense ? 5 : 6
        radius: 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            width: Math.max(Math.min(root.utilization, 1.0) * parent.width, root.utilization > 0 ? 3 : 0)
            height: parent.height
            radius: parent.radius
            color: root.barColor
        }
    }

    Item { width: 3; height: 1 }

    PlasmaComponents.Label {
        text: Math.round(root.utilization * 100) + "%"
        font.pixelSize: root.fontSize
        width: 25
        anchors.verticalCenter: parent.verticalCenter
    }

    Item {
        id: resetGroup
        implicitWidth: resetIcon.width + 2 + resetText.implicitWidth
        implicitHeight: Math.max(resetIcon.height, resetText.implicitHeight)
        width: implicitWidth
        height: implicitHeight
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0.8

        Kirigami.Icon {
            id: resetIcon
            source: "view-refresh"
            width: root.dense ? 11 : 12
            height: root.dense ? 11 : 12
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        PlasmaComponents.Label {
            id: resetText
            text: root.resetLabel
            font.pixelSize: root.fontSize
            anchors.left: resetIcon.right
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
