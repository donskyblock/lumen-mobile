#pragma once
#include "NativeExtension.h"
#include "YtdlpRunner.h"
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <memory>

// In-process version of extensions/ytdlp/main.py: same methods (source.search / source.resolve /
// source.recommend), same yt-dlp command lines, same fallbacks. Keep the two in step.
class YtdlpExtension : public NativeExtension {
    Q_OBJECT
public:
    explicit YtdlpExtension(QObject* parent = nullptr);
    void call(const QString& method, const QJsonObject& params, PluginReply cb, int timeoutMs, PluginPartial partial) override;

    // exposed for tests
    static QStringList authArgs(const QJsonObject& params);
    static QString friendly(const QString& msg, bool signedIn);
    static QString videoId(const QString& url);
    static QString seedVideo(const QJsonArray& entries, const QJsonObject& params);

private:
    struct ResolveJob;
    void resolveStep(std::shared_ptr<ResolveJob> job);
    void search(const QJsonObject& p, PluginReply cb, PluginPartial partial);
    void recommend(const QJsonObject& p, PluginReply cb);
    void resolve(const QJsonObject& p, PluginReply cb);
    void opens(const QString& url, const QJsonObject& headers, std::function<void(bool)> done);

    YtdlpRunner* m_runner = nullptr;
    QNetworkAccessManager m_nam;
};
