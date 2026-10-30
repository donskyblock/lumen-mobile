import QtQuick
import "Util.js" as U

// Full-screen player. Slides up from the mini player, drag the top area down to close.
// Portrait: cover on top, controls below. Landscape: cover left, controls right.
Item {
    id: root
    property bool open: false
    property real topInset: 0
    property real bottomInset: 0
    property bool showQueue: false
    signal closeRequested()
    signal lyricsRequested()

    readonly property bool landscape: width > height * 1.1
    property real lastDy: 0
    readonly property real dragY: drag.active ? Math.max(0, drag.translation.y) : 0

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    y: open ? dragY : height
    visible: y < height - 0.5
    z: 300
    Behavior on y { enabled: !drag.active; NumberAnimation { duration: Pal.motion ? 300 : 0; easing.type: Easing.OutCubic } }
    onOpenChanged: if (!open) showQueue = false

    Rectangle { anchors.fill: parent; color: Pal.surface }
    Backdrop {
        anchors.fill: parent
        key: Player.cover
        base: Pal.surface
        strength: 0.85
    }
    // swallow touches so nothing underneath reacts
    MouseArea { anchors.fill: parent; onPressed: (m) => m.accepted = true }

    // ---- header ----
    Item {
        id: header
        anchors.top: parent.top; anchors.topMargin: root.topInset
        anchors.left: parent.left; anchors.right: parent.right
        height: 64
        DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            onTranslationChanged: if (active) root.lastDy = translation.y
            onActiveChanged: { if (!active && root.lastDy > 140) root.closeRequested(); if (!active) root.lastDy = 0 }
        }
        IconButton {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48
            icon: "arrow_drop_down"; iconSize: 40; tint: Pal.onSurface
            Accessible.name: "Close player"
            onClicked: root.closeRequested()
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 140
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.showQueue ? "Up next" : "Now playing"
                   font.pixelSize: Math.round(12 * Pal.fs); font.weight: Font.Medium; color: Pal.onSurfaceVariant }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.showQueue ? "" : Player.album; elide: Text.ElideRight
                   visible: !root.showQueue; font.pixelSize: Math.round(14 * Pal.fs); font.weight: Font.DemiBold; color: Pal.onSurface }
        }
        IconButton {
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48
            icon: "more_vert"; tint: Pal.onSurface
            visible: Player.currentPath !== ""
            Accessible.name: "More"
            onClicked: Bus.menu("track", { path: Player.currentPath }, root.width / 2, root.height)
        }
    }

    // ---- cover ----
    Item {
        id: coverBox
        readonly property real side: root.landscape ? Math.min(root.height - header.height - root.topInset - root.bottomInset - 32, root.width * 0.42)
                                                    : Math.min(root.width - 48, (root.height - root.topInset - root.bottomInset) * 0.42)
        x: root.landscape ? 24 : (root.width - side) / 2
        y: root.topInset + header.height + (root.landscape ? 8 : 12)
           + (root.landscape ? 0 : Math.max(0, (root.height - root.topInset - root.bottomInset - header.height - side - 330) / 2.5))
        width: side; height: side
        scale: Player.playing ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: Pal.motion ? 300 : 0; easing.type: Easing.OutCubic } }
        Cover { anchors.fill: parent; key: Player.cover; url: Player.coverUrl; radiusPct: 6 }
    }

    // ---- title, seek, transport ----
    Item {
        id: info
        x: root.landscape ? coverBox.x + coverBox.width + 28 : 24
        y: root.landscape ? root.topInset + header.height + 8 : coverBox.y + coverBox.height + 20
        width: root.landscape ? root.width - x - 24 : root.width - 48
        height: root.landscape ? root.height - y - root.bottomInset - 16 : root.height - y - root.bottomInset - 16

        Row {
            id: titleRow
            width: parent.width
            Column {
                width: parent.width - (heart.visible ? heart.width : 0)
                spacing: 2
                Text { width: parent.width; text: Player.title; elide: Text.ElideRight
                       font.pixelSize: Math.round(24 * Pal.fs); font.weight: Font.Bold; color: Pal.onSurface }
                Text { width: parent.width; text: Player.artist; elide: Text.ElideRight
                       font.pixelSize: Math.round(16 * Pal.fs); color: Pal.onSurfaceVariant }
            }
            IconButton {
                id: heart
                readonly property bool liked: Playlists.revision >= 0 && Playlists.isLiked(Player.currentPath)
                width: 52; height: 52
                visible: Player.currentPath !== "" && Player.currentPath.indexOf("://") < 0
                icon: liked ? "favorite" : "favorite_border"; iconSize: 26; active: liked
                Accessible.name: liked ? "Remove from Liked songs" : "Add to Liked songs"
                onClicked: Playlists.toggleLike(Player.currentPath)
            }
        }
        Row {
            id: chips
            anchors.top: titleRow.bottom; anchors.topMargin: 8
            spacing: 6
            Chip { text: Player.lossless ? "Lossless" : "Lossy"; accent: Player.lossless }
            Chip { visible: Player.quality !== ""; text: Player.quality }
            Chip { visible: Player.preview; text: "30 s preview" }
        }

        Column {
            id: transport
            anchors.top: chips.bottom; anchors.topMargin: root.landscape ? 12 : 18
            width: parent.width
            spacing: root.landscape ? 4 : 10
            Item {
                width: parent.width; height: 40
                Scrubber {
                    id: seek
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    height: 28
                    value: Player.duration > 0 ? Player.position / Player.duration : 0
                    waving: Player.playing
                    onSeekRequested: (f) => Player.seek(f * Player.duration)
                }
                Text { anchors.left: parent.left; anchors.top: seek.bottom; text: U.fmt(Player.position)
                       font.pixelSize: Math.round(12 * Pal.fs); color: Pal.onSurfaceVariant }
                Text { anchors.right: parent.right; anchors.top: seek.bottom; text: U.fmt(Player.duration)
                       font.pixelSize: Math.round(12 * Pal.fs); color: Pal.onSurfaceVariant }
            }
            Item {
                width: parent.width; height: 84
                IconButton { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 52; height: 52
                             icon: "shuffle"; iconSize: 26; active: Player.shuffle; Accessible.name: "Shuffle"; onClicked: Player.toggleShuffle() }
                IconButton { x: (parent.width - 52) / 2 - 84; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56
                             icon: "skip_previous"; iconSize: 36; tint: Pal.onSurface; Accessible.name: "Previous"; onClicked: Player.previous() }
                Item {
                    x: (parent.width - 76) / 2; anchors.verticalCenter: parent.verticalCenter
                    width: 76; height: 76
                    Accessible.role: Accessible.Button
                    Accessible.name: Player.playing ? "Pause" : "Play"
                    Rectangle {
                        id: playShape
                        anchors.fill: parent
                        radius: (Player.playing ? 24 : 38) * Pal.rs
                        color: Pal.primary
                        Behavior on radius { NumberAnimation { duration: Pal.motion ? 260 : 0; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                    }
                    Rectangle { anchors.fill: parent; radius: playShape.radius; color: Pal.onPrimary; opacity: playTap.pressed ? 0.16 : 0 }
                    Icon { anchors.centerIn: parent; name: Player.playing ? "pause" : "play"; size: 40; color: Pal.onPrimary }
                    MouseArea { id: playTap; anchors.fill: parent; onClicked: Player.toggle() }
                }
                IconButton { x: (parent.width - 52) / 2 + 84 + 0; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56
                             icon: "skip_next"; iconSize: 36; tint: Pal.onSurface; Accessible.name: "Next"; onClicked: Player.next() }
                IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 52; height: 52
                             icon: Player.repeat === 2 ? "repeat_one" : "repeat"; iconSize: 26; active: Player.repeat > 0
                             Accessible.name: "Repeat"; onClicked: Player.cycleRepeat() }
            }
            Item {
                width: parent.width; height: 52
                IconButton { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48
                             icon: "lyrics"; tint: Pal.onSurface; Accessible.name: "Lyrics"; onClicked: root.lyricsRequested() }
                IconButton { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48
                             icon: "autoplay"; active: Player.autoplay; opacity: Player.autoplayBusy ? 0.55 : 1
                             Accessible.name: "Autoplay: keep playing similar songs"; onClicked: Player.setAutoplay(!Player.autoplay) }
                IconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48
                             icon: "queue_music"; active: root.showQueue; tint: Pal.onSurface; Accessible.name: "Up next"
                             onClicked: root.showQueue = !root.showQueue }
            }
        }
    }

    // ---- up next ----
    Rectangle {
        id: queuePanel
        x: 0; width: parent.width
        y: root.showQueue ? root.topInset + header.height : root.height
        height: root.height - root.topInset - header.height
        color: Pal.surface
        visible: y < root.height - 0.5
        Behavior on y { NumberAnimation { duration: Pal.motion ? 260 : 0; easing.type: Easing.OutCubic } }
        ListView {
            id: queue
            anchors.fill: parent
            anchors.bottomMargin: root.bottomInset
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Player.upNext
            header: Item {
                width: queue.width; height: 56
                Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "Next in queue"; font.pixelSize: Math.round(13 * Pal.fs)
                       font.weight: Font.DemiBold; color: Pal.onSurfaceVariant }
            }
            delegate: Item {
                width: queue.width; height: 64
                Cover { id: qc; x: 24; anchors.verticalCenter: parent.verticalCenter; width: 48; height: 48; key: modelData.cover; radiusPct: 20 }
                Column {
                    anchors.left: qc.right; anchors.leftMargin: 14
                    anchors.right: parent.right; anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: modelData.title; elide: Text.ElideRight
                           font.pixelSize: Math.round(15 * Pal.fs); font.weight: Font.Medium; color: Pal.onSurface }
                    Text { width: parent.width; text: modelData.artist; elide: Text.ElideRight
                           font.pixelSize: Math.round(13 * Pal.fs); color: Pal.onSurfaceVariant }
                }
                Rectangle { anchors.fill: parent; color: Pal.onSurface; opacity: qt.pressed ? 0.08 : 0 }
                MouseArea { id: qt; anchors.fill: parent; onClicked: { Player.jumpTo(index); root.showQueue = false } }
            }
            Text {
                anchors.centerIn: parent
                visible: queue.count === 0
                text: "Nothing queued after this song"
                font.pixelSize: Math.round(15 * Pal.fs); color: Pal.onSurfaceVariant
            }
        }
    }
}
