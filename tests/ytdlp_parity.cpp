// Reads a JSON list of cases on stdin, answers each with the C++ helpers of the native yt-dlp extension.
// tests/ytdlp_parity.py compares the answers with extensions/ytdlp/main.py.
#include "../src/YtdlpExtension.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QTextStream>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTextStream in(stdin);
    const QJsonArray cases = QJsonDocument::fromJson(in.readAll().toUtf8()).array();
    QJsonArray out;
    for (const QJsonValue& v : cases) {
        const QJsonObject c = v.toObject();
        const QString kind = c.value("kind").toString();
        if (kind == "friendly") out << YtdlpExtension::friendly(c.value("msg").toString(), c.value("signed").toBool());
        else if (kind == "video_id") out << YtdlpExtension::videoId(c.value("url").toString());
        else if (kind == "seed_video") out << YtdlpExtension::seedVideo(c.value("entries").toArray(), c.value("params").toObject());
        else if (kind == "auth") { QJsonArray a; for (const QString& s : YtdlpExtension::authArgs(c.value("params").toObject())) a << s; out << a; }
        else out << QJsonValue();
    }
    QTextStream(stdout) << QJsonDocument(out).toJson(QJsonDocument::Compact) << "\n";
    return 0;
}
