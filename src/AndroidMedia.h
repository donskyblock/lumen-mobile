#pragma once
#include "MediaBrowse.h"
#include <QObject>
#include <QTimer>

class Library;
class Player;
class Playlists;

// Connects the C++ player to Android's media session (src: android/src/app/lumen/LumenBridge.kt):
//  - pushes what is playing (title, cover, position, play/pause ...) so the notification, lock screen and Android Auto show it
//  - receives play/pause/next/seek and "play this id" from Android, and answers browse and search requests for the car
class AndroidMedia : public QObject {
    Q_OBJECT
public:
    AndroidMedia(Player* player, Library* library, Playlists* playlists, QObject* parent);
    // GUI thread; called through the JNI entry points in AndroidMedia.cpp
    void command(int cmd, qint64 arg);
    void playId(const QString& id);
    QVector<MediaRow> rows(const QString& parentId);
    QVector<MediaRow> searchRows(const QString& query);
    MediaBrowse* browse() const { return m_browse; }

private:
    void push();
    Player* m_player;
    MediaBrowse* m_browse;
    QTimer m_debounce;
};
