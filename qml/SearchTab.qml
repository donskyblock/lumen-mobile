import QtQuick

// Search tab: a field on top, results below (the same ranking and filters as the desktop search page).
Item {
    id: root
    property string query: ""
    property string arg: ""
    property string kind: "search"
    signal queryEdited(string text)

    SearchField {
        id: field
        anchors.top: parent.top; anchors.topMargin: 4
        anchors.left: parent.left; anchors.leftMargin: 16
        anchors.right: parent.right; anchors.rightMargin: 16
        height: 52
        placeholder: "Songs, albums, artists, playlists"
        text: root.query
        onTextChanged: if (text !== root.query) root.queryEdited(text)
    }
    Loader {
        id: results
        anchors.top: field.bottom; anchors.topMargin: 8
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        active: root.query.trim() !== ""
        sourceComponent: SearchPage { query: root.query }
    }
    Column {
        anchors.centerIn: results
        width: Math.min(320, parent.width - 48)
        spacing: 10
        visible: root.query.trim() === ""
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "search"; size: 44; color: Pal.outline }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "Search your library and the online catalog"
               font.pixelSize: Math.round(16 * Pal.fs); font.weight: Font.Medium; color: Pal.onSurface }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
               text: "Find songs, albums, artists and playlists. Online songs play through your extensions, or as a 30 second preview."
               font.pixelSize: Math.round(13 * Pal.fs); color: Pal.onSurfaceVariant }
    }
    function focusInput() { field.focusInput() }
}
