import QtQuick
import QtQuick.Window
import QtQuick.Controls
import "."

// Phone / tablet shell: bottom navigation, mini player, full-screen player, long-press menus.
// Shares every page, model and the audio engine with the desktop UI (Main.qml).
Window {
    id: win
    visible: true
    width: 412          // only used when forced onto a desktop (LUMEN_MOBILE=1); phones fill the screen
    height: 915
    title: Player.hasTrack ? Player.title + " \u2013 " + Player.artist : "Lumen"
    color: Pal.surface
    Behavior on color { ColorAnimation { duration: Pal.motion ? 500 : 0 } }

    // Android back button / gesture arrives as a close request: peel back one layer at a time.
    onClosing: (close) => {
        if (menu.visible) { menu.visible = false; close.accepted = false }
        else if (picker.visible || prompt.visible) { close.accepted = false }
        else if (playerOpen) { playerOpen = false; close.accepted = false }
        else if (hpos > 0) { goBack(); close.accepted = false }
        else if (tab !== "home") { selectTab("home"); close.accepted = false }
    }

    // ---- navigation: a route is {page, arg}, with back/forward history ----
    property string tab: Ui.stringValue("tab", "home")
    property var route: ({ page: tab, arg: "" })
    property var hist: [route]
    property int hpos: 0
    property string query: ""
    property string toast: ""
    property bool playerOpen: false
    readonly property bool searching: query.trim() !== ""
    property real topInset: 0          // status bar / display cutout, set from QWindow::safeAreaMargins() (see main.cpp)
    property real bottomInset: 0       // gesture / navigation bar
    readonly property bool hasLibrary: Library.trackCount > 0
    readonly property var tabPages: ["home", "search", "library", "settings"]
    readonly property var libraryPages: ["songs", "albums", "artists"]
    readonly property var needsLibrary: ["album", "artist"]
    readonly property var pageFiles: ({ home: "HomePage.qml", artists: "ArtistsPage.qml", albums: "AlbumsPage.qml", songs: "SongsPage.qml",
                                        lyrics: "LyricsPage.qml", settings: "SettingsPage.qml", album: "AlbumDetail.qml", library: "LibraryPage.qml", search: "SearchTab.qml",
                                        artist: "ArtistPage.qml", playlist: "PlaylistPage.qml", mix: "PlaylistPage.qml",
                                        oartist: "OnlineArtistPage.qml", oalbum: "OnlineAlbumPage.qml" })

    function goRoute(page, arg) {
        if (libraryPages.indexOf(page) >= 0) { arg = page; page = "library" }
        var r = { page: page, arg: (arg === undefined || arg === null) ? "" : String(arg) }
        playerOpen = false
        if (route.page === r.page && route.arg === r.arg) return
        hist = hist.slice(0, hpos + 1).concat([r])
        hpos = hist.length - 1
        route = r
    }
    function selectTab(t) {
        if (t === tab && route.page === t && hpos === 0) return
        tab = t
        hist = [{ page: t, arg: "" }]; hpos = 0; route = hist[0]
        playerOpen = false
    }
    function goBack() { if (hpos > 0) { hpos -= 1; route = hist[hpos] } }
    function goForward() { if (hpos < hist.length - 1) { hpos += 1; route = hist[hpos] } }
    onRouteChanged: {
        Bus.currentArg = route.arg
    }
    onTabChanged: Ui.set("tab", tab)
    // a query typed (or set by a test hook) always shows the results
    onQueryChanged: if (query.trim() !== "" && route.page !== "search") { tab = "search"; goRoute("search", "") }
    Timer { id: toastTimer; interval: 3200; onTriggered: win.toast = "" }
    function say(msg) { toast = msg; toastTimer.restart() }

    Connections {
        target: Bus
        function onNavigate(page, arg) { win.goRoute(page, arg) }
        function onNavigateBack() { win.goBack() }
        function onNavigateForward() { win.goForward() }
        function onToastRequested(msg) { win.say(msg) }
        function onMenuRequested(kind, ctx, x, y) { win.showMenu(kind, ctx, x, y) }
        function onPickRequested(paths) { picker.open(paths) }
        function onPlayOnlineRequested(kind, id) {
            if (kind === "album") { win.pendingAlbum = id; Catalog.loadAlbum(id) }
            else if (kind === "artist") { win.pendingArtist = id; Catalog.loadArtist(id) }
            else if (kind === "radio") Taste.startRadio("artist:" + id)
        }
        function onPromptRequested(title, initial, action, arg) { prompt.ask(title, initial, action, arg) }
    }

    // ---- online catalog: things that need loading before they can play ----
    property string pendingAlbum: ""
    property string pendingArtist: ""
    Connections {
        target: Catalog
        function onAlbumLoaded(id, page) { if (id === win.pendingAlbum) { win.pendingAlbum = ""; Player.playPaths(Catalog.albumPaths(id), 0) } }
        function onArtistLoaded(id, page) { if (id === win.pendingArtist) { win.pendingArtist = ""; Player.playPaths(Catalog.artistPaths(id), 0) } }
        function onLoadFailed(what, id, err) { if (id === win.pendingAlbum || id === win.pendingArtist) { win.pendingAlbum = ""; win.pendingArtist = ""; win.say(err) } }
        function onNavigateArtist(id) { win.goRoute("oartist", id) }
        function onMessage(text) { win.say(text) }
    }
    Connections {
        target: Taste
        function onRadioReady(title, paths) { Player.playPaths(paths, 0); win.say("Playing " + title) }
        function onRadioFailed(why) { win.say(why) }
        function onImportFinished(summary) { win.say(summary) }
        function onImportFailed(why) { win.say(why) }
    }

    // ---- context menus ----
    function pathsFor(kind, ctx) {
        if (kind === "track") return [ctx.path]
        if (kind === "album") return Library.albumPaths(ctx.key)
        if (kind === "artist") return Library.artistPaths(ctx.name)
        if (kind === "playlist") return Playlists.playablePaths(ctx.id)
        if (kind === "mix") return Library.mixPaths(ctx.id)
        return []
    }
    property string menuKind: ""
    function showMenu(kind, ctx, x, y) {
        menuKind = kind
        var it = []
        if (kind === "oartist") {
            var sv = Catalog.savedRevision >= 0 && Catalog.isSavedArtist(ctx.id)
            it.push({ id: "oplay", label: "Play", icon: "play" })
            it.push({ id: "radio", label: "Start radio", icon: "shuffle" })
            it.push({ id: "oopen", label: "Open artist", icon: "person" })
            it.push({ sep: true })
            it.push({ id: sv ? "removeArtist" : "importArtist", label: sv ? "Remove from library" : "Add to library", icon: sv ? "delete" : "add", danger: sv })
            menu.items = it; menu.ctx = ctx; menu.popup(x, y)
            return
        }
        if (kind === "oalbum") {
            it.push({ id: "oplay", label: "Play", icon: "play" })
            it.push({ id: "importAlbum", label: "Add to library", icon: "add" })
            if (ctx.artistId) { it.push({ sep: true }); it.push({ id: "oopen", label: "Go to artist", icon: "person" }) }
            menu.items = it; menu.ctx = ctx; menu.popup(x, y)
            return
        }
        if (kind !== "playlist" || (ctx.special !== undefined)) {
            // playable things
        }
        it.push({ id: "play", label: "Play", icon: "play" })
        if (kind !== "track") it.push({ id: "shuffle", label: "Shuffle", icon: "shuffle" })
        if (kind !== "playlist" && kind !== "mix") it.push({ id: "next", label: "Play next", icon: "skip_next" })
        it.push({ id: "queue", label: "Add to queue", icon: "queue_music" })
        if (kind === "track" || kind === "album" || kind === "artist") it.push({ id: "addpl", label: "Add to playlist\u2026", icon: "playlist_add" })
        if (kind === "track") {
            it.push({ id: "like", label: Playlists.isLiked(ctx.path) ? "Remove from Liked songs" : "Add to Liked songs", icon: Playlists.isLiked(ctx.path) ? "favorite" : "favorite_border" })
            if (Library.trackInfo(ctx.path).catalog) {
                var inLib = Catalog.isSaved(ctx.path)
                it.push({ id: inLib ? "removeTrack" : "importTrack", label: inLib ? "Remove from library" : "Add to library", icon: inLib ? "delete" : "add" })
            }
            it.push({ sep: true })
            it.push({ id: "goArtist", label: "Go to artist", icon: "person" })
            it.push({ id: "goAlbum", label: "Go to album", icon: "album" })
            if (ctx.playlistId !== undefined) {
                it.push({ sep: true })
                if (ctx.index > 0) it.push({ id: "up", label: "Move up", icon: "arrow_upward" })
                if (ctx.index < ctx.count - 1) it.push({ id: "down", label: "Move down", icon: "arrow_downward" })
                it.push({ id: "removeFrom", label: "Remove from this playlist", icon: "delete", danger: true })
            }
        }
        if (kind === "album" && ctx.artist) { it.push({ sep: true }); it.push({ id: "goArtistName", label: "Go to artist", icon: "person" }) }
        if (kind === "playlist" && ctx.special !== "liked") {
            it.push({ sep: true })
            it.push({ id: "rename", label: "Rename", icon: "edit" })
            it.push({ id: "delete", label: "Delete playlist", icon: "delete", danger: true })
        }
        if (kind === "mix") { it.push({ sep: true }); it.push({ id: "saveMix", label: "Save as playlist", icon: "playlist_add" }) }
        menu.items = it
        menu.ctx = ctx
        menu.popup(x, y)
    }
    function menuAction(id) {
        var ctx = menu.ctx, kind = win.menuKind
        var paths = pathsFor(kind, ctx)
        switch (id) {
        case "play": Player.playPaths(paths, 0); break
        case "shuffle": Player.playPathsShuffled(paths); break
        case "next": Player.playNext(paths); say("Playing next"); break
        case "queue": Player.addToQueue(paths); say("Added to queue"); break
        case "addpl": picker.open(paths); break
        case "like": Playlists.toggleLike(ctx.path); break
        case "goArtist": { var ti = Library.trackInfo(ctx.path); if (ti.catalog && ti.artistId) goRoute("oartist", ti.artistId); else if (ti.artistName) goRoute("artist", ti.artistName); break }
        case "goAlbum": { var tj = Library.trackInfo(ctx.path); if (tj.catalog && tj.albumId) goRoute("oalbum", tj.albumId); else if (tj.albumKey) goRoute("album", tj.albumKey); break }
        case "oplay": if (kind === "oartist") Bus.playOnline("artist", ctx.id); else Bus.playOnline("album", ctx.id); break
        case "radio": Taste.startRadio("artist:" + ctx.id); break
        case "oopen": goRoute(kind === "oartist" ? "oartist" : "oartist", kind === "oartist" ? ctx.id : ctx.artistId); break
        case "importArtist": Catalog.importArtist(ctx.id); say("Adding to your library\u2026"); break
        case "removeArtist": Catalog.removeArtist(ctx.id); break
        case "importAlbum": Catalog.importAlbum(ctx.id); break
        case "importTrack": Catalog.importTracks([ctx.path]); break
        case "removeTrack": Catalog.removeTracks([ctx.path]); say("Removed from your library"); break
        case "goArtistName": goRoute("artist", String(ctx.artist).split(/ feat\.? | ft\.? |;|\//i)[0].trim()); break
        case "up": Playlists.move(ctx.playlistId, ctx.index, ctx.index - 1); break
        case "down": Playlists.move(ctx.playlistId, ctx.index, ctx.index + 1); break
        case "removeFrom": Playlists.removeAt(ctx.playlistId, ctx.index); break
        case "rename": prompt.ask("Rename playlist", (Playlists.info(ctx.id).name || ""), "renamePlaylist", ctx.id); break
        case "delete": Playlists.remove(ctx.id); if (route.page === "playlist" && route.arg === ctx.id) goBack(); break
        case "saveMix": prompt.ask("Save playlist", Library.mixInfo(ctx.id).title || "Mix", "newPlaylist", paths); break
        }
    }
    function promptDone(action, text, arg) {
        if (action === "newPlaylist") {
            var id = Playlists.create(text, arg || [])
            say("Created \u201C" + (text.trim() || "New playlist") + "\u201D")
            if (!arg || arg.length === 0) goRoute("playlist", id)
        } else if (action === "renamePlaylist") Playlists.rename(arg, text)
        else if (action === "renameProfile") Profiles.set("name", text)
        else if (action === "newProfile") Profiles.create(text, arg)
    }


    Item {
        id: shell
        anchors.fill: parent
        focus: true
        Keys.onSpacePressed: Player.toggle()
        Keys.onBackPressed: (e) => { e.accepted = true; win.close() }

        // ---- top bar ----
        Item {
            id: topBar
            anchors.top: parent.top; anchors.topMargin: win.topInset
            anchors.left: parent.left; anchors.right: parent.right
            height: 60
            z: 20
            readonly property bool canBack: win.hpos > 0
            IconButton {
                id: backBtn
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 48; height: 48
                visible: topBar.canBack
                icon: "arrow_back"; tint: Pal.onSurface
                Accessible.name: "Back"
                onClicked: win.goBack()
            }
            Row {
                x: 20; anchors.verticalCenter: parent.verticalCenter
                visible: !topBar.canBack
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 12 * Pal.rs; color: Pal.primaryContainer
                    Icon { anchors.centerIn: parent; name: "music_note"; size: 22; color: Pal.onPrimaryContainer }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Lumen"; font.pixelSize: Math.round(22 * Pal.fs); font.weight: Font.Bold; color: Pal.onSurface }
            }
            Rectangle {
                id: avatar
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20 * Pal.rs
                color: Pal.primaryContainer
                border.width: profileMenu.visible ? 2 : 0
                border.color: Pal.primary
                Accessible.role: Accessible.Button
                Accessible.name: "Profile and appearance"
                Text { anchors.centerIn: parent; text: (Profiles.active.name || "?").charAt(0).toUpperCase()
                       font.pixelSize: Math.round(17 * Pal.fs); font.weight: Font.Bold; color: Pal.onPrimaryContainer }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: profileMenu.visible = !profileMenu.visible }
            }
        }

        // ---- page ----
        Item {
            id: content
            anchors.top: topBar.bottom
            anchors.bottom: dock.top
            anchors.left: parent.left; anchors.right: parent.right
            clip: true

            Loader {
                id: page
                anchors.fill: parent
                source: win.pageFiles[win.route.page] || "HomePage.qml"
                active: !(win.needsLibrary.indexOf(win.route.page) >= 0 && !win.hasLibrary)
                onLoaded: sync()
                function sync() {
                    if (!item) return
                    item.width = Qt.binding(function () { return page.width })
                    item.height = Qt.binding(function () { return page.height })
                    if ("arg" in item) item.arg = win.route.arg
                    if ("kind" in item) item.kind = win.route.page
                    if ("query" in item) item.query = Qt.binding(function () { return win.query })
                }
                Connections { target: win; function onRouteChanged() { page.sync() } }
                Connections { target: page.item; ignoreUnknownSignals: true; function onQueryEdited(text) { win.query = text } }
            }
            EmptyState {
                anchors.fill: parent
                visible: !win.hasLibrary && win.needsLibrary.indexOf(win.route.page) >= 0
                scanning: Library.scanning
                onOpenSettings: win.selectTab("settings")
            }
        }

        // ---- mini player + navigation bar ----
        Column {
            id: dock
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            MiniPlayer {
                id: mini
                x: 8; width: parent.width - 16
                visible: Player.hasTrack
                height: visible ? 64 : 0
                onOpened: win.playerOpen = true
            }
            Item { width: 1; height: Player.hasTrack ? 8 : 0 }
            BottomNav {
                width: parent.width
                bottomInset: win.bottomInset
                current: win.tab
                onSelected: (t) => win.selectTab(t)
            }
        }

        // ---- full-screen player ----
        NowPlayingSheet {
            id: sheet
            open: win.playerOpen
            topInset: win.topInset
            bottomInset: win.bottomInset
            onCloseRequested: win.playerOpen = false
            onLyricsRequested: { win.playerOpen = false; win.goRoute("lyrics", "") }
        }

        // ---- profile switcher ----
        // profile switcher
        MouseArea { anchors.fill: parent; visible: profileMenu.visible; onPressed: profileMenu.visible = false; z: 150 }
        Rectangle {
            id: profileMenu
            visible: false
            z: 160
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: win.topInset + 60
            anchors.rightMargin: 12
            width: Math.min(300, win.width - 24)
            height: pcol.height + 16
            radius: 22 * Pal.rs
            color: Pal.surfaceHighest
            border.width: 1; border.color: Pal.outlineVariant
            Column {
                id: pcol
                x: 8; y: 8; width: parent.width - 16
                Text { x: 12; height: 34; verticalAlignment: Text.AlignVCenter; text: "Profiles"; font.pixelSize: Math.round(12 * Pal.fs); font.weight: Font.DemiBold; color: Pal.onSurfaceVariant }
                Repeater {
                    model: Profiles.list
                    delegate: Item {
                        width: pcol.width; height: 46
                        readonly property bool on: modelData.id === Profiles.active.id
                        Rectangle { anchors.fill: parent; radius: 14 * Pal.rs; color: on ? Pal.secondaryContainer : (pmm.containsMouse ? Pal.surfaceHigh : "transparent") }
                        Rectangle {
                            id: dot; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; radius: 14 * Pal.rs
                            color: modelData.accent === "fixed" ? Qt.hsla(modelData.hue / 360, 0.5 + modelData.chroma / 250, 0.6, 1) : Pal.primary
                            Text { anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); font.pixelSize: Math.round(13 * Pal.fs); font.weight: Font.Bold; color: "#101010" }
                        }
                        Text { anchors.left: dot.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.name
                               font.pixelSize: Math.round(14 * Pal.fs); font.weight: on ? Font.DemiBold : Font.Normal; color: on ? Pal.onSecondaryContainer : Pal.onSurface }
                        Icon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: on; name: "check"; size: 18; color: Pal.onSecondaryContainer }
                        MouseArea { id: pmm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { Profiles.select(modelData.id); profileMenu.visible = false } }
                    }
                }
                Rectangle { x: 8; width: parent.width - 16; height: 1; color: Pal.outlineVariant }
                Item {
                    width: pcol.width; height: 46
                    Rectangle { anchors.fill: parent; radius: 14 * Pal.rs; color: Pal.onSurface; opacity: cm.containsMouse ? 0.08 : 0 }
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "palette"; size: 20; color: Pal.onSurfaceVariant }
                    Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: "Customize appearance"; font.pixelSize: Math.round(14 * Pal.fs); color: Pal.onSurface }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { profileMenu.visible = false; win.selectTab("settings") } }
                }
            }
        }


        ContextMenu { id: menu; anchors.fill: parent; z: 500; bottomInset: win.bottomInset; onChosen: (id) => win.menuAction(id) }
        PlaylistPicker { id: picker; anchors.fill: parent; z: 510; onNewPlaylist: (p) => prompt.ask("New playlist", "My playlist", "newPlaylist", p) }
        PromptDialog { id: prompt; anchors.fill: parent; z: 520; onAccepted: (a, t, arg) => win.promptDone(a, t, arg) }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: dock.top
            anchors.bottomMargin: 16
            width: Math.min(parent.width - 32, toastText.implicitWidth + 40)
            height: 48
            radius: height * Pal.pf
            color: Pal.primaryContainer
            visible: win.toast !== ""
            z: 600
            Text { id: toastText; anchors.centerIn: parent; width: parent.width - 32; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                   text: win.toast; font.pixelSize: Math.round(14 * Pal.fs); color: Pal.onPrimaryContainer }
        }
    }
}
