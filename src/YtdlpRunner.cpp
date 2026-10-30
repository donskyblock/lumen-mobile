#include "YtdlpRunner.h"
#include <memory>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QCoreApplication>
#include <QStandardPaths>
#ifdef Q_OS_ANDROID
#include <QFutureWatcher>
#include <QJniEnvironment>
#include <QJniObject>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtConcurrent>
#endif

namespace {

QString lastLine(const QByteArray& err)
{
    const QList<QByteArray> lines = err.trimmed().split('\n');
    for (int i = lines.size() - 1; i >= 0; --i)
        if (!lines.at(i).trimmed().isEmpty()) return QString::fromUtf8(lines.at(i).trimmed());
    return {};
}

class ProcessRunner : public YtdlpRunner {
public:
    using YtdlpRunner::YtdlpRunner;
    void run(const QStringList& args, int timeoutMs, std::function<void(YtdlpResult)> done) override
    {
        QString exe = qEnvironmentVariable("LUMEN_YTDLP");
        if (exe.isEmpty()) exe = QStandardPaths::findExecutable(QStringLiteral("yt-dlp"));
        if (exe.isEmpty()) {
            YtdlpResult r;
            r.err = tr("yt-dlp isn't installed. Install it (Arch: pacman -S yt-dlp) and try again.");
            QTimer::singleShot(0, this, [done, r] { done(r); });
            return;
        }
        auto* p = new QProcess(this);
        auto* t = new QTimer(p);
        t->setSingleShot(true);
        auto finished = std::make_shared<bool>(false);
        auto finish = [p, finished, done](YtdlpResult r) {
            if (*finished) return;
            *finished = true;
            p->disconnect();
            if (p->state() != QProcess::NotRunning) p->kill();
            p->deleteLater();
            done(std::move(r));
        };
        connect(t, &QTimer::timeout, p, [finish] { YtdlpResult r; r.err = QStringLiteral("yt-dlp timed out"); finish(r); });
        connect(p, &QProcess::errorOccurred, p, [finish, p](QProcess::ProcessError e) {
            if (e != QProcess::FailedToStart) return;
            YtdlpResult r; r.err = QStringLiteral("Couldn't start yt-dlp: %1").arg(p->errorString()); finish(r);
        });
        connect(p, &QProcess::finished, p, [finish, p](int code, QProcess::ExitStatus st) {
            YtdlpResult r;
            r.out = p->readAllStandardOutput();
            r.ok = st == QProcess::NormalExit && code == 0;
            if (!r.ok) { r.err = lastLine(p->readAllStandardError()); if (r.err.isEmpty()) r.err = QStringLiteral("yt-dlp failed"); }
            finish(r);
        });
        p->setProcessChannelMode(QProcess::SeparateChannels);
        p->start(exe, args);
        t->start(timeoutMs);
    }
};

#ifdef Q_OS_ANDROID
// yt-dlp + its Python + QuickJS (for YouTube's JS challenges) ship inside the APK through the
// youtubedl-android library; app.lumen.YtdlpBridge (Kotlin) runs one command and returns
// {"ok":bool,"out":string,"err":string} as JSON.
class AndroidRunner : public YtdlpRunner {
public:
    using YtdlpRunner::YtdlpRunner;
    void run(const QStringList& args, int timeoutMs, std::function<void(YtdlpResult)> done) override
    {
        auto* w = new QFutureWatcher<QByteArray>(this);
        connect(w, &QFutureWatcher<QByteArray>::finished, this, [w, done] {
            YtdlpResult r;
            const QJsonObject o = QJsonDocument::fromJson(w->result()).object();
            r.ok = o.value("ok").toBool();
            r.out = o.value("out").toString().toUtf8();
            r.err = o.value("err").toString();
            if (!r.ok && r.err.isEmpty()) r.err = QStringLiteral("yt-dlp failed");
            w->deleteLater();
            done(std::move(r));
        });
        w->setFuture(QtConcurrent::run([args, timeoutMs]() -> QByteArray {
            QJniEnvironment env;                                   // attaches this worker thread to the JVM
            jclass str = env.findClass("java/lang/String");
            jobjectArray arr = env->NewObjectArray(args.size(), str, nullptr);
            for (int i = 0; i < args.size(); ++i) {
                QJniObject s = QJniObject::fromString(args.at(i));
                env->SetObjectArrayElement(arr, i, s.object<jstring>());
            }
            QJniObject ctx = QNativeInterface::QAndroidApplication::context();
            QJniObject res = QJniObject::callStaticObjectMethod("app/lumen/YtdlpBridge", "run",
                                                                "(Landroid/content/Context;[Ljava/lang/String;I)Ljava/lang/String;",
                                                                ctx.object(), arr, jint((timeoutMs + 999) / 1000));
            env->DeleteLocalRef(arr);
            if (!res.isValid()) return R"({"ok":false,"err":"yt-dlp is not available in this build"})";
            return res.toString().toUtf8();
        }));
    }
};
#endif

}   // namespace

YtdlpRunner* createYtdlpRunner(QObject* parent)
{
#ifdef Q_OS_ANDROID
    return new AndroidRunner(parent);
#else
    return new ProcessRunner(parent);
#endif
}
