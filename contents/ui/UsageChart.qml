import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Small dependency-free chart on a Canvas, in one of two modes:
//   lines: series of [x, y] points over xMin..xMax (x in epoch seconds)
//   bars:  one bar per entry of `bars`, evenly spaced (x is the index)
// Plan limits are drawn as labelled horizontal lines; lines above yMax are
// listed as off-scale at the top instead.
Item {
    id: chart

    // [{ points: [[x, y], ...], color, width, dash: [on, off], opacity, label }]
    property var series: []
    // [{ value, color, label }]
    property var bars: []
    // [{ y, label, current }]
    property var hLines: []
    // [{ x, label }]
    property var xTicks: []
    property real xMin: 0
    property real xMax: 1
    property real yMax: 100
    property real nowX: -1
    // Formats a hovered line point: function(x, y) -> string
    property var pointText: function(x, y) { return Math.round(y) + "%" }

    readonly property bool barMode: bars.length > 0
    readonly property int leftPad: 40
    readonly property int rightPad: 92
    readonly property int topPad: 14
    readonly property int bottomPad: 20
    readonly property real plotWidth: Math.max(1, width - leftPad - rightPad)
    readonly property real plotHeight: Math.max(1, height - topPad - bottomPad)

    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color gridColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)
    readonly property color lineColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.45)

    property string hoverText: ""
    property real hoverX: -1

    function px(x) {
        if (barMode)
            return leftPad + (x + 0.5) * plotWidth / Math.max(1, bars.length)
        return leftPad + (x - xMin) / Math.max(1, xMax - xMin) * plotWidth
    }

    function py(y) {
        return topPad + plotHeight - Math.max(0, Math.min(y, yMax)) / yMax * plotHeight
    }

    function yStep() {
        if (yMax <= 60) return 10
        if (yMax <= 150) return 25
        if (yMax <= 400) return 50
        return 100
    }

    onSeriesChanged: canvas.requestPaint()
    onBarsChanged: canvas.requestPaint()
    onHLinesChanged: canvas.requestPaint()
    onXTicksChanged: canvas.requestPaint()
    onYMaxChanged: canvas.requestPaint()
    onXMinChanged: canvas.requestPaint()
    onXMaxChanged: canvas.requestPaint()
    onNowXChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        function dash(ctx, pattern) {
            if (ctx.setLineDash)
                ctx.setLineDash(pattern || [])
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.font = Kirigami.Theme.smallFont.pixelSize > 0
                ? Kirigami.Theme.smallFont.pixelSize + "px sans-serif" : "10px sans-serif"
            ctx.lineWidth = 1

            // Y grid and labels
            ctx.textAlign = "right"
            ctx.textBaseline = "middle"
            for (var gy = 0; gy <= chart.yMax + 0.01; gy += chart.yStep()) {
                ctx.strokeStyle = chart.gridColor
                dash(ctx, [])
                ctx.beginPath()
                ctx.moveTo(chart.leftPad, chart.py(gy))
                ctx.lineTo(chart.leftPad + chart.plotWidth, chart.py(gy))
                ctx.stroke()
                ctx.fillStyle = chart.lineColor
                ctx.fillText(gy + "%", chart.leftPad - 4, chart.py(gy))
            }

            // X ticks
            ctx.textAlign = "center"
            ctx.textBaseline = "top"
            for (var i = 0; i < chart.xTicks.length; ++i) {
                var tx = chart.px(chart.xTicks[i].x)
                ctx.strokeStyle = chart.gridColor
                ctx.beginPath()
                ctx.moveTo(tx, chart.topPad)
                ctx.lineTo(tx, chart.topPad + chart.plotHeight)
                ctx.stroke()
                ctx.fillStyle = chart.lineColor
                ctx.fillText(chart.xTicks[i].label, tx, chart.topPad + chart.plotHeight + 4)
            }

            // "Now" marker
            if (!chart.barMode && chart.nowX > chart.xMin && chart.nowX < chart.xMax) {
                ctx.strokeStyle = chart.lineColor
                dash(ctx, [2, 3])
                ctx.beginPath()
                ctx.moveTo(chart.px(chart.nowX), chart.topPad)
                ctx.lineTo(chart.px(chart.nowX), chart.topPad + chart.plotHeight)
                ctx.stroke()
            }

            // Bars
            var slot = chart.plotWidth / Math.max(1, chart.bars.length)
            var barWidth = Math.max(1, Math.min(18, slot * 0.7))
            for (var b = 0; b < chart.bars.length; ++b) {
                var bar = chart.bars[b]
                var top = chart.py(bar.value)
                ctx.fillStyle = bar.color
                ctx.fillRect(chart.px(b) - barWidth / 2, top,
                             barWidth, chart.topPad + chart.plotHeight - top)
            }

            // Series, last first so the primary (hovered) series ends up on top
            for (var s = chart.series.length - 1; s >= 0; --s) {
                var line = chart.series[s]
                if (!line.points || line.points.length === 0)
                    continue
                ctx.globalAlpha = line.opacity !== undefined ? line.opacity : 1
                ctx.strokeStyle = line.color
                ctx.lineWidth = line.width || 2
                dash(ctx, line.dash)
                ctx.beginPath()
                for (var p = 0; p < line.points.length; ++p) {
                    var x = chart.px(line.points[p][0])
                    var y = chart.py(line.points[p][1])
                    if (p === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                if (line.points.length === 1 || line.dots) {
                    ctx.fillStyle = line.color
                    for (var d = 0; d < line.points.length; ++d) {
                        ctx.beginPath()
                        ctx.arc(chart.px(line.points[d][0]), chart.py(line.points[d][1]),
                                2.5, 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
                ctx.globalAlpha = 1
                ctx.lineWidth = 1
            }

            // Plan lines
            ctx.textAlign = "left"
            ctx.textBaseline = "middle"
            var offScale = []
            for (var h = 0; h < chart.hLines.length; ++h) {
                var hl = chart.hLines[h]
                if (hl.y > chart.yMax) {
                    offScale.push(hl.label + " " + Math.round(hl.y) + "%")
                    continue
                }
                var hy = chart.py(hl.y)
                ctx.strokeStyle = hl.current ? chart.textColor : chart.lineColor
                ctx.lineWidth = hl.current ? 1.5 : 1
                dash(ctx, hl.current ? [] : [6, 4])
                ctx.beginPath()
                ctx.moveTo(chart.leftPad, hy)
                ctx.lineTo(chart.leftPad + chart.plotWidth, hy)
                ctx.stroke()
                ctx.fillStyle = hl.current ? chart.textColor : chart.lineColor
                ctx.fillText(hl.label, chart.leftPad + chart.plotWidth + 6, hy)
                ctx.lineWidth = 1
            }
            if (offScale.length > 0) {
                ctx.fillStyle = chart.lineColor
                ctx.textAlign = "right"
                ctx.textBaseline = "top"
                ctx.fillText("↑ off-scale: " + offScale.join(", "), chart.width - 2, 0)
            }
            dash(ctx, [])
        }
    }

    // Hover readout: nearest point of the first series, or the bar under the cursor.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onExited: chart.hoverX = -1
        onPositionChanged: function(mouse) {
            if (mouse.x < chart.leftPad || mouse.x > chart.leftPad + chart.plotWidth) {
                chart.hoverX = -1
                return
            }
            if (chart.barMode) {
                var index = Math.floor((mouse.x - chart.leftPad) / chart.plotWidth * chart.bars.length)
                index = Math.max(0, Math.min(chart.bars.length - 1, index))
                chart.hoverX = chart.px(index)
                chart.hoverText = chart.bars[index].label
                return
            }
            var points = chart.series.length > 0 ? chart.series[0].points : []
            if (!points || points.length === 0) {
                chart.hoverX = -1
                return
            }
            var best = 0
            for (var i = 1; i < points.length; ++i) {
                if (Math.abs(chart.px(points[i][0]) - mouse.x) < Math.abs(chart.px(points[best][0]) - mouse.x))
                    best = i
            }
            chart.hoverX = chart.px(points[best][0])
            chart.hoverText = chart.pointText(points[best][0], points[best][1])
        }
    }

    Rectangle {
        visible: chart.hoverX >= 0
        x: chart.hoverX
        y: chart.topPad
        width: 1
        height: chart.plotHeight
        color: chart.lineColor
    }

    QQC2.Label {
        visible: chart.hoverX >= 0
        text: chart.hoverText
        x: Math.min(Math.max(chart.leftPad, chart.hoverX + 6), chart.width - width - 2)
        y: chart.topPad
        padding: 3
        font: Kirigami.Theme.smallFont
        background: Rectangle {
            color: Kirigami.Theme.backgroundColor
            border.color: chart.gridColor
            radius: 3
        }
    }
}
