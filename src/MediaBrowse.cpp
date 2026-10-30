#include "MediaBrowse.h"
#include "Covers.h"
#include "Library.h"
#include "Player.h"
#include "Playlists.h"
#include <QAbstractItemModel>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>

namespace {

constexpr int kRowCap = 1000;          // a car screen never needs more, and every row costs a cover render
constexpr int kContextCap = 300;       // songs queued when one is picked from a huge list

QVector<QVariantMap> modelRows(QObject* o, int cap)
{
    QVector<QVariantMap> out;
    auto* m = qobject_cast<QAbstractItemModel*>(o);
    if (!m) return out;
    const QHash<int, QByteArray> roles = m->roleNames();
    const int n = qMin(m->rowCount(), cap);
    out.reserve(n);
    for (int r = 0; r < n; ++r) {
        QVariantMap row;
        const QModelIndex idx = m->index(r, 0);
        for (auto it = roles.cbegin(); it != roles.cend(); ++it) row.insert(QString::fromLatin1(it.value()), m->data(idx, it.key()));
        out << row;
    }
    return out;
}

QString countText(int n) { return n == 1 ? QStringLiteral("1 song") : QStringLiteral("%1 songs").arg(n); }

QString titleOf(const QVariantMap& t)
{
    const QString title = t.value("title").toString();
    return title.isEmpty() ? QFileInfo(t.value("path").toString()).completeBaseName() : title;
}

QString firstCover(const QVariant& covers)
{
    const QVariantList l = covers.toList();
    return l.isEmpty() ? QString() : l.first().toString();
}

}   // namespace

MediaBrowse::MediaBrowse(Player* player, Library* library, Playlists* playlists, QString coverDir, QObject* parent)
    : QObject(parent), m_player(player), m_lib(library), m_playlists(playlists), m_coverDir(std::move(coverDir))
{
    QDir().mkpath(m_coverDir);
}

QVector<MediaRow> MediaBrowse::rows(const QString& parentId) const
{
    QVector<MediaRow> out;
    const auto songRows = [&](const QVariantList& tracks, const QString& parent) {
        for (const QVariant& v : tracks) {
            const QVariantMap t = v.toMap();
            const QString path = t.value("path").toString();
            if (path.isEmpty()) continue;
            MediaRow r;
            r.id = songId(parent, path);
            r.title = titleOf(t);
            r.subtitle = t.value("artist").toString();
            r.coverKey = t.value("cover").toString();
            out << r;
            if (out.size() >= kRowCap) break;
        }
    };

    if (parentId == QLatin1String("root")) {
        out << MediaRow{"cat:playlists", tr("Playlists"), {}, true, {}, {}} << MediaRow{"cat:albums", tr("Albums"), {}, true, {}, {}}
            << MediaRow{"cat:artists", tr("Artists"), {}, true, {}, {}} << MediaRow{"cat:songs", tr("Songs"), {}, true, {}, {}};
    } else if (parentId == QLatin1String("cat:playlists")) {
        for (const QVariant& v : m_playlists->list()) {
            const QVariantMap p = v.toMap();
            MediaRow r;
            r.id = QStringLiteral("playlist:") + p.value("id").toString();
            r.title = p.value("name").toString();
            r.subtitle = countText(p.value("count").toInt());
            r.browsable = true;
            r.coverKey = firstCover(p.value("covers"));
            out << r;
        }
    } else if (parentId == QLatin1String("cat:albums")) {
        for (const QVariantMap& a : modelRows(m_lib->albums(), kRowCap)) {
            MediaRow r;
            r.id = QStringLiteral("album:") + a.value("key").toString();
            r.title = a.value("title").toString();
            r.subtitle = a.value("artist").toString();
            r.browsable = true;
            r.coverKey = a.value("cover").toString();
            out << r;
        }
    } else if (parentId == QLatin1String("cat:artists")) {
        for (const QVariantMap& a : modelRows(m_lib->artists(), kRowCap)) {
            MediaRow r;
            r.id = QStringLiteral("artist:") + a.value("name").toString();
            r.title = a.value("name").toString();
            r.subtitle = countText(a.value("count").toInt());
            r.browsable = true;
            r.coverKey = a.value("cover").toString();
            out << r;
        }
    } else if (parentId == QLatin1String("cat:songs")) {
        QVariantList tracks;
        for (const QVariantMap& t : modelRows(m_lib->songs(), kRowCap)) tracks << t;
        songRows(tracks, parentId);
    } else if (parentId.startsWith(QLatin1String("playlist:")) || parentId.startsWith(QLatin1String("artist:")) || parentId.startsWith(QLatin1String("album:"))) {
        if (parentId.startsWith(QLatin1String("album:"))) songRows(m_lib->albumTrackList(parentId.mid(6)), parentId);
        else songRows(m_lib->tracksInfo(pathsOf(parentId)), parentId);
    }
    return out;
}

