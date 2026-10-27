import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_refreshInterval: refreshSpinBox.value
    property alias cfg_showTitle: showTitleCheck.checked
    property alias cfg_showServiceStatus: showServiceStatusCheck.checked
    property alias cfg_statusRefreshInterval: statusRefreshSpinBox.value
    property string cfg_proxyMode: "env"
    property alias cfg_proxyUrl: proxyUrlField.text
    property alias cfg_pricePro: priceProSpinBox.value
    property alias cfg_priceMax5: priceMax5SpinBox.value
    property alias cfg_priceMax20: priceMax20SpinBox.value
    property alias cfg_priceCurrency: priceCurrencyField.text

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

    QQC2.CheckBox {
        id: showServiceStatusCheck
        Kirigami.FormData.label: "Show service status:"
    }

    // ── Refresh ───────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Refresh"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: refreshSpinBox
        Kirigami.FormData.label: "Limits interval:"
        // The usage endpoint throttles faster polling.
        from: 5
        to: 120
        value: 15
        textFromValue: function(v) { return v + " min" }
        valueFromText: function(t) { return parseInt(t) || 15 }
    }

    QQC2.SpinBox {
        id: statusRefreshSpinBox
        Kirigami.FormData.label: "Status interval:"
        from: 1
        to: 120
        value: 5
        enabled: showServiceStatusCheck.checked
        textFromValue: function(v) { return v + " min" }
        valueFromText: function(t) { return parseInt(t) || 5 }
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

    // ── Plans ─────────────────────────────────────────────────────────────────
    Kirigami.Heading {
        text: "Plan prices"
        level: 3
        Kirigami.FormData.isSection: true
    }

    QQC2.Label {
        text: "Monthly prices, used by the plan fit in the statistics window."
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
    }

    QQC2.SpinBox {
        id: priceProSpinBox
        Kirigami.FormData.label: "Pro:"
        from: 0
        to: 10000
        value: 20
    }

    QQC2.SpinBox {
        id: priceMax5SpinBox
        Kirigami.FormData.label: "Max 5x:"
        from: 0
        to: 10000
        value: 100
    }

    QQC2.SpinBox {
        id: priceMax20SpinBox
        Kirigami.FormData.label: "Max 20x:"
        from: 0
        to: 10000
        value: 200
    }

    QQC2.TextField {
        id: priceCurrencyField
        Kirigami.FormData.label: "Currency:"
        placeholderText: "$"
        maximumLength: 8
        Layout.maximumWidth: Kirigami.Units.gridUnit * 5
    }
}
