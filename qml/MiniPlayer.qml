import QtQuick

// Compact player docked above the navigation bar. Tap (or swipe up) opens the full player.
Rectangle {
    id: root
    signal opened()

    height: 64
    radius: 18 * Pal.rs
    color: Pal.surfaceHigh
    Behavior on color { ColorAnimation { duration: Pal.motion ? 500 : 0 } }
    clip: true

    Cover {
        id: art
        x: 8; anchors.verticalCenter: parent.verticalCenter
        width: 48; height: 48
        key: Player.cover
        url: Player.coverUrl
        radiusPct: 20
    }
    Column {
        anchors.left: art.right; anchors.leftMargin: 12
        anchors.right: controls.left; anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text { width: parent.width; text: Player.title; elide: Text.ElideRight
               font.pixelSize: Math.round(14 * Pal.fs); font.weight: Font.DemiBold; color: Pal.onSurface }
        Text { width: parent.width; text: Player.resolving ? "Finding the song\u2026" : Player.artist; elide: Text.ElideRight
               font.pixelSize: Math.round(12 * Pal.fs); color: Pal.onSurfaceVariant }
    }
    MouseArea {
        anchors.fill: parent
        anchors.rightMargin: controls.width + 4
        onClicked: root.opened()
        // swipe up opens too
        property real y0: 0
        onPressed: (m) => y0 = m.y
        onReleased: (m) => { if (y0 - m.y > 28) root.opened() }
    }
    Row {
        id: controls
        anchors.right: parent.right; anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        IconButton {
            width: 48; height: 48
            icon: Player.playing ? "pause" : "play"; iconSize: 28; tint: Pal.onSurface
            Accessible.name: Player.playing ? "Pause" : "Play"
            onClicked: Player.toggle()
        }
        IconButton {
            width: 48; height: 48
            icon: "skip_next"; iconSize: 26; tint: Pal.onSurface
            Accessible.name: "Next"
            onClicked: Player.next()
        }
    }
    // thin progress line along the bottom edge
    Rectangle {
        anchors.left: parent.left; anchors.bottom: parent.bottom
        height: 3
        width: Player.duration > 0 ? parent.width * Math.min(1, Player.position / Player.duration) : 0
        color: Pal.primary
    }
}
