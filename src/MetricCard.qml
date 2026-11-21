import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// One reading: its name, the current value, a level bar against its limit,
// and the last few minutes behind it.
Rectangle {
    id: card

    property string label
    property string value: "—"
    property string detail
    property color valueColor: "#f2f2f5"
    property color chartColor: theme.accent
    // 0 to 1, or negative to hide the bar.
    property real level: -1
    property var series: []
    property real chartMin: 0
    property real chartMax: 100

    readonly property color dim: "#8b8b93"

    color: "#17171a"
    border.color: "#232328"
    radius: theme.radius
    implicitHeight: 170

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 4

        Label {
            text: card.label
            color: card.dim
            font.pixelSize: 13
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: card.value
                color: card.valueColor
                font.pixelSize: 30
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            visible: card.level >= 0
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            radius: Math.min(2, theme.radius)
            color: "#26262c"

            Rectangle {
                width: parent.width * Math.min(1, Math.max(0, card.level))
                height: parent.height
                radius: parent.radius
                color: card.chartColor
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        Label {
            text: card.detail
            color: card.dim
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Sparkline {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 40
            Layout.topMargin: 6
            values: card.series
            capacity: backend.historySize
            minValue: card.chartMin
            maxValue: card.chartMax
            lineColor: card.chartColor
        }
    }
}
