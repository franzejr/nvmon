import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 920
    height: 760
    minimumWidth: 680
    minimumHeight: 640
    visible: true
    title: "Nvmon"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    property bool confirmStop: false
    property double now: Date.now()

    readonly property var gpu: backend.gpu
    readonly property var history: backend.history
    readonly property bool hasGpu: backend.error === "" && gpu.name !== undefined
    readonly property bool keepaliveRunning: backend.keepalive === "active" || backend.keepalive === "activating"
    readonly property bool linkAtMax: gpu.linkGen !== undefined && gpu.linkGen >= gpu.linkGenMax
    readonly property int historyMinutes: Math.round(backend.historySize * backend.intervalMs / 60000)

    // How many times the link changed speed in the recorded history.
    readonly property int linkChanges: {
        const series = history.linkGen || []
        let changes = 0
        for (let i = 1; i < series.length; ++i)
            if (series[i] !== series[i - 1])
                ++changes
        return changes
    }

    readonly property color panel: "#17171a"
    readonly property color edge: "#232328"
    readonly property color dim: "#8b8b93"
    readonly property color bright: "#f2f2f5"
    readonly property color warn: "#e0af68"
    readonly property color bad: "#f7768e"

    Timer { interval: 15000; running: true; repeat: true; onTriggered: win.now = Date.now() }

    // Numbers take the language's separators and digits; reading the language
    // makes every caller re-render when it changes.
    function num(value, decimals) {
        translator.language
        return value === undefined ? "—" : Number(value).toLocaleString(Qt.locale(), 'f', decimals)
    }

    function duration(sinceMs) {
        translator.language
        const minutes = Math.max(0, Math.floor((win.now - sinceMs) / 60000))
        if (minutes < 1)
            return qsTr("less than a minute")
        const days = Math.floor(minutes / 1440)
        const hours = Math.floor(minutes % 1440 / 60)
        if (days > 0)
            return qsTr("%1 d %2 h").arg(days).arg(hours)
        if (hours > 0)
            return qsTr("%1 h %2 min").arg(hours).arg(minutes % 60)
        return qsTr("%1 min").arg(minutes)
    }

    function toggleKeepalive() {
        if (backend.keepalive === "missing")
            return
        if (win.keepaliveRunning)
            win.confirmStop = true
        else
            backend.startKeepalive()
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: { win.helpVisible = false; win.confirmStop = false }
    }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; onActivated: backend.refresh() }
    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        enabled: !win.confirmStop
        onActivated: win.toggleKeepalive()
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.ApplicationShortcut
        enabled: win.confirmStop
        onActivated: { backend.stopKeepalive(); win.confirmStop = false }
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header: the card, and the one-line answer to "is it holding up?"
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        text: win.hasGpu ? gpu.name : "Nvmon"
                        color: win.bright
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: gpu.driver !== undefined
                        text: qsTr("Driver %1").arg(gpu.driver || "")
                        color: win.dim
                        font.pixelSize: 13
                    }
                }

                Rectangle {
                    id: pill
                    readonly property bool failing: backend.error !== "" || backend.xidCount > 0
                    readonly property color tone: failing ? win.bad : theme.accent
                    implicitWidth: pillRow.implicitWidth + 28
                    implicitHeight: 36
                    radius: theme.radius > 0 ? height / 2 : 0
                    color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
                    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.5)

                    RowLayout {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { width: 8; height: 8; radius: 4; color: pill.tone }
                        Label {
                            color: pill.tone
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            text: backend.error !== "" ? qsTr("GPU lost")
                                : backend.xidCount > 0 ? qsTr("Xid %1 at %2").arg(backend.lastXidCode).arg(backend.lastXidTime.slice(11, 16))
                                : backend.stableSince > 0 ? qsTr("Stable for %1").arg(win.duration(backend.stableSince))
                                : qsTr("Stable")
                        }
                    }
                }
            }

            // A missing tool or a lost GPU is said out loud, not hidden.
            Rectangle {
                visible: backend.error !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: errorText.implicitHeight + 28
                color: "#2a1519"
                border.color: win.bad
                radius: theme.radius

                Label {
                    id: errorText
                    anchors.fill: parent
                    anchors.margins: 14
                    text: backend.error
                    color: win.bad
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // The PCIe link, which is what this whole app is about.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 168
                color: win.panel
                border.color: win.edge
                radius: theme.radius

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 24

                    ColumnLayout {
                        Layout.preferredWidth: 250
                        Layout.fillHeight: true
                        spacing: 4

                        Label { text: qsTr("PCIe link"); color: win.dim; font.pixelSize: 13 }
                        Label {
                            text: gpu.linkGen === undefined ? "—" : qsTr("Gen %1 · x%2").arg(gpu.linkGen).arg(gpu.linkWidth)
                            color: gpu.linkGen === undefined ? win.dim : win.linkAtMax ? theme.accent : win.warn
                            font.pixelSize: 40
                            font.weight: Font.Bold
                        }
                        Label {
                            visible: gpu.linkGen !== undefined
                            text: (win.linkAtMax ? qsTr("Full speed") : qsTr("Idle speed"))
                                  + " · " + qsTr("max Gen %1 · x%2").arg(gpu.linkGenMax).arg(gpu.linkWidthMax)
                            color: win.dim
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            spacing: 8
                            Rectangle {
                                implicitWidth: pstateLabel.implicitWidth + 16
                                implicitHeight: 24
                                radius: Math.min(4, theme.radius)
                                color: "#232328"
                                Label {
                                    id: pstateLabel
                                    anchors.centerIn: parent
                                    text: gpu.pstate === undefined ? "—" : gpu.pstate
                                    color: win.bright
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                            Label {
                                text: gpu.pstate === undefined ? ""
                                    : (gpu.pstate === "P8" ? qsTr("Idle") : qsTr("Awake"))
                                      + " · " + qsTr("GPU %1 % · encoder %2 %").arg(win.num(gpu.utilization, 0)).arg(win.num(gpu.encoder, 0))
                                color: win.dim
                                font.pixelSize: 13
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: qsTr("Last %1 min").arg(win.historyMinutes)
                                color: win.dim
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (history.linkGen || []).length < 2 ? ""
                                    : win.linkChanges === 0 ? qsTr("No speed changes")
                                    : qsTr("%n speed changes", "", win.linkChanges)
                                color: win.linkChanges === 0 ? win.dim : win.warn
                                font.pixelSize: 12
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            // Gen labels beside the chart, top to bottom.
                            ColumnLayout {
                                Layout.fillHeight: true
                                spacing: 0
                                Repeater {
                                    model: Math.max(1, gpu.linkGenMax || 3)
                                    delegate: Label {
                                        readonly property int gen: Math.max(1, gpu.linkGenMax || 3) - index
                                        text: "Gen " + gen
                                        color: win.dim
                                        font.pixelSize: 11
                                        Layout.fillHeight: true
                                        verticalAlignment: index === 0 ? Text.AlignTop
                                                         : gen === 1 ? Text.AlignBottom : Text.AlignVCenter
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Repeater {
                                    model: Math.max(1, gpu.linkGenMax || 3)
                                    delegate: Rectangle {
                                        readonly property int levels: Math.max(1, (gpu.linkGenMax || 3) - 1)
                                        width: parent.width
                                        height: 1
                                        color: "#232328"
                                        y: 2 + index / levels * (parent.height - 4)
                                    }
                                }

                                Sparkline {
                                    anchors.fill: parent
                                    values: history.linkGen || []
                                    capacity: backend.historySize
                                    minValue: 1
                                    maxValue: Math.max(2, gpu.linkGenMax || 3)
                                    steps: true
                                    lineColor: win.linkAtMax ? theme.accent : win.warn
                                    fillOpacity: 0.05
                                }
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: columns === 4 ? 170 : 340
                columns: width < 820 ? 2 : 4
                columnSpacing: 14
                rowSpacing: 14

                MetricCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: qsTr("Temperature")
                    value: win.num(gpu.temperature, 0) + " °C"
                    readonly property color tone: gpu.temperature === undefined ? win.dim
                        : gpu.temperature >= 85 ? win.bad : gpu.temperature >= 75 ? win.warn : win.bright
                    valueColor: tone
                    chartColor: gpu.temperature >= 75 ? tone : theme.accent
                    level: gpu.temperature === undefined ? -1 : gpu.temperature / 100
                    detail: qsTr("Peak %1 °C").arg(win.num(Math.max(...(history.temperature || [0])), 0))
                    series: history.temperature || []
                    chartMin: 20
                    chartMax: 100
                }
                MetricCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: qsTr("Fan")
                    value: win.num(gpu.fan, 0) + " %"
                    level: gpu.fan === undefined ? -1 : gpu.fan / 100
                    detail: gpu.fan === 0 ? qsTr("Stopped while the card is cool") : qsTr("Spinning")
                    series: history.fan || []
                }
                MetricCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: qsTr("Power")
                    value: win.num(gpu.power, 1) + " W"
                    level: gpu.power === undefined || !gpu.powerLimit ? -1 : gpu.power / gpu.powerLimit
                    detail: gpu.powerLimit === undefined ? "" : qsTr("Limit %1 W").arg(win.num(gpu.powerLimit, 0))
                    series: history.power || []
                    chartMax: gpu.powerLimit || 200
                }
                MetricCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    label: qsTr("Memory")
                    value: win.num(gpu.memoryUsed, 0) + " MiB"
                    level: gpu.memoryUsed === undefined || !gpu.memoryTotal ? -1 : gpu.memoryUsed / gpu.memoryTotal
                    detail: gpu.memoryTotal === undefined ? "" : qsTr("of %1 MiB").arg(win.num(gpu.memoryTotal, 0))
                    series: history.memoryUsed || []
                    chartMax: gpu.memoryTotal || 1
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                spacing: 14

                // The keepalive holds the card out of idle while the Xid 79
                // test runs.
                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    color: win.panel
                    border.color: win.edge
                    radius: theme.radius

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6

                        Label { text: qsTr("Keepalive"); color: win.dim; font.pixelSize: 13 }
                        RowLayout {
                            spacing: 10
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: win.keepaliveRunning ? theme.accent : win.dim
                                SequentialAnimation on opacity {
                                    running: win.keepaliveRunning
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }
                            Label {
                                text: backend.keepalive === "missing" ? qsTr("Not installed")
                                    : win.keepaliveRunning ? qsTr("Running") : qsTr("Stopped")
                                color: win.bright
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                        }
                        Label {
                            text: win.keepaliveRunning && backend.keepaliveSince > 0
                                  ? qsTr("For %1").arg(win.duration(backend.keepaliveSince))
                                  : backend.keepalive === "missing" ? qsTr("rtx-keepalive.service was not found")
                                  : qsTr("The card can go idle and drop to Gen 1")
                            color: win.dim
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Item { Layout.fillHeight: true }
                        ActionButton {
                            visible: backend.keepalive !== "missing"
                            text: win.keepaliveRunning ? qsTr("Stop") : qsTr("Start")
                            primary: !win.keepaliveRunning
                            Layout.fillWidth: true
                            onClicked: win.toggleKeepalive()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: win.panel
                    border.color: win.edge
                    radius: theme.radius

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Processes on the GPU"); color: win.dim; font.pixelSize: 13; Layout.fillWidth: true }
                            Label { text: qsTr("Memory"); color: win.dim; font.pixelSize: 12 }
                        }

                        Label {
                            visible: backend.apps.length === 0
                            text: qsTr("Nothing is using the GPU")
                            color: win.dim
                            font.pixelSize: 15
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: backend.apps
                            spacing: 2

                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 32
                                radius: Math.min(4, theme.radius)
                                color: index % 2 === 0 ? "#1c1c20" : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 12
                                    Label {
                                        text: modelData.name
                                        color: win.bright
                                        font.pixelSize: 14
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: modelData.pid
                                        color: win.dim
                                        font.pixelSize: 12
                                    }
                                    Label {
                                        text: win.num(modelData.memory, 0) + " MiB"
                                        color: win.bright
                                        font.pixelSize: 14
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: 80
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Label {
                text: qsTr("Press ? for shortcuts")
                color: win.dim
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Stopping the keepalive ends the idle test, so it asks first.
        Rectangle {
            visible: win.confirmStop
            anchors.fill: parent
            color: "#d90e0e10"

            MouseArea { anchors.fill: parent; onClicked: win.confirmStop = false }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 40)
                height: confirmColumn.implicitHeight + 44
                color: win.panel
                border.color: win.warn
                radius: theme.radius

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: confirmColumn
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    Label {
                        text: qsTr("Stop the keepalive?")
                        color: win.bright
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    Label {
                        text: qsTr("The card will go idle and drop to Gen 1 again, which is when it has been falling off the bus.")
                        color: win.dim
                        font.pixelSize: 14
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        ActionButton {
                            text: qsTr("Cancel")
                            onClicked: win.confirmStop = false
                        }
                        ActionButton {
                            text: qsTr("Stop")
                            primary: true
                            tone: win.warn
                            onClicked: { backend.stopKeepalive(); win.confirmStop = false }
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: win.helpVisible
            anchors.fill: parent
            color: "#d90e0e10"

            MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 40)
                height: helpColumn.implicitHeight + 40
                color: win.panel
                border.color: theme.accent
                radius: theme.radius

                ColumnLayout {
                    id: helpColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10

                    Label { text: qsTr("Shortcuts"); color: win.bright; font.pixelSize: 18; font.weight: Font.DemiBold }

                    Repeater {
                        model: [
                            { key: "Space", what: qsTr("Start or stop the keepalive") },
                            { key: "R", what: qsTr("Refresh now") },
                            { key: "?", what: qsTr("Show or hide this help") },
                            { key: "Q", what: qsTr("Quit") }
                        ]
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Label {
                                text: modelData.key
                                color: theme.accent
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                Layout.preferredWidth: 70
                            }
                            Label {
                                text: modelData.what
                                color: win.bright
                                font.pixelSize: 15
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
