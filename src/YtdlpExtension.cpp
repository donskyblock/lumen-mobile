#include "YtdlpExtension.h"
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QSet>
#include <algorithm>

namespace {

// Tried in order until one yields an address that really opens. An empty string means yt-dlp's own default.
const QStringList kClients = {QStringLiteral("youtube:player_client=web_music,web"), QString(),
                              QStringLiteral("youtube:player_client=tv,mweb"), QStringLiteral("youtube:player_client=ios")};
const QString kAudioFormat = QStringLiteral("bestaudio[protocol=https]/bestaudio[protocol=http]/bestaudio/best");
constexpr qint64 kResolveBudgetMs = 40000;
const QSet<QString> kBrowsers = {"firefox", "chrome", "chromium", "brave", "edge", "vivaldi", "opera", "safari"};

QStringList commonArgs()
{
    return {"--ignore-config", "--no-warnings", "--socket-timeout", "10", "--retries", "2", "--extractor-retries", "2"};
}

bool parseObject(const QByteArray& data, QJsonObject* out)
{
    QJsonParseError pe;
    const QJsonDocument d = QJsonDocument::fromJson(data, &pe);
    if (pe.error != QJsonParseError::NoError || !d.isObject()) return false;
    *out = d.object();
    return true;
}

QString firstNonEmpty(const QJsonObject& o, const char* a, const char* b = nullptr)
{
    QString s = o.value(a).toString();
    if (s.isEmpty() && b) s = o.value(b).toString();
    return s;
}

qint64 durationMsOf(const QJsonObject& e) { return qint64(e.value("duration").toDouble() * 1000.0); }

QString entryUrl(const QJsonObject& e) { return firstNonEmpty(e, "url", "webpage_url"); }

QJsonObject rowOf(const QJsonObject& e, const QString& url, const QString& album)
{
    const QJsonArray thumbs = e.value("thumbnails").toArray();
    QString title = e.value("title").toString();
    if (title.isEmpty()) title = url;
    return QJsonObject{{"id", url},
                       {"title", title},
                       {"artist", firstNonEmpty(e, "uploader", "channel")},
                       {"album", album},
                       {"durationMs", durationMsOf(e)},
                       {"cover", thumbs.isEmpty() ? QString() : thumbs.last().toObject().value("url").toString()}};
}

QSet<QString> wordsOf(const QString& s)
{
    QString t;
    t.reserve(s.size());
    for (const QChar c : s) t += c.isLetterOrNumber() ? c.toLower() : QChar(' ');
    const QStringList parts = t.split(' ', Qt::SkipEmptyParts);
    return QSet<QString>(parts.begin(), parts.end());
}

QVector<QJsonObject> keepRows(const QVector<QJsonObject>& rows, const QString& seedTitle)
{
    const QString seed = seedTitle.trimmed().toLower();
    QVector<QJsonObject> out;
    for (const QJsonObject& r : rows) {
        const qint64 d = qint64(r.value("durationMs").toDouble());
        if (d && !(d >= 60000 && d <= 600000)) continue;
        if (!seed.isEmpty() && r.value("title").toString().trimmed().toLower() == seed) continue;
        out << r;
    }
    return out;
}

QJsonArray toArray(const QVector<QJsonObject>& rows, int limit = -1)
{
    QJsonArray a;
    for (const QJsonObject& r : rows) {
        if (limit >= 0 && a.size() >= limit) break;
        a << r;
    }
    return a;
}

struct Picked { QString url; QJsonObject headers; QString codec; double abr = 0; };

Picked pickStream(const QJsonObject& j)
{
    Picked p;
    p.url = j.value("url").toString();
    p.headers = j.value("http_headers").toObject();
    p.codec = firstNonEmpty(j, "acodec", "ext");
    p.abr = j.value("abr").toDouble();
    if (!p.url.isEmpty()) return p;
    QVector<QJsonObject> fmts;
    for (const QJsonValue& v : j.value("formats").toArray()) {
        const QJsonObject f = v.toObject();
        const QJsonValue vc = f.value("vcodec");
        const bool audioOnly = vc.isNull() || vc.isUndefined() || vc.toString() == QLatin1String("none");
        if (!f.value("url").toString().isEmpty() && audioOnly) fmts << f;
    }
    // same preference as the audio format string: plain https first, then by bitrate (stable, best last)
    std::stable_sort(fmts.begin(), fmts.end(), [](const QJsonObject& a, const QJsonObject& b) {
        const auto key = [](const QJsonObject& f) {
            const QString proto = f.value("protocol").toString();
            return std::make_pair(proto == QLatin1String("https") || proto == QLatin1String("http"), f.value("abr").toDouble());
        };
        return key(a) < key(b);
    });
    if (!fmts.isEmpty()) {
        const QJsonObject f = fmts.last();
        p.url = f.value("url").toString();
        const QJsonObject fh = f.value("http_headers").toObject();
        if (!fh.isEmpty()) p.headers = fh;
        const QString c = firstNonEmpty(f, "acodec", "ext");
        if (!c.isEmpty()) p.codec = c;
        if (f.value("abr").toDouble() != 0) p.abr = f.value("abr").toDouble();
    }
    return p;
}

}   // namespace

