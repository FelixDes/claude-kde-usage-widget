import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/utils.js" as Utils

// Service-status block for the popup: a colored dot + overall description,
// followed by one line per active incident.
ColumnLayout {
    id: root

    property string indicator: ""
    property string description: ""
    property var incidents: []
    property string errorText: ""

    // True once we have either a status payload or an error to show.
    readonly property bool hasStatus: description !== "" || errorText !== ""

    function severityColor(sev) {
        return Utils.severityColor(
            sev,
            Kirigami.Theme.positiveTextColor,
            Kirigami.Theme.neutralTextColor,
            Kirigami.Theme.negativeTextColor,
            Kirigami.Theme.disabledTextColor)
    }

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            Layout.alignment: Qt.AlignVCenter
            color: root.errorText !== ""
                   ? Kirigami.Theme.disabledTextColor
                   : root.severityColor(root.indicator)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.errorText !== ""
                  ? "Status unavailable"
                  : (root.description || "Checking status…")
            font.pixelSize: 11
            opacity: root.errorText !== "" ? 0.6 : 0.9
            elide: Text.ElideRight
        }
    }

    Repeater {
        model: root.incidents

        PlasmaComponents.Label {
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: 14
            text: "• " + (modelData.name || "Incident")
                  + (modelData.status ? " (" + modelData.status + ")" : "")
            font.pixelSize: 10
            color: root.severityColor(modelData.impact)
            wrapMode: Text.WordWrap
        }
    }
}
