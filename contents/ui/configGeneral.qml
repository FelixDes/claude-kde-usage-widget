import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshInterval: refreshSpinBox.value
    property alias cfg_showTitle: showTitleCheck.checked
    property string cfg_proxyMode: "env"
    property alias cfg_proxyUrl: proxyUrlField.text

    // ── Appearance ────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Appearance"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showTitleCheck
        Kirigami.FormData.label: "Show title:"
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
        model: ["No proxy", "System env (HTTP_PROXY)", "Custom URL"]
        currentIndex: {
            var idx = ["none", "env", "custom"].indexOf(cfg_proxyMode)
            return idx >= 0 ? idx : 1
        }
        onActivated: cfg_proxyMode = ["none", "env", "custom"][currentIndex]
    }

    QQC2.TextField {
        id: proxyUrlField
        Kirigami.FormData.label: "Proxy URL:"
        placeholderText: "http://proxy.example.com:8080"
        visible: cfg_proxyMode === "custom"
    }
}
