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
    readonly property color barColor: Utils.barColor(
        windowData ? windowData.status : "", utilization,
        Kirigami.Theme.negativeTextColor)

    spacing: 2

    PlasmaComponents.Label {
        text: root.label
        font.pixelSize: 10
        width: 16
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0.8
    }

    Rectangle {
        width: 60
        height: 6
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
        width: 25
        font.pixelSize: 10
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        opacity: 0.8

        Kirigami.Icon {
            source: "view-refresh"
            width: 12
            height: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        PlasmaComponents.Label {
            text: root.resetIn
            font.pixelSize: 10
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
