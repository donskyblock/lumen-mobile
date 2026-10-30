#pragma once
#include <QObject>
#include <QString>
#include <QVector>

class Library;
class Player;
class Playlists;

// One line of the browse tree a car (Android Auto) or a voice assistant sees.
struct MediaRow {
    QString id;            // "cat:albums", "album:<key>", "song:<parent>\x1e<path>" ...
    QString title, subtitle;
    bool browsable = false;
    QString coverKey;      // Covers key of a local cover, or empty
    QString coverUrl;      // http(s) cover of an online song
};

// The browse tree, search and "play this id" logic behind the Android media service. No Android code in here:
// it only reads Library/Playlists and drives Player, so it can be tested on a desktop (LUMEN_BROWSE=cat:albums).
//   root -> Playlists, Albums, Artists, Songs          (kept to four: that is what a car screen shows as tabs)
//   playlist:<id> / album:<key> / artist:<name> / cat:songs -> songs, played as a queue from the chosen song
class MediaBrowse : public QObject {
    Q_OBJECT
public:
    MediaBrowse(Player* player, Library* library, Playlists* playlists, QString coverDir, QObject* parent = nullptr);

    // GUI thread only (they touch the models) ------------------------------------------------
    QVector<MediaRow> rows(const QString& parentId) const;
    QVector<MediaRow> searchRows(const QString& query) const;
    void play(const QString& id);

    // any thread ------------------------------------------------------------------------------
    // Renders the slice [page*pageSize, +pageSize) of `rows` to JSON, writing the cover JPEGs it needs into coverDir.
    QByteArray json(const QVector<MediaRow>& rows, int page, int pageSize) const;
    // JPEG file name (inside coverDir) for a cover key at `size` px; empty if there is no art. Exposed for the player state.
    QString coverFile(const QString& key, int size) const;

    static constexpr QChar kSep = QChar(0x1e);
    static QString songId(const QString& parent, const QString& path) { return QStringLiteral("song:") + parent + kSep + path; }

private:
    QStringList pathsOf(const QString& parentId) const;
    Player* m_player;
    Library* m_lib;
    Playlists* m_playlists;
    QString m_coverDir;
};
