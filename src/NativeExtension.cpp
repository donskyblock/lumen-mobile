#include "NativeExtension.h"
#include "LrclibExtension.h"
#include "YtdlpExtension.h"
#include <QtGlobal>

bool nativeExtensionAvailable(const QString& name)
{
#ifndef Q_OS_ANDROID
    if (!qEnvironmentVariableIntValue("LUMEN_NATIVE_EXT")) return false;
#endif
    return name == QLatin1String("ytdlp") || name == QLatin1String("lrclib");
}

NativeExtension* createNativeExtension(const PluginInfo& info, QObject* parent)
{
    if (info.native.isEmpty() || !nativeExtensionAvailable(info.native)) return nullptr;
    if (info.native == QLatin1String("ytdlp")) return new YtdlpExtension(parent);
    if (info.native == QLatin1String("lrclib")) return new LrclibExtension(parent);
    return nullptr;
}