QVector<MediaRow> MediaBrowse::searchRows(const QString& query) const
{
    QVector<MediaRow> out;
    const QVariantMap res = m_lib->searchAll(query, false);
    for (const QVariant& v : res.value("songs").toList()) {
        const QVariantMap t = v.toMap();
        const QString path = t.value("path").toString();
        if (path.isEmpty()) continue;
        MediaRow r;
        r.id = songId(QStringLiteral("search"), path);
        r.title = titleOf(t);
        r.subtitle = t.value("artist").toString();
        r.coverKey = t.value("cover").toString();
        out << r;
        if (out.size() >= 25) break;
    }
    int albums = 0;
    for (const QVariant& v : res.value("albums").toList()) {
        const QVariantMap a = v.toMap();
        if (a.value("key").toString().isEmpty() || albums++ >= 5) continue;
        MediaRow r;
        r.id = QStringLiteral("album:") + a.value("key").toString();
        r.title = a.value("title").toString();
        r.subtitle = a.value("artist").toString();
        r.browsable = true;
        r.coverKey = a.value("cover").toString();
        out << r;
    }
    return out;
}

QStringList MediaBrowse::pathsOf(const QString& parentId) const
{
    if (parentId.startsWith(QLatin1String("playlist:"))) return m_playlists->playablePaths(parentId.mid(9));
    if (parentId.startsWith(QLatin1String("album:"))) return m_lib->albumPaths(parentId.mid(6));
    if (parentId.startsWith(QLatin1String("artist:"))) return m_lib->artistPaths(parentId.mid(7));
    QStringList paths;
    if (parentId == QLatin1String("cat:songs"))
        for (const QVariantMap& t : modelRows(m_lib->songs(), 100000)) paths << t.value("path").toString();
    return paths;
}

void MediaBrowse::play(const QString& id)
{
    if (id.startsWith(QLatin1String("song:"))) {
        const int sep = id.indexOf(kSep);
        const QString parent = sep < 0 ? QString() : id.mid(5, sep - 5);
        const QString path = sep < 0 ? id.mid(5) : id.mid(sep + 1);
        QStringList paths = pathsOf(parent);
        int start = paths.indexOf(path);
        if (start < 0) { paths = {path}; start = 0; }                 // search results and anything unknown: just that song
        if (paths.size() > kContextCap) { paths = paths.mid(start, kContextCap); start = 0; }
        m_player->playPaths(paths, start);
    } else if (id.startsWith(QLatin1String("album:"))) {
        m_player->playAlbum(id.mid(6), 0, false);
    } else if (id.startsWith(QLatin1String("playlist:")) || id.startsWith(QLatin1String("artist:"))) {
        const QStringList paths = pathsOf(id);
        if (!paths.isEmpty()) m_player->playPaths(paths, 0);
    }
}

QString MediaBrowse::coverFile(const QString& key, int size) const
{
    if (key.isEmpty()) return {};
    const QString name = QString::fromLatin1(QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Md5).toHex()) + QLatin1Char('_') + QString::number(size) + QStringLiteral(".jpg");
    const QString file = QDir(m_coverDir).filePath(name);
    if (QFileInfo::exists(file)) return name;
    const QString path = Covers::pathFromKey(key);
    if (path.isEmpty()) return {};
    QImage img = Covers::render(path, size, 0);
    if (img.isNull()) return {};
    const QString tmp = file + QStringLiteral(".tmp");                 // never leave a half-written file for the other process to read
    if (!img.convertToFormat(QImage::Format_RGB888).save(tmp, "JPG", 85)) return {};
    QFile::remove(file);
    return QFile::rename(tmp, file) ? name : QString();
}

QByteArray MediaBrowse::json(const QVector<MediaRow>& rows, int page, int pageSize) const
{
    const int from = qMax(0, page) * qMax(1, pageSize);
    QJsonArray arr;
    for (int i = from; i < rows.size() && i < from + qMax(1, pageSize); ++i) {
        const MediaRow& r = rows.at(i);
        QString cover = r.coverUrl;
        if (cover.isEmpty()) cover = coverFile(r.coverKey, 256);
        arr << QJsonObject{{"id", r.id}, {"title", r.title}, {"subtitle", r.subtitle}, {"browsable", r.browsable}, {"cover", cover}};
    }
    return QJsonDocument(arr).toJson(QJsonDocument::Compact);
}
