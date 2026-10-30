#pragma once
#include <QByteArray>
#include <QObject>
#include <QString>
#include <QStringList>
#include <functional>

// One yt-dlp invocation. `done` always runs on the thread that called run() (the GUI thread).
struct YtdlpResult {
    bool ok = false;           // exit code 0
    QByteArray out;            // stdout
    QString err;               // last line of stderr (or why it could not run)
};

class YtdlpRunner : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    virtual void run(const QStringList& args, int timeoutMs, std::function<void(YtdlpResult)> done) = 0;
};

// Desktop/tests: a yt-dlp executable ($LUMEN_YTDLP, else "yt-dlp" on PATH). Android: the yt-dlp that ships inside the app.
YtdlpRunner* createYtdlpRunner(QObject* parent);           // owned by `parent`