// ---- helpers shared with tests -------------------------------------------------------------

QStringList YtdlpExtension::authArgs(const QJsonObject& params)
{
    const QJsonObject o = params.value("_options").toObject();
    QString f = o.value("cookiesFile").toString().trimmed();
    if (!f.isEmpty()) {
        if (f == QLatin1String("~")) f = QDir::homePath();
        else if (f.startsWith(QLatin1String("~/"))) f = QDir::homePath() + f.mid(1);
        if (QFileInfo(f).isFile()) return {QStringLiteral("--cookies"), f};
    }
    const QString b = o.value("cookiesBrowser").toString().trimmed().toLower();
    if (kBrowsers.contains(b)) return {QStringLiteral("--cookies-from-browser"), b};
    return {};
}

QString YtdlpExtension::friendly(const QString& msg, bool signedIn)
{
    const QString low = msg.toLower();
    if (low.contains("not a bot") || low.contains("sign in to confirm"))
        return signedIn ? tr("YouTube is refusing this request and says the cookies aren't accepted. Sign in again in your browser.")
                        : tr("YouTube wants you signed in (bot check). Sign in under Settings > Extensions > yt-dlp.");
    if (low.contains("age") && (low.contains("restricted") || low.contains("confirm your age")))
        return tr("This video is age-restricted. Sign in under Settings > Extensions > yt-dlp to play it.");
    if (low.contains("cookies") && (low.contains("could not") || low.contains("failed") || low.contains("unable")))
        return tr("Couldn't read your browser's login (is the browser name right, and the profile unlocked?).");
    if (low.contains("private video") || low.contains("video unavailable") || low.contains("not available"))
        return tr("This video isn't available (removed, private or blocked in your country).");
    return msg;
}

QString YtdlpExtension::videoId(const QString& url)
{
    int i = url.indexOf(QLatin1String("v="));
    if (i >= 0) return url.mid(i + 2).section('&', 0, 0);
    i = url.indexOf(QLatin1String("youtu.be/"));
    if (i >= 0) return url.mid(i + 9).section('?', 0, 0);
    return {};
}

// The upload of the seed song itself (not a cover, a slowed edit or a reaction).
QString YtdlpExtension::seedVideo(const QJsonArray& entries, const QJsonObject& p)
{
    const QSet<QString> want = wordsOf(p.value("title").toString());
    const QSet<QString> artist = wordsOf(p.value("artist").toString());
    static const QSet<QString> bad = {"cover", "slowed", "reverb", "reaction", "remix", "sped", "nightcore", "live", "karaoke", "instrumental"};
    for (const QJsonValue& v : entries) {
        const QJsonObject e = v.toObject();
        const QSet<QString> t = wordsOf(e.value("title").toString());
        if (want.isEmpty() || !t.contains(want)) continue;
        if (!artist.isEmpty()) {
            QSet<QString> pool = t;
            pool.unite(wordsOf(firstNonEmpty(e, "uploader", "channel")));
            if (!pool.contains(artist)) continue;
        }
        QSet<QString> stray = t;
        stray.intersect(bad);
        stray.subtract(want);
        if (!stray.isEmpty()) continue;
        return videoId(entryUrl(e));
    }
    return {};
}

// ---- the extension ----------------------------------------------------------------------------

YtdlpExtension::YtdlpExtension(QObject* parent) : NativeExtension(parent)
{
    m_runner = createYtdlpRunner(this);
    m_nam.setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
}

void YtdlpExtension::call(const QString& method, const QJsonObject& params, PluginReply cb, int, PluginPartial partial)
{
    if (method == QLatin1String("source.search")) search(params, std::move(cb), std::move(partial));
    else if (method == QLatin1String("source.resolve")) resolve(params, std::move(cb));
    else if (method == QLatin1String("source.recommend")) recommend(params, std::move(cb));
    else cb(false, {}, tr("Unknown method: %1").arg(method));
}

