import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

import "../code/utils.js" as Utils
import "../code/stats.js" as Stats

// Usage statistics: where the current session/week is heading, how they
// compare with earlier ones, and how other plans would have coped.
Window {
    id: win

    property string historyScriptPath: ""
    // Bumped by the widget after each successful fetch.
    property int revision: 0
    // Latest fetch result (for the per-client breakdown).
    property var liveData: null
    // { "1": 20, "5": 100, "20": 200, "currency": "$" }
    property var prices: ({})

    property var report: null
    property string reportError: ""
    property bool reportLoading: false

    readonly property int tier: report && report.tier ? report.tier : 0
    readonly property double nowSec: report ? report.now : Date.now() / 1000
    readonly property var planLines: Stats.tierLines(tier)
    readonly property color seriesColor: Utils.CLAUDE_COLOR
    // Theme colors come from the content item: a Window is not an Item, so
    // Kirigami.Theme attached to it does not follow the system color scheme.
    readonly property var theme: content.Kirigami.Theme
    readonly property color mutedColor: Qt.rgba(theme.textColor.r,
        theme.textColor.g, theme.textColor.b, 0.5)

    title: "Claude usage"
    width: 860
    height: 600
    minimumWidth: 600
    minimumHeight: 460
    color: theme.backgroundColor

    onRevisionChanged: if (visible) loadReport()
    onVisibleChanged: if (visible) loadReport()

    P5Support.DataSource {
        id: historyExecutable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            win.reportLoading = false
            disconnectSource(source)
            try {
                win.report = JSON.parse((data["stdout"] || "").trim())
                win.reportError = ""
            } catch (e) {
                win.reportError = (data["stderr"] || "").trim() || "Could not read the usage history"
            }
        }
    }

    function loadReport() {
        if (reportLoading || !historyScriptPath) return
        reportLoading = true
        historyExecutable.connectSource(
            "python3 -I '" + historyScriptPath.replace(/'/g, "'\\''") + "' report")
    }

    function levelColor(level) {
        switch (level) {
            case "critical":
            case "bad":      return theme.negativeTextColor
            case "warn":
            case "notice":   return theme.neutralTextColor
            case "good":     return theme.positiveTextColor
            default:         return theme.textColor
        }
    }

    // Current window, its even-pace line and the projection to its reset.
    function windowSeries(windowData, pace, previous) {
        if (!windowData)
            return []
        var out = [{ "points": windowData.points, "color": seriesColor, "width": 2.5,
                     "dots": windowData.points.length < 30 }]
        out.push({ "points": [[windowData.start, 0], [windowData.reset, 100]],
                   "color": mutedColor, "width": 1, "dash": [4, 4] })
        if (pace && !pace.limited && windowData.points.length > 0) {
            var last = windowData.points[windowData.points.length - 1]
            out.push({ "points": [last, [windowData.reset, Math.min(pace.projected, 1000)]],
                       "color": seriesColor, "width": 1.5, "dash": [3, 3], "opacity": 0.8 })
        }
        for (var i = 0; previous && i < previous.length; ++i) {
            var shifted = []
            for (var p = 0; p < previous[i].points.length; ++p)
                shifted.push([previous[i].points[p][0] + windowData.start, previous[i].points[p][1]])
            // Older weeks fainter.
            out.push({ "points": shifted, "color": mutedColor, "width": 1.5,
                       "opacity": 0.5 + 0.25 * i })
        }
        return out
    }

    function windowYMax(windowData, pace, previous) {
        var values = []
        if (windowData)
            values.push(windowData.peak)
        if (pace && !pace.limited)
            values.push(Math.min(pace.projected, 150))
        for (var i = 0; previous && i < previous.length; ++i)
            values.push(previous[i].peak)
        return Stats.chartYMax(values, planLines)
    }

    function sessionBars() {
        if (!report || !report.sessions)
            return []
        var proLine = tier > 1 ? 100 / tier : 1000
        var bars = []
        for (var i = 0; i < report.sessions.length; ++i) {
            var s = report.sessions[i]
            var color = s.peak >= 99.5 ? theme.negativeTextColor
                : (s.peak >= proLine ? Utils.WARN_COLOR : seriesColor)
            bars.push({
                "value": s.peak,
                "color": color,
                "label": Qt.formatDateTime(new Date(s.start * 1000), "ddd d MMM HH:mm") + "–"
                    + Qt.formatDateTime(new Date(s.reset * 1000), "HH:mm") + " · "
                    + Math.round(s.peak) + "%"
            })
        }
        return bars
    }

    function sessionPeaks() {
        var values = []
        for (var i = 0; report && report.sessions && i < report.sessions.length; ++i)
            values.push(report.sessions[i].peak)
        return values
    }

    Rectangle {
        id: content
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        // ── Where the current windows are heading ───────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: 2

            Rectangle {
                width: 8; height: 8; radius: 4
                color: win.levelColor(sessionPace.level)
            }
            QQC2.Label { text: "Session"; font.bold: true }
            QQC2.Label {
                objectName: "sessionPace"
                Layout.fillWidth: true
                text: sessionPace.text
                color: win.levelColor(sessionPace.level)
                elide: Text.ElideRight
            }

            Rectangle {
                width: 8; height: 8; radius: 4
                color: win.levelColor(weekPace.level)
            }
            QQC2.Label { text: "Week"; font.bold: true }
            QQC2.Label {
                objectName: "weekPace"
                Layout.fillWidth: true
                text: weekPace.text
                color: win.levelColor(weekPace.level)
                elide: Text.ElideRight
            }
        }

        QQC2.Label {
            objectName: "breakdown"
            Layout.fillWidth: true
            readonly property string text_: Stats.breakdownText(win.liveData ? win.liveData.breakdown : null)
            text: "This week by client: " + text_
            visible: text_ !== ""
            opacity: 0.7
            elide: Text.ElideRight
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: win.reportError
            visible: win.reportError !== ""
        }

        QQC2.TabBar {
            id: tabs
            objectName: "tabs"
            Layout.fillWidth: true
            QQC2.TabButton { text: "Week" }
            QQC2.TabButton { text: "Session" }
            QQC2.TabButton { text: "Plan fit" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ── Week ──────────────────────────────────────────────────────────
            ColumnLayout {
                UsageChart {
                    objectName: "weekChart"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property var w: win.report ? win.report.week : null
                    readonly property var pace: win.report ? win.report.pace.week : null
                    readonly property var prev: win.report ? win.report.prev_weeks : []
                    xMin: w ? w.start : 0
                    xMax: w ? w.reset : 1
                    nowX: win.nowSec
                    series: win.windowSeries(w, pace, prev)
                    hLines: win.planLines.map(function(l) {
                        return { "y": l.y, "current": l.current, "label": l.current ? l.label : "≈ " + l.label }
                    })
                    yMax: win.windowYMax(w, pace, prev)
                    xTicks: w ? Stats.timeTicks(w.start, w.reset, win.nowSec) : []
                    pointText: function(x, y) {
                        return Qt.formatDateTime(new Date(x * 1000), "ddd HH:mm") + " · " + Math.round(y) + "%"
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: "Solid: this week · dashed diagonal: even pace to the reset · dashed: projection · "
                        + "faint: previous weeks"
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                }
            }

            // ── Session ───────────────────────────────────────────────────────
            ColumnLayout {
                UsageChart {
                    objectName: "sessionChart"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property var w: win.report ? win.report.session : null
                    readonly property var pace: win.report ? win.report.pace.session : null
                    xMin: w ? w.start : 0
                    xMax: w ? w.reset : 1
                    nowX: win.nowSec
                    series: win.windowSeries(w, pace, [])
                    hLines: win.planLines
                    yMax: win.windowYMax(w, pace, [])
                    xTicks: w ? Stats.timeTicks(w.start, w.reset, win.nowSec) : []
                    pointText: function(x, y) {
                        return Qt.formatDateTime(new Date(x * 1000), "HH:mm") + " · " + Math.round(y) + "%"
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: win.report && !win.report.session
                        ? "No active 5-hour session." : "The 5-hour window starts with your first message."
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }

            // ── Plan fit ──────────────────────────────────────────────────────
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Information
                    visible: win.report !== null && win.report.days < 14
                    text: "Collecting data: " + (win.report ? win.report.days : 0)
                        + " days so far. The plan fit becomes meaningful after about two weeks."
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Warning
                    visible: win.report !== null && !win.tier
                    text: "Your plan's tier is unknown, so other plans cannot be compared."
                }

                UsageChart {
                    objectName: "planFitChart"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    bars: win.sessionBars()
                    hLines: win.planLines
                    yMax: Stats.chartYMax(win.sessionPeaks(), win.planLines)
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    readonly property var fit: win.report ? win.report.plan_fit : null
                    visible: fit !== null && fit.sessions > 0
                    text: fit ? "Last 30 days: " + fit.sessions + " sessions, " + fit.weeks + " weeks · "
                        + "peak session " + Math.round(fit.peak_session || 0) + "% (" + fit.peak_session_pro
                        + "× Pro) · peak week " + Math.round(fit.peak_week || 0) + "%" : ""
                    opacity: 0.8
                }

                Repeater {
                    objectName: "planFitRows"
                    model: win.report ? Stats.planFitRows(win.report.plan_fit, win.tier, win.prices) : []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            text: modelData.name
                            font.bold: modelData.tier === win.tier
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                        }
                        QQC2.Label {
                            text: modelData.price
                            opacity: 0.7
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        }
                        QQC2.Label {
                            text: modelData.verdict
                            color: win.levelColor(modelData.level)
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: "Bars: each 5-hour session's final usage of your plan (light: above Pro's limit, red: "
                        + "hit your own limit). Plan lines use the nominal "
                        + "5x/20x multipliers; weekly comparisons (≈) are approximate because weekly limits "
                        + "are not published per plan."
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                Layout.fillWidth: true
                text: win.report && win.report.first_sample
                    ? "History: " + win.report.samples + " samples since "
                        + Qt.formatDateTime(new Date(win.report.first_sample * 1000), "d MMM yyyy")
                        + " · ~/.local/share/claude-limits-widget/history.jsonl"
                    : "No history yet: samples are recorded on every refresh."
                font: Kirigami.Theme.smallFont
                opacity: 0.6
                elide: Text.ElideMiddle
            }
            QQC2.BusyIndicator {
                running: win.reportLoading
                visible: running
                Layout.preferredHeight: Kirigami.Units.gridUnit
                Layout.preferredWidth: Kirigami.Units.gridUnit
            }
            QQC2.ToolButton {
                icon.name: "view-refresh"
                text: "Reload"
                display: QQC2.AbstractButton.IconOnly
                QQC2.ToolTip.text: "Reload history"
                QQC2.ToolTip.visible: hovered
                onClicked: win.loadReport()
            }
        }
    }

    }

    readonly property var sessionPace: Stats.paceSummary(
        report ? report.pace.session : null, report && report.session ? report.session.reset : 0, nowSec)
    readonly property var weekPace: Stats.paceSummary(
        report ? report.pace.week : null, report && report.week ? report.week.reset : 0, nowSec)
}
