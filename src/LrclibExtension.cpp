#include "LrclibExtension.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QUrlQuery>

LrclibExtension::LrclibExtension(QObject* parent) : NativeExtension(parent)
{
    m_base = qEnvironmentVariable("LRCLIB_URL", QStringLiteral("https://lrclib.net"));
    while (m_base.endsWith('/')) m_base.chop(1);
    m_nam.setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
}

void LrclibExtension::fetch(const QList<QPair<QString, QString>>& query, std::function<void(bool, const QJsonArray&, const QString&)> done)
{
    QUrl url(m_base + QStringLiteral("/api/search"));
    QUrlQuery q;
    for (const auto& kv : query) q.addQueryItem(kv.first, kv.second);
    url.setQuery(q);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Lumen/0.2 (music player extension)");
    req.setTransferTimeout(10000);
    QNetworkReply* r = m_nam.get(req);
    connect(r, &QNetworkReply::finished, this, [r, done] {
        r->deleteLater();
        if (r->error() != QNetworkReply::NoError) { done(false, {}, r->errorString()); return; }
        QJsonParseError pe;
        const QJsonDocument d = QJsonDocument::fromJson(r->readAll(), &pe);
        if (pe.error != QJsonParseError::NoError || !d.isArray()) { done(false, {}, tr("lrclib.net returned something Lumen couldn't read.")); return; }
        done(true, d.array(), {});
    });
}

void LrclibExtension::call(const QString& method, const QJsonObject& p, PluginReply cb, int, PluginPartial)
{
    if (method != QLatin1String("lyrics.search")) { cb(false, {}, tr("unknown method: %1").arg(method)); return; }
    const QString title = p.value("title").toString();
    const QString artist = p.value("artist").toString();
    QPointer<LrclibExtension> self(this);

    auto finish = [cb](const QJsonArray& rows) {
        QJsonArray out;
        int n = 0;
        for (const QJsonValue& v : rows) {
            if (n++ >= 20) break;                                   // like the Python version: first 20, then drop instrumentals
            const QJsonObject d = v.toObject();
            if (d.value("instrumental").toBool()) continue;
            out << QJsonObject{{"title", d.value("trackName").toString()},
                               {"artist", d.value("artistName").toString()},
                               {"album", d.value("albumName").toString()},
                               {"durationMs", qint64(d.value("duration").toDouble() * 1000.0)},
                               {"synced", d.value("syncedLyrics").toString()},
                               {"plain", d.value("plainLyrics").toString()}};
        }
        cb(true, out, {});
    };
    auto loose = [self, title, cb, finish]() {                      // loose retry: title only, the host ranks the results
        if (!self) return;
        self->fetch({{"track_name", title}}, [cb, finish](bool ok, const QJsonArray& rows, const QString& err) {
            if (!ok) cb(false, {}, err); else finish(rows);
        });
    };
    if (artist.isEmpty()) { loose(); return; }
    fetch({{"track_name", title}, {"artist_name", artist}}, [self, cb, finish, loose](bool ok, const QJsonArray& rows, const QString& err) {
        if (!self) return;
        if (!ok) { cb(false, {}, err); return; }
        if (rows.isEmpty()) loose(); else finish(rows);
    });
}
