#include "AndroidMedia.h"

#ifdef Q_OS_ANDROID
#include "MediaBrowse.h"
#include "Player.h"
#include <QCoreApplication>
#include <QDir>
#include <QJniEnvironment>
#include <QJniObject>
#include <QThread>

namespace {
AndroidMedia* g_media = nullptr;
enum Cmd { CmdPlay = 0, CmdPause = 1, CmdNext = 2, CmdPrev = 3, CmdSeek = 4, CmdToggleShuffle = 5, CmdSetRepeat = 6 };

// Android calls in from its own threads; the models belong to the GUI thread.
template <class F>
auto onGui(F&& f) -> decltype(f())
{
    using R = decltype(f());
    if (QThread::currentThread() == QCoreApplication::instance()->thread()) return f();
    R r{};
    QMetaObject::invokeMethod(QCoreApplication::instance(), [&] { r = f(); }, Qt::BlockingQueuedConnection);
    return r;
}

QString fromJava(JNIEnv* env, jstring s)
{
    if (!s) return {};
    const jchar* chars = env->GetStringChars(s, nullptr);
    const QString out = QString(reinterpret_cast<const QChar*>(chars), env->GetStringLength(s));
    env->ReleaseStringChars(s, chars);
    return out;
}

jstring toJava(JNIEnv* env, const QByteArray& utf8)
{
    const QString s = QString::fromUtf8(utf8);
    return env->NewString(reinterpret_cast<const jchar*>(s.utf16()), jsize(s.size()));
}

void jCommand(JNIEnv*, jclass, jint cmd, jlong arg)
{
    if (!g_media) return;
    QMetaObject::invokeMethod(g_media, [cmd, arg] { g_media->command(cmd, arg); }, Qt::QueuedConnection);
}

void jPlayId(JNIEnv* env, jclass, jstring id)
{
    if (!g_media) return;
    const QString s = fromJava(env, id);
    QMetaObject::invokeMethod(g_media, [s] { g_media->playId(s); }, Qt::QueuedConnection);
}

jstring jBrowse(JNIEnv* env, jclass, jstring parent, jint page, jint pageSize)
{
    if (!g_media) return toJava(env, "[]");
    const QString p = fromJava(env, parent);
    const QVector<MediaRow> rows = onGui([&] { return g_media->rows(p); });          // models: GUI thread
    return toJava(env, g_media->browse()->json(rows, page, pageSize));               // cover files: this thread
}

jstring jSearch(JNIEnv* env, jclass, jstring query)
{
    if (!g_media) return toJava(env, "[]");
    const QString q = fromJava(env, query);
    const QVector<MediaRow> rows = onGui([&] { return g_media->searchRows(q); });
    return toJava(env, g_media->browse()->json(rows, 0, 100));
}
}   // namespace

AndroidMedia::AndroidMedia(Player* player, Library* library, Playlists* playlists, QObject* parent) : QObject(parent), m_player(player)
{
    g_media = this;
    // the cover cache lives in the app's cache dir: android/.../CoverProvider.kt serves files from <cacheDir>/covers
    QJniObject ctx = QNativeInterface::QAndroidApplication::context();
    const QString cache = ctx.callObjectMethod("getCacheDir", "()Ljava/io/File;").callObjectMethod("getAbsolutePath", "()Ljava/lang/String;").toString();
    m_browse = new MediaBrowse(player, library, playlists, QDir(cache).filePath(QStringLiteral("covers")), this);

    m_debounce.setSingleShot(true);
    m_debounce.setInterval(60);                          // several signals fire for one track change; send one update
    connect(&m_debounce, &QTimer::timeout, this, &AndroidMedia::push);
    for (auto sig : {&Player::trackChanged, &Player::playingChanged, &Player::modeChanged, &Player::queueChanged, &Player::seeked})
        connect(player, sig, &m_debounce, qOverload<>(&QTimer::start));

    QJniEnvironment env;
    const JNINativeMethod methods[] = {
        {"nativeCommand", "(IJ)V", reinterpret_cast<void*>(jCommand)},
        {"nativePlayId", "(Ljava/lang/String;)V", reinterpret_cast<void*>(jPlayId)},
        {"nativeBrowse", "(Ljava/lang/String;II)Ljava/lang/String;", reinterpret_cast<void*>(jBrowse)},
        {"nativeSearch", "(Ljava/lang/String;)Ljava/lang/String;", reinterpret_cast<void*>(jSearch)},
    };
    if (!env.registerNativeMethods("app/lumen/LumenBridge", methods, 4)) qWarning("Lumen: could not register the media bridge");
    QJniObject::callStaticMethod<void>("app/lumen/LumenBridge", "onNativeReady", "()V");
    push();
}

QVector<MediaRow> AndroidMedia::rows(const QString& parentId) { return m_browse->rows(parentId); }
QVector<MediaRow> AndroidMedia::searchRows(const QString& query) { return m_browse->searchRows(query); }
void AndroidMedia::playId(const QString& id) { m_browse->play(id); }

void AndroidMedia::command(int cmd, qint64 arg)
{
    switch (cmd) {
    case CmdPlay:  if (!m_player->playing()) m_player->toggle(); break;
    case CmdPause: if (m_player->playing()) m_player->toggle(); break;
    case CmdNext:  m_player->next(); break;
    case CmdPrev:  m_player->previous(); break;
    case CmdSeek:  m_player->seek(arg); break;
    case CmdToggleShuffle: m_player->toggleShuffle(); break;
    case CmdSetRepeat:                                    // Player only cycles off -> all -> one
        for (int i = 0; i < 3 && m_player->repeat() != int(arg); ++i) m_player->cycleRepeat();
        break;
    default: break;
    }
}

void AndroidMedia::push()
{
    const bool has = m_player->hasTrack();
    const QString id = m_player->currentPath();
    // Online songs have an http cover; local ones a key we render to a JPEG the provider can serve.
    QString cover = m_player->coverUrl();
    if (!cover.startsWith(QLatin1String("http"))) cover = m_browse->coverFile(m_player->cover(), 512);
    QJniObject::callStaticMethod<void>(
        "app/lumen/LumenBridge", "pushState",
        "(ZLjava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;JJZZZLjava/lang/String;ZI)V",
        jboolean(has), QJniObject::fromString(id).object<jstring>(), QJniObject::fromString(m_player->title()).object<jstring>(),
        QJniObject::fromString(m_player->artist()).object<jstring>(), QJniObject::fromString(m_player->album()).object<jstring>(),
        jlong(m_player->duration()), jlong(m_player->position()), jboolean(m_player->playing()),
        jboolean(has), jboolean(has), QJniObject::fromString(cover).object<jstring>(), jboolean(m_player->shuffle()), jint(m_player->repeat()));
}
#endif
