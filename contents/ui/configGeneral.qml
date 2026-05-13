import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshInterval: refreshSpinBox.value
    property bool   cfg_showTitle: true
    property string cfg_proxyMode: "env"
    property string cfg_proxyUrl:  ""

    // ── Appearance ────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Appearance"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showTitleCheck
        Kirigami.FormData.label: "Show title:"
        checked: cfg_showTitle
        onCheckedChanged: cfg_showTitle = checked
    }

    // ── Refresh ───────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Refresh"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: refreshSpinBox
        Kirigami.FormData.label: "Interval (minutes):"
        from: 1
        to: 120
        value: 15
        textFromValue: function(v) { return v + " min" }
        valueFromText: function(t) { return parseInt(t) || 15 }
    }

    // ── Proxy ─────────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Proxy"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: proxyCombo
        Kirigami.FormData.label: "Mode:"
        model: [
            { text: "No proxy",              value: "none"   },
            { text: "System env (HTTP_PROXY)", value: "env"  },
            { text: "Custom URL",             value: "custom" }
        ]
        textRole: "text"
        currentIndex: {
            var modes = ["none", "env", "custom"]
            var idx = modes.indexOf(cfg_proxyMode)
            return idx >= 0 ? idx : 1
        }
        onActivated: cfg_proxyMode = model[currentIndex].value
    }

    QQC2.TextField {
        id: proxyUrlField
        Kirigami.FormData.label: "Proxy URL:"
        placeholderText: "http://proxy.example.com:8080"
        text: cfg_proxyUrl
        visible: cfg_proxyMode === "custom"
        onTextChanged: cfg_proxyUrl = text
    }
}
