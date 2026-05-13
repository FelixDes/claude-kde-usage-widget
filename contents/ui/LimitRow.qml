import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string label: ""
    property real utilization: 0
    property string status: ""
    property string resetIn: ""
    property string resetTs: ""

    readonly property string resetLabel: {
        if (!resetTs) return resetIn
        var ts = parseInt(resetTs)
        if (isNaN(ts) || ts <= 0) return resetIn
        var diff = ts * 1000 - Date.now()
        if (diff <= 0) return "now"
        var totalMins = Math.round(diff / 60000)
        var days = Math.floor(totalMins / 1440)
        var hrs  = Math.floor((totalMins % 1440) / 60)
        var mins = totalMins % 60
        var parts = []
        if (days > 0) parts.push(days + "d")
        if (hrs  > 0) parts.push(hrs + " hr")
        if (mins > 0) parts.push(mins + " min")
        return parts.length ? parts.join(" ") : "< 1 min"
    }

    readonly property color claudeColor: "#DA7756"
    readonly property bool limited: status === "limited" || status === "blocked"
    readonly property color barColor: limited
        ? Kirigami.Theme.negativeTextColor
        : utilization > 0.85
            ? "#E8A87C"
            : claudeColor

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        PlasmaComponents.Label {
            text: root.label
            font.bold: true
            font.pixelSize: 12
        }

        PlasmaComponents.Label {
            text: Math.round(root.utilization * 100) + "%"
            font.pixelSize: 12
            opacity: 0.7
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents.Label {
            text: root.limited ? "LIMITED" : ""
            font.pixelSize: 10
            color: Kirigami.Theme.negativeTextColor
            visible: root.limited
        }
    }

    // Progress bar background
    Rectangle {
        Layout.fillWidth: true
        height: 7
        radius: 3
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        Rectangle {
            width: Math.max(Math.min(root.utilization, 1.0) * parent.width, root.utilization > 0 ? 4 : 0)
            height: parent.height
            radius: parent.radius
            color: root.barColor
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    PlasmaComponents.Label {
        text: root.resetLabel ? "Resets " + root.resetLabel : ""
        font.pixelSize: 10
        opacity: 0.7
        visible: root.resetIn !== ""
    }
}
