package app.lumen

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The seam between Lumen's C++ player (the real audio engine, in this same process) and the Android media
 * session. C++ pushes the player state in with [pushState]; Android's commands (notification buttons, lock
 * screen, Bluetooth, Android Auto) go back out through the native* functions, which src/AndroidMedia.cpp
 * registers when the app starts.
 */
object LumenBridge {
    private const val TAG = "LumenBridge"

    const val CMD_PLAY = 0
    const val CMD_PAUSE = 1
    const val CMD_NEXT = 2
    const val CMD_PREVIOUS = 3
    const val CMD_SEEK = 4            // arg = position in ms
    const val CMD_TOGGLE_SHUFFLE = 5
    const val CMD_SET_REPEAT = 6      // arg = Lumen mode: 0 off, 1 all, 2 one

    class State(
        val hasTrack: Boolean = false,
        val id: String = "",
        val title: String = "",
        val artist: String = "",
        val album: String = "",
        val durationMs: Long = 0,
        val positionMs: Long = 0,
        val playing: Boolean = false,
        val hasPrev: Boolean = false,
        val hasNext: Boolean = false,
        val cover: String = "",       // a file name in the cover cache, or an http(s) address
        val shuffle: Boolean = false,
        val repeat: Int = 0,          // Lumen: 0 off, 1 all, 2 one
    )

    @Volatile var state = State()
        private set
    @Volatile var nativeReady = false
        private set
    @Volatile var appContext: Context? = null

    private val listeners = CopyOnWriteArrayList<() -> Unit>()
    private val main = Handler(Looper.getMainLooper())
    private var controller: MediaController? = null
    private var connecting = false

    fun addListener(l: () -> Unit) { listeners.add(l) }
    fun removeListener(l: () -> Unit) { listeners.remove(l) }

    /** Address of a cover for MediaMetadata.artworkUri: our provider for cached files, the address itself for online art. */
    fun artworkUri(context: Context, cover: String): Uri? = when {
        cover.isBlank() -> null
        cover.startsWith("http://") || cover.startsWith("https://") -> Uri.parse(cover)
        else -> Uri.parse("content://${context.packageName}.covers/$cover")
    }

    // ---- called by C++ (Qt thread) --------------------------------------------------------------

    @JvmStatic
    fun onNativeReady() {
        nativeReady = true
    }

    @JvmStatic
    fun pushState(
        hasTrack: Boolean, id: String, title: String, artist: String, album: String,
        durationMs: Long, positionMs: Long, playing: Boolean, hasPrev: Boolean, hasNext: Boolean,
        cover: String, shuffle: Boolean, repeat: Int,
    ) {
        state = State(hasTrack, id, title, artist, album, durationMs, positionMs, playing, hasPrev, hasNext, cover, shuffle, repeat)
        main.post {
            if (hasTrack) connectService()
            for (l in listeners) l()
        }
    }

    // Binding a controller to the service is the documented way to keep it alive and let Media3 promote it to a
    // foreground service (notification, lock screen, car) while audio plays in the background.
    private fun connectService() {
        val ctx = appContext ?: return
        if (controller != null || connecting) return
        connecting = true
        try {
            val token = SessionToken(ctx, ComponentName(ctx, PlaybackService::class.java))
            val future = MediaController.Builder(ctx, token).buildAsync()
            future.addListener({
                connecting = false
                try { controller = future.get() } catch (e: Exception) { Log.w(TAG, "media session not available: ${e.message}") }
            }, ctx.mainExecutor)
        } catch (e: Exception) {
            connecting = false
            Log.w(TAG, "could not connect to the media service: ${e.message}")
        }
    }

    // ---- implemented in C++ (src/AndroidMedia.cpp) ----------------------------------------------

    @JvmStatic external fun nativeCommand(cmd: Int, arg: Long)
    @JvmStatic external fun nativePlayId(id: String)
    @JvmStatic external fun nativeBrowse(parentId: String, page: Int, pageSize: Int): String
    @JvmStatic external fun nativeSearch(query: String): String

    /** Runs a native call and turns "the C++ side isn't loaded" (service started without the app) into null. */
    inline fun <T> native(block: () -> T): T? =
        if (!nativeReady) null else try { block() } catch (e: UnsatisfiedLinkError) { null }
}
