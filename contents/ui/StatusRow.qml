import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
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
    property int maximumIncidentHeight: 96

    readonly property bool hasStatus: indicator !== "" || errorText !== ""
    readonly property real incidentContentHeight: incidentColumn.implicitHeight

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
            objectName: "statusSummary"
            Layout.fillWidth: true
            text: root.errorText !== ""
                  ? "Status unavailable"
                  : (root.description || "Checking status…")
            font.pixelSize: 11
            opacity: root.errorText !== "" ? 0.6 : 0.9
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    QQC2.ScrollView {
        id: incidentScroll
        objectName: "statusIncidentScroll"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(incidentColumn.implicitHeight, root.maximumIncidentHeight)
        Layout.maximumHeight: root.maximumIncidentHeight
        visible: root.errorText === "" && root.incidents.length > 0
        clip: true
        contentWidth: availableWidth

        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.vertical.policy: incidentColumn.implicitHeight > root.maximumIncidentHeight
                                          ? QQC2.ScrollBar.AsNeeded
                                          : QQC2.ScrollBar.AlwaysOff

        ColumnLayout {
            id: incidentColumn
            width: incidentScroll.availableWidth
            spacing: 2

            Repeater {
                model: root.incidents

                PlasmaComponents.Label {
                    required property int index
                    required property var modelData
                    objectName: "statusIncident" + index
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    text: "• " + (modelData.name || "Incident")
                          + (modelData.status ? " (" + modelData.status + ")" : "")
                    textFormat: Text.PlainText
                    font.pixelSize: 10
                    color: root.severityColor(modelData.impact)
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
