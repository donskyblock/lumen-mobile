#pragma once
#include "Db.h"
#include <QObject>
#include <QVariant>

// Tiny persistent key/value store for QML (window size, last page, panel state).
class UiState : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool mobile READ mobile CONSTANT)
public:
    using QObject::QObject;
    // True on phones/tablets. LUMEN_MOBILE=1 forces the touch UI on a desktop build (used for screenshots and testing).
    static bool isMobile()
    {
#if defined(Q_OS_ANDROID) || defined(Q_OS_IOS)
        return true;
#else
        return qEnvironmentVariableIntValue("LUMEN_MOBILE") > 0;
#endif
    }
    bool mobile() const { return isMobile(); }
    Q_INVOKABLE int intValue(const QString& key, int def) const { return Db::get().kv("ui." + key, QString::number(def)).toInt(); }
    Q_INVOKABLE QString stringValue(const QString& key, const QString& def) const { return Db::get().kv("ui." + key, def); }
    Q_INVOKABLE bool boolValue(const QString& key, bool def) const { return Db::get().kv("ui." + key, def ? "1" : "0") == "1"; }
    Q_INVOKABLE void set(const QString& key, const QVariant& v) { Db::get().setKv("ui." + key, v.typeId() == QMetaType::Bool ? (v.toBool() ? "1" : "0") : v.toString()); }
};
