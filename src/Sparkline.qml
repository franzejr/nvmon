import QtQuick

// A small history chart. Samples fill from the right, so a fresh window shows
// a short line that grows leftward as history builds up.
Canvas {
    id: chart

    property var values: []
    property int capacity: 150
    property real minValue: 0
    property real maxValue: 100
    // Draws a step line, for values that jump between levels (the PCIe
    // generation) rather than drift (a temperature).
    property bool steps: false
    property color lineColor: "white"
    property real fillOpacity: 0.14

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMaxValueChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const n = values ? values.length : 0
        if (n === 0 || width <= 0 || height <= 0)
            return

        const pad = 2
        const span = Math.max(1e-6, maxValue - minValue)
        const stepX = width / Math.max(1, capacity - 1)
        const startX = width - (n - 1) * stepX
        const y = v => {
            const t = (Math.min(maxValue, Math.max(minValue, v)) - minValue) / span
            return pad + (1 - t) * (height - 2 * pad)
        }

        ctx.beginPath()
        ctx.moveTo(startX, y(values[0]))
        for (let i = 1; i < n; ++i) {
            const x = startX + i * stepX
            if (steps)
                ctx.lineTo(x, y(values[i - 1]))
            ctx.lineTo(x, y(values[i]))
        }
        if (n === 1)
            ctx.lineTo(width, y(values[0]))

        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.strokeStyle = lineColor
        ctx.stroke()

        ctx.lineTo(width, height)
        ctx.lineTo(n === 1 ? width : startX, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, fillOpacity)
        ctx.fill()
    }
}