void YtdlpExtension::search(const QJsonObject& p, PluginReply cb, PluginPartial partial)
{
    const QString q = p.value("query").toString().trimmed();
    const int limit = qMax(4, p.contains("limit") ? p.value("limit").toInt(10) : 10);
    const int half = qMax(4, (limit + 1) / 2);

    struct State { QVector<QJsonObject> yt, sc; QStringList errors; int pending = 2; PluginReply cb; PluginPartial partial; int limit = 10; };
    auto st = std::make_shared<State>();
    st->cb = std::move(cb);
    st->partial = std::move(partial);
    st->limit = limit;
    QPointer<YtdlpExtension> self(this);

    auto finish = [st]() {
        if (st->yt.isEmpty() && st->sc.isEmpty() && !st->errors.isEmpty()) {
            st->cb(false, {}, YtdlpExtension::friendly(st->errors.first(), false));
            return;
        }
        QJsonArray out;                                  // interleave so neither site buries the other
        const int n = qMax(st->yt.size(), st->sc.size());
        for (int i = 0; i < n && out.size() < st->limit; ++i) {
            if (i < st->yt.size() && out.size() < st->limit) out << st->yt.at(i);
            if (i < st->sc.size() && out.size() < st->limit) out << st->sc.at(i);
        }
        st->cb(true, out, {});
    };

    // Two independent network searches: run them together and report each as it lands.
    const auto site = [&](const QString& prefix, const QString& label, bool isYoutube) {
        m_runner->run({"--flat-playlist", "-J", "--no-warnings", QStringLiteral("%1%2:%3").arg(prefix).arg(half).arg(q)}, 25000,
                      [self, st, finish, label, isYoutube](YtdlpResult r) {
                          if (!self) return;
                          QVector<QJsonObject> rows;
                          QString error;
                          QJsonObject data;
                          if (!r.ok) error = r.err;
                          else if (!parseObject(r.out, &data)) error = tr("yt-dlp returned something Lumen couldn't read.");
                          else
                              for (const QJsonValue& v : data.value("entries").toArray()) {
                                  const QJsonObject e = v.toObject();
                                  const QString url = entryUrl(e);
                                  if (!url.isEmpty()) rows << rowOf(e, url, label);
                              }
                          (isYoutube ? st->yt : st->sc) = rows;
                          if (!error.isEmpty()) st->errors << error;
                          else if (st->partial && !rows.isEmpty()) st->partial(toArray(rows));
                          if (--st->pending == 0) finish();
                      });
    };
    site(QStringLiteral("ytsearch"), QStringLiteral("YouTube"), true);
    site(QStringLiteral("scsearch"), QStringLiteral("SoundCloud"), false);
}

void YtdlpExtension::recommend(const QJsonObject& p, PluginReply cb)
{
    const QString seed = (p.value("artist").toString() + QLatin1Char(' ') + p.value("title").toString()).trimmed();
    if (seed.isEmpty()) { cb(true, QJsonArray(), {}); return; }
    const int limit = qMax(4, p.contains("limit") ? p.value("limit").toInt(20) : 20);
    auto rows = std::make_shared<QVector<QJsonObject>>();
    QPointer<YtdlpExtension> self(this);

    // Deliberately no keyword fallback: searching YouTube for the song's name only returns more songs with
    // that name. Lumen fills the rest from its own index of what you listen to.
    auto finalize = [rows, p, limit, cb]() { cb(true, toArray(keepRows(*rows, p.value("title").toString()), limit), {}); };

    auto stepAuth = [self, rows, p, finalize]() {
        if (!self) return;
        const QStringList auth = authArgs(p);
        if (auth.isEmpty()) { finalize(); return; }
        // signed in: YouTube's own recommendations for this account join the pool
        self->m_runner->run(commonArgs() + auth + QStringList{"--flat-playlist", "-J", "--playlist-end", "25", ":ytrec"}, 40000,
                            [self, rows, finalize](YtdlpResult r) {
                                if (!self) return;
                                QJsonObject feed;
                                if (r.ok && parseObject(r.out, &feed)) {
                                    int added = 0;
                                    for (const QJsonValue& v : feed.value("entries").toArray()) {
                                        const QJsonObject e = v.toObject();
                                        const QString url = entryUrl(e);
                                        const qint64 d = durationMsOf(e);
                                        if (url.isEmpty() || !(d >= 60000 && d <= 600000) || added >= 12) continue;
                                        rows->append(rowOf(e, url, QStringLiteral("Your YouTube recommendations")));
                                        ++added;
                                    }
                                }
                                finalize();
                            });
    };

    // First choice is YouTube's own "Mix" for that song: find the song's video, then read the RD<id> playlist.
    m_runner->run({"--flat-playlist", "-J", "--no-warnings", QStringLiteral("ytsearch5:") + seed}, 25000,
                  [self, rows, p, limit, stepAuth](YtdlpResult r) {
                      if (!self) return;
                      QJsonObject found;
                      QString vid;
                      if (r.ok && parseObject(r.out, &found)) vid = YtdlpExtension::seedVideo(found.value("entries").toArray(), p);
                      if (vid.isEmpty()) { stepAuth(); return; }
                      self->m_runner->run({"--flat-playlist", "-J", "--no-warnings", "--playlist-end", QString::number(limit + 5),
                                           QStringLiteral("https://www.youtube.com/watch?v=%1&list=RD%1").arg(vid)}, 40000,
                                          [self, rows, vid, stepAuth](YtdlpResult r2) {
                                              if (!self) return;
                                              QJsonObject mix;
                                              if (r2.ok && parseObject(r2.out, &mix))
                                                  for (const QJsonValue& v : mix.value("entries").toArray()) {
                                                      const QJsonObject e = v.toObject();
                                                      const QString url = entryUrl(e);
                                                      if (url.isEmpty() || YtdlpExtension::videoId(url) == vid) continue;
                                                      rows->append(rowOf(e, url, QStringLiteral("YouTube Mix")));
                                                  }
                                              stepAuth();
                                          });
                  });
}

