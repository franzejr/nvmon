import QtQuick
import QtQuick.Controls

// A button drawn by hand, so it reads clearly on the dark panels whatever the
// Material style decides to do with flat and tonal buttons.
AbstractButton {
    id: button

    property color tone: theme.accent
    // Filled with the tone for the main action; a quiet outline otherwise.
    property bool primary: false

    readonly property color foreground: primary ? (theme.accentForeground === "black" && tone === theme.accent ? "black"
                                                   : "#0e0e10")
                                                : "#f2f2f5"

    implicitWidth: Math.max(96, label.implicitWidth + 32)
    implicitHeight: 38
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: Math.min(6, theme.radius)
        color: button.primary ? (button.down ? Qt.darker(button.tone, 1.2) : button.hovered ? Qt.lighter(button.tone, 1.1) : button.tone)
                              : (button.down ? "#2e2e35" : button.hovered ? "#26262c" : "#1f1f24")
        border.color: button.primary ? "transparent" : "#34343c"
    }

    contentItem: Label {
        id: label
        text: button.text
        color: button.foreground
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
