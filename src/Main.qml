import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 860
    height: 640
    minimumWidth: 640
    minimumHeight: 540
    visible: true
    title: "Nvmon"
    color: "#0e0e10"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property bool helpVisible: false
    readonly property var gpu: backend.gpu
    readonly property bool hasGpu: backend.error === "" && gpu.name !== undefined
    readonly property bool keepaliveRunning: backend.keepalive === "active" || backend.keepalive === "activating"
    readonly property bool linkAtMax: gpu.linkGen !== undefined && gpu.linkGen >= gpu.linkGenMax

    readonly property color panel: "#18181b"
    readonly property color dim: "#8b8b93"
    readonly property color bright: "#f2f2f5"
    readonly property color warn: "#e0af68"
    readonly property color bad: "#f7768e"

    // Numbers take the language's separators and digits; reading the language
    // makes every caller re-render when it changes.
    function num(value, decimals) {
        translator.language
        return value === undefined ? "—" : Number(value).toLocaleString(Qt.locale(), 'f', decimals)
    }

    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = false }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; onActivated: Qt.quit() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; onActivated: backend.refresh() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; onActivated: backend.toggleKeepalive() }

    component Tile: Rectangle {
        property string label
        property string value
        property string detail
        property color valueColor: win.bright

        Layout.fillWidth: true
        Layout.preferredHeight: 104
        color: win.panel
        radius: theme.radius

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 2

            Label {
                text: label
                color: win.dim
                font.pixelSize: 13
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: value
                color: valueColor
                font.pixelSize: 28
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Label {
                text: detail
                color: win.dim
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
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
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Label {
                    text: win.hasGpu ? gpu.name : "Nvmon"
                    color: win.bright
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: win.hasGpu && gpu.driver !== undefined
                    text: qsTr("Driver %1").arg(gpu.driver || "")
                    color: win.dim
                    font.pixelSize: 13
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

            GridLayout {
                Layout.fillWidth: true
                columns: width < 720 ? 2 : 3
                columnSpacing: 12
                rowSpacing: 12

                Tile {
                    label: qsTr("PCIe link")
                    value: gpu.linkGen === undefined ? "—" : qsTr("Gen %1 · x%2").arg(gpu.linkGen).arg(gpu.linkWidth)
                    valueColor: gpu.linkGen === undefined ? win.dim : win.linkAtMax ? theme.accent : win.warn
                    detail: gpu.linkGen === undefined ? ""
                          : (win.linkAtMax ? qsTr("Full speed") : qsTr("Idle speed"))
                            + " · " + qsTr("max Gen %1 · x%2").arg(gpu.linkGenMax).arg(gpu.linkWidthMax)
                }
                Tile {
                    label: qsTr("Temperature")
                    value: win.num(gpu.temperature, 0) + " °C"
                    valueColor: gpu.temperature === undefined ? win.dim
                              : gpu.temperature >= 85 ? win.bad : gpu.temperature >= 75 ? win.warn : win.bright
                }
                Tile {
                    label: qsTr("Fan")
                    value: win.num(gpu.fan, 0) + " %"
                    detail: gpu.fan === 0 ? qsTr("Stopped while the card is cool") : ""
                }
                Tile {
                    label: qsTr("Power")
                    value: win.num(gpu.power, 1) + " W"
                    detail: gpu.powerLimit === undefined ? "" : qsTr("Limit %1 W").arg(win.num(gpu.powerLimit, 0))
                }
                Tile {
                    label: qsTr("Performance state")
                    value: gpu.pstate === undefined ? "—" : gpu.pstate
                    detail: gpu.pstate === undefined ? "" : gpu.pstate === "P8" ? qsTr("Idle") : qsTr("Awake")
                }
                Tile {
                    label: qsTr("Memory")
                    value: win.num(gpu.memoryUsed, 0) + " MiB"
                    detail: gpu.memoryTotal === undefined ? ""
                          : qsTr("of %1 MiB · GPU %2 % · encoder %3 %")
                                .arg(win.num(gpu.memoryTotal, 0)).arg(win.num(gpu.utilization, 0)).arg(win.num(gpu.encoder, 0))
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: win.panel
                    radius: theme.radius

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 10
                        spacing: 10

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: win.keepaliveRunning ? theme.accent : win.dim
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: qsTr("Keepalive"); color: win.dim; font.pixelSize: 13 }
                            Label {
                                text: backend.keepalive === "missing" ? qsTr("Not installed")
                                    : win.keepaliveRunning ? qsTr("Running") : qsTr("Stopped")
                                color: win.bright
                                font.pixelSize: 16
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Button {
                            visible: backend.keepalive !== "missing"
                            text: win.keepaliveRunning ? qsTr("Stop") : qsTr("Start")
                            flat: true
                            focusPolicy: Qt.NoFocus
                            Material.roundedScale: theme.radius
                            onClicked: backend.toggleKeepalive()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: win.panel
                    radius: theme.radius

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: backend.xidCount > 0 ? win.bad : theme.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: qsTr("Xid errors this boot"); color: win.dim; font.pixelSize: 13 }
                            Label {
                                text: backend.xidCount === 0 ? qsTr("None")
                                    : qsTr("%1 · last Xid %2 at %3").arg(win.num(backend.xidCount, 0))
                                          .arg(backend.lastXidCode).arg(backend.lastXidTime)
                                color: backend.xidCount > 0 ? win.bad : win.bright
                                font.pixelSize: 16
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: win.panel
                radius: theme.radius

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Label { text: qsTr("Processes on the GPU"); color: win.dim; font.pixelSize: 13 }

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
                        spacing: 4

                        delegate: RowLayout {
                            width: ListView.view.width
                            spacing: 12
                            Label {
                                text: modelData.pid
                                color: win.dim
                                font.pixelSize: 14
                                Layout.preferredWidth: 70
                            }
                            Label {
                                text: modelData.name
                                color: win.bright
                                font.pixelSize: 15
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Label {
                                text: win.num(modelData.memory, 0) + " MiB"
                                color: win.bright
                                font.pixelSize: 14
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