// ---- resolve: try each YouTube client until one gives an address that really opens ----------

struct YtdlpExtension::ResolveJob {
    QString target;
    QStringList auth;
    QElapsedTimer clock;
    QStringList clients;
    int next = 0;
    QString last;
    PluginReply cb;
};

void YtdlpExtension::resolve(const QJsonObject& p, PluginReply cb)
{
    auto job = std::make_shared<ResolveJob>();
    job->target = p.value("id").toString();
    if (job->target.isEmpty()) { cb(false, {}, tr("No song was given.")); return; }
    job->auth = authArgs(p);
    job->clock.start();
    const bool youtube = job->target.contains(QLatin1String("youtube.com")) || job->target.contains(QLatin1String("youtu.be"));
    job->clients = youtube ? kClients : QStringList{QString()};
    job->last = tr("No playable audio stream was found.");
    job->cb = std::move(cb);
    resolveStep(job);
}

void YtdlpExtension::resolveStep(std::shared_ptr<ResolveJob> job)
{
    const qint64 remaining = kResolveBudgetMs - job->clock.elapsed();
    if (job->next >= job->clients.size() || remaining < 6000) {
        job->cb(false, {}, friendly(job->last, !job->auth.isEmpty()));
        return;
    }
    const QString client = job->clients.at(job->next++);
    QStringList args = commonArgs() + job->auth + QStringList{"-f", kAudioFormat, "-J", "--no-playlist"};
    if (!client.isEmpty()) args << "--extractor-args" << client;
    args << job->target;
    QPointer<YtdlpExtension> self(this);
    m_runner->run(args, int(qMin<qint64>(28000, remaining)), [self, job](YtdlpResult r) {
        if (!self) return;
        if (!r.ok) { job->last = r.err; self->resolveStep(job); return; }
        QJsonObject j;
        if (!parseObject(r.out, &j)) { job->last = tr("yt-dlp returned something Lumen couldn't read."); self->resolveStep(job); return; }
        const Picked pick = pickStream(j);
        if (pick.url.isEmpty()) { job->last = tr("No playable audio stream was found."); self->resolveStep(job); return; }
        self->opens(pick.url, pick.headers, [self, job, pick](bool good) {
            if (!self) return;
            if (!good) { job->last = tr("The stream was refused (HTTP error); trying another way."); self->resolveStep(job); return; }
            job->cb(true, QJsonObject{{"url", pick.url},
                                      {"headers", pick.headers},
                                      {"format", pick.codec.section('.', 0, 0)},
                                      {"bitrateKbps", int(pick.abr)},
                                      {"lossless", false}}, {});
        });
    });
}

// One tiny ranged request, made the way FFmpeg will make it. false only on a definite HTTP refusal.
void YtdlpExtension::opens(const QString& url, const QJsonObject& headers, std::function<void(bool)> done)
{
    if (url.contains(QLatin1String(".m3u8")) || url.startsWith(QLatin1String("file:"))) { done(true); return; }
    QNetworkRequest req{QUrl(url)};
    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) req.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
    req.setRawHeader("Range", "bytes=0-1023");
    req.setTransferTimeout(8000);
    QNetworkReply* r = m_nam.get(req);
    auto decided = std::make_shared<bool>(false);
    auto decide = [r, decided, done](bool ok) {
        if (*decided) return;
        *decided = true;
        r->disconnect();
        r->abort();
        r->deleteLater();
        done(ok);
    };
    const auto status = [r] { return r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); };
    connect(r, &QNetworkReply::readyRead, this, [r, decide, status] { const int s = status(); r->read(256); decide(s == 200 || s == 206); });
    connect(r, &QNetworkReply::finished, this, [decide, status] {
        const int s = status();
        decide(s > 0 ? (s == 200 || s == 206 || s == 416)      // 416: range past the end of a tiny file still means it exists
                     : true);                                    // timeouts / TLS quirks: not proof of a bad link, let FFmpeg decide
    });
}
