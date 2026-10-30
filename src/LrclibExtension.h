#pragma once
#include "NativeExtension.h"
#include <QNetworkAccessManager>

// In-process version of plugins/lrclib/main.py (lyrics.search against lrclib.net). Used where a Python
// script can't run, i.e. on Android.
class LrclibExtension : public NativeExtension {
    Q_OBJECT
public:
    explicit LrclibExtension(QObject* parent = nullptr);
    void call(const QString& method, const QJsonObject& params, PluginReply cb, int timeoutMs, PluginPartial partial) override;
private:
    void fetch(const QList<QPair<QString, QString>>& query, std::function<void(bool ok, const QJsonArray& rows, const QString& err)> done);
    QNetworkAccessManager m_nam;
    QString m_base;
};
