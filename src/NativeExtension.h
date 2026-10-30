#pragma once
#include "PluginManager.h"

// Some extensions have no separate process on a phone (Android can't run a Python script from app storage,
// and there is no system yt-dlp). Those ship a "native" implementation inside the app that answers exactly the
// same JSON-RPC methods, so the rest of Lumen can't tell the difference.
class NativeExtension : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    virtual void call(const QString& method, const QJsonObject& params, PluginReply cb, int timeoutMs, PluginPartial partial) = 0;
    virtual void stop() {}
};

// plugin.json says  "native": "ytdlp"  and this build decides whether that name is available here.
// Android always uses native extensions; on a desktop build LUMEN_NATIVE_EXT=1 turns them on (tests).
bool nativeExtensionAvailable(const QString& name);
NativeExtension* createNativeExtension(const PluginInfo& info, QObject* parent);   // null if this build has none; owned by `parent`
