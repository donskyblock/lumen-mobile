@file:OptIn(UnstableApi::class)

package app.lumen

import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * A Media3 Player that mirrors Lumen's C++ player. It holds no audio: [LumenBridge.state] is what is playing,
 * and every command is forwarded to C++.
 *
 * The playlist shown to Android is [previous?, current, next?] so the next / previous buttons stay enabled; the
 * placeholder items are never played, a seek onto one just means "skip".
 */
class LumenPlayer : SimpleBasePlayer(Looper.getMainLooper()) {

    private val onChange: () -> Unit = { invalidateState() }

    init { LumenBridge.addListener(onChange) }

    private val commands = Player.Commands.Builder().addAll(
        Player.COMMAND_PLAY_PAUSE, Player.COMMAND_PREPARE, Player.COMMAND_STOP,
        Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
        Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM, Player.COMMAND_SEEK_TO_MEDIA_ITEM,
        Player.COMMAND_GET_CURRENT_MEDIA_ITEM, Player.COMMAND_GET_TIMELINE, Player.COMMAND_GET_METADATA,
        Player.COMMAND_SET_MEDIA_ITEM, Player.COMMAND_CHANGE_MEDIA_ITEMS,
        Player.COMMAND_SET_SHUFFLE_MODE, Player.COMMAND_SET_REPEAT_MODE,
    ).build()

    override fun getState(): SimpleBasePlayer.State {
        val s = LumenBridge.state
        val builder = SimpleBasePlayer.State.Builder().setAvailableCommands(commands)
        if (!s.hasTrack) return builder.setPlaybackState(Player.STATE_IDLE).build()

        val ctx = LumenBridge.appContext
        val metadata = MediaMetadata.Builder()
            .setTitle(s.title).setArtist(s.artist).setAlbumTitle(s.album)
            .setIsPlayable(true).setIsBrowsable(false)
            .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
            .apply { if (ctx != null) setArtworkUri(LumenBridge.artworkUri(ctx, s.cover)) }
            .build()
        val current = SimpleBasePlayer.MediaItemData.Builder("current:" + s.id)
            .setMediaItem(MediaItem.Builder().setMediaId(s.id).setMediaMetadata(metadata).build())
            .setDurationUs(if (s.durationMs > 0) s.durationMs * 1000 else C.TIME_UNSET)
            .setIsSeekable(true)
            .build()

        val playlist = ArrayList<SimpleBasePlayer.MediaItemData>(3)
        if (s.hasPrev) playlist += placeholder("previous")
        playlist += current
        if (s.hasNext) playlist += placeholder("next")

        builder
            .setPlaylist(playlist)
            .setCurrentMediaItemIndex(if (s.hasPrev) 1 else 0)
            .setPlaybackState(Player.STATE_READY)
            .setPlayWhenReady(s.playing, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setShuffleModeEnabled(s.shuffle)
            .setRepeatMode(when (s.repeat) { 1 -> Player.REPEAT_MODE_ALL; 2 -> Player.REPEAT_MODE_ONE; else -> Player.REPEAT_MODE_OFF })
        // the progress bar keeps moving between pushes while playing
        builder.setContentPositionMs(
            if (s.playing) SimpleBasePlayer.PositionSupplier.getExtrapolating(s.positionMs, 1f) else SimpleBasePlayer.PositionSupplier.getConstant(s.positionMs)
        )
        return builder.build()
    }

    private fun placeholder(uid: String) = SimpleBasePlayer.MediaItemData.Builder(uid)
        .setMediaItem(MediaItem.Builder().setMediaId(uid).build())
        .build()

    private fun done(): ListenableFuture<*> = Futures.immediateVoidFuture()

    private fun send(cmd: Int, arg: Long = 0) { LumenBridge.native { LumenBridge.nativeCommand(cmd, arg) } }

    override fun handlePrepare(): ListenableFuture<*> = done()

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        send(if (playWhenReady) LumenBridge.CMD_PLAY else LumenBridge.CMD_PAUSE)
        return done()
    }

    override fun handleStop(): ListenableFuture<*> {
        send(LumenBridge.CMD_PAUSE)
        return done()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        val currentIndex = if (LumenBridge.state.hasPrev) 1 else 0
        val position = if (positionMs == C.TIME_UNSET) 0L else positionMs.coerceAtLeast(0L)
        when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> send(LumenBridge.CMD_NEXT)
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> send(LumenBridge.CMD_PREVIOUS)
            Player.COMMAND_SEEK_TO_MEDIA_ITEM -> when {
                mediaItemIndex > currentIndex -> send(LumenBridge.CMD_NEXT)
                mediaItemIndex < currentIndex -> send(LumenBridge.CMD_PREVIOUS)
                else -> send(LumenBridge.CMD_SEEK, position)
            }
            else -> send(LumenBridge.CMD_SEEK, position)
        }
        return done()
    }

    override fun handleSetShuffleModeEnabled(shuffleModeEnabled: Boolean): ListenableFuture<*> {
        if (shuffleModeEnabled != LumenBridge.state.shuffle) send(LumenBridge.CMD_TOGGLE_SHUFFLE)
        return done()
    }

    override fun handleSetRepeatMode(repeatMode: Int): ListenableFuture<*> {
        send(LumenBridge.CMD_SET_REPEAT, when (repeatMode) { Player.REPEAT_MODE_ALL -> 1L; Player.REPEAT_MODE_ONE -> 2L; else -> 0L })
        return done()
    }

    // The car (or a voice command) picked something: its media id says what, C++ builds the queue.
    override fun handleSetMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long): ListenableFuture<*> {
        val id = mediaItems.getOrNull(startIndex.coerceAtLeast(0))?.mediaId
        if (!id.isNullOrEmpty()) LumenBridge.native { LumenBridge.nativePlayId(id) }
        return done()
    }

    override fun handleRelease(): ListenableFuture<*> {
        LumenBridge.removeListener(onChange)
        return done()
    }
}
