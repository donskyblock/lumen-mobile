import QtQuick

// Phone "Your Library": playlists, songs, albums and artists behind filter chips.
Item {
    id: root
    property string arg: ""
    property string kind: "library"
    property string sub: Ui.stringValue("libtab", "playlists")
    readonly property var subs: ["playlists", "songs", "albums", "artists"]
    readonly property var files: ({ songs: "SongsPage.qml", albums: "AlbumsPage.qml", artists: "ArtistsPage.qml" })

    onArgChanged: if (subs.indexOf(arg) >= 0) sub = arg
    Component.onCompleted: if (subs.indexOf(arg) >= 0) sub = arg
    function pick(s) { sub = s; Ui.set("libtab", s) }

    Row {
        id: chips
        anchors.top: parent.top
        anchors.left: parent.left; anchors.leftMargin: 16
        height: 52
        spacing: 8
        Repeater {
            model: [{ id: "playlists", label: "Playlists" }, { id: "songs", label: "Songs" }, { id: "albums", label: "Albums" }, { id: "artists", label: "Artists" }]
            delegate: FilterChip {
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                height: 40
                text: modelData.label
                checked: root.sub === modelData.id
                onClicked: root.pick(modelData.id)
            }
        }
    }

    // ---- playlists ----
    ListView {
        id: pl
        anchors.top: chips.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        visible: root.sub === "playlists"
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Playlists.list
        header: Item {
            width: pl.width; height: 68
            Rectangle { anchors.fill: parent; anchors.margins: 4; anchors.leftMargin: 8; anchors.rightMargin: 8; radius: 18 * Pal.rs; color: Pal.onSurface; opacity: np.pressed ? 0.08 : 0 }
            Rectangle {
                id: plus; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 52; height: 52; radius: 14 * Pal.rs; color: Pal.surfaceHigh
                Icon { anchors.centerIn: parent; name: "add"; size: 26; color: Pal.onSurface }
            }
            Text { anchors.left: plus.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "New playlist"
                   font.pixelSize: Math.round(15 * Pal.fs); font.weight: Font.Medium; color: Pal.onSurface }
            MouseArea { id: np; anchors.fill: parent; onClicked: Bus.prompt("New playlist", "My playlist", "newPlaylist", []) }
        }
        delegate: Item {
            id: pr
            width: pl.width; height: 68
            Rectangle { anchors.fill: parent; anchors.margins: 4; anchors.leftMargin: 8; anchors.rightMargin: 8; radius: 18 * Pal.rs; color: Pal.onSurface; opacity: pm.pressed ? 0.08 : 0 }
            Item {
                id: pc; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 52; height: 52
                Mosaic { anchors.fill: parent; visible: modelData.special !== "liked"; covers: modelData.covers; radiusPct: 18 }
                Rectangle { anchors.fill: parent; visible: modelData.special === "liked"; radius: width * 0.18 * Pal.rs
                            gradient: Gradient { GradientStop { position: 0; color: Pal.primaryContainer } GradientStop { position: 1; color: Pal.primary } }
                            Icon { anchors.centerIn: parent; name: "favorite"; size: 24; color: Pal.onPrimary } }
            }
            Column {
                anchors.left: pc.right; anchors.leftMargin: 14; anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                Text { width: parent.width; text: modelData.name; elide: Text.ElideRight; font.pixelSize: Math.round(15 * Pal.fs); font.weight: Font.Medium; color: Pal.onSurface }
                Text { width: parent.width; text: "Playlist \u00B7 " + modelData.count + (modelData.count === 1 ? " song" : " songs"); elide: Text.ElideRight
                       font.pixelSize: Math.round(13 * Pal.fs); color: Pal.onSurfaceVariant }
            }
            MouseArea {
                id: pm; anchors.fill: parent
                property bool held: false
                onPressed: held = false
                onPressAndHold: (m) => { held = true; var p = pr.mapToItem(null, m.x, m.y); Bus.menu("playlist", { id: modelData.id, special: modelData.special }, p.x, p.y) }
                onClicked: if (!held) Bus.go("playlist", modelData.id)
            }
        }
    }

    // ---- songs / albums / artists ----
    Loader {
        id: body
        anchors.top: chips.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        active: root.sub !== "playlists" && Library.trackCount > 0
        source: root.files[root.sub] || ""
        onLoaded: { item.width = Qt.binding(function () { return body.width }); item.height = Qt.binding(function () { return body.height }) }
    }
    EmptyState {
        anchors.top: chips.bottom; anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        visible: root.sub !== "playlists" && Library.trackCount === 0
        scanning: Library.scanning
        onOpenSettings: Bus.go("settings", "")
    }
}
