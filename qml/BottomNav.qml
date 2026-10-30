import QtQuick

// Material 3 navigation bar: Home / Search / Library / Settings.
Rectangle {
    id: root
    property string current: "home"
    property real bottomInset: 0
    signal selected(string tab)

    implicitHeight: 72 + bottomInset
    color: Pal.surfaceLow
    Behavior on color { ColorAnimation { duration: Pal.motion ? 500 : 0 } }

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 72
        Repeater {
            model: [
                { id: "home", icon: "home", label: "Home" },
                { id: "search", icon: "search", label: "Search" },
                { id: "library", icon: "library_music", label: "Library" },
                { id: "settings", icon: "settings", label: "Settings" }
            ]
            delegate: Item {
                id: tab
                width: root.width / 4
                height: 72
                readonly property bool on: root.current === modelData.id
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.label
                Rectangle {
                    id: pill
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    width: tab.on ? 64 : 32; height: 32
                    radius: height * Pal.pf
                    color: Pal.secondaryContainer
                    opacity: tab.on ? 1 : 0
                    Behavior on width { NumberAnimation { duration: Pal.motion ? 180 : 0; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: Pal.motion ? 140 : 0 } }
                }
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12 + (32 - height) / 2
                    name: modelData.icon
                    size: 24
                    color: tab.on ? Pal.onSecondaryContainer : Pal.onSurfaceVariant
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 48
                    text: modelData.label
                    font.pixelSize: Math.round(12 * Pal.fs)
                    font.weight: tab.on ? Font.DemiBold : Font.Medium
                    color: tab.on ? Pal.onSurface : Pal.onSurfaceVariant
                }
                MouseArea { anchors.fill: parent; onClicked: root.selected(modelData.id) }
            }
        }
    }
}
