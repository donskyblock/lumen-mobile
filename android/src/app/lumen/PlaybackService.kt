@file:OptIn(UnstableApi::class)

package app.lumen

import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import org.json.JSONArray
import java.util.concurrent.Executors

/**
 * Lumen's media session: notification and lock-screen controls, Bluetooth/headset buttons, and the browse tree
 * Android Auto shows. It owns no audio; [LumenPlayer] mirrors the C++ player.
 *
 * Needs the app process (and with it the C++ engine) to be running: the engine lives there. When a car connects
 * before the app was ever opened, only the four top-level folders are shown and opening them says to start Lumen.
 */
class PlaybackService : MediaLibraryService() {
    private var player: LumenPlayer? = null
    private var session: MediaLibrarySession? = null
    private val executor = MoreExecutors.listeningDecorator(Executors.newFixedThreadPool(2))

    override fun onCreate() {
        super.onCreate()
        LumenBridge.appContext = applicationContext
        val p = LumenPlayer()
        player = p
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, LumenActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaLibrarySession.Builder(this, p, Callback()).setSessionActivity(open).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onDestroy() {
        session?.release()
        session = null
        player?.release()
        player = null
        executor.shutdown()
        super.onDestroy()
    }

    private inner class Callback : MediaLibrarySession.Callback {

        override fun onGetLibraryRoot(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(folder("root", "Lumen"), params))

        override fun onGetChildren(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String,
            page: Int, pageSize: Int, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = executor.submit<LibraryResult<ImmutableList<MediaItem>>> {
            val json = LumenBridge.native { LumenBridge.nativeBrowse(parentId, page, pageSize) }
            when {
                json != null -> LibraryResult.ofItemList(items(json), params)
                parentId == "root" -> LibraryResult.ofItemList(offlineRoot(), params)   // engine not running yet
                else -> LibraryResult.ofError(LibraryResult.RESULT_ERROR_UNKNOWN)
            }
        }

        override fun onGetItem(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(MediaItem.Builder().setMediaId(mediaId).build(), null))

        override fun onSearch(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<Void>> = executor.submit<LibraryResult<Void>> {
            val count = LumenBridge.native { JSONArray(LumenBridge.nativeSearch(query)).length() } ?: 0
            session.notifySearchResultChanged(browser, query, count, params)
            LibraryResult.ofVoid()
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String,
            page: Int, pageSize: Int, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = executor.submit<LibraryResult<ImmutableList<MediaItem>>> {
            val json = LumenBridge.native { LumenBridge.nativeSearch(query) }
            if (json == null) LibraryResult.ofError(LibraryResult.RESULT_ERROR_UNKNOWN)
            else LibraryResult.ofItemList(items(slice(json, page, pageSize)), params)
        }

        // "Play X" by voice arrives as an item with only a search query: turn it into the best match.
        override fun onAddMediaItems(
            mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> = executor.submit<MutableList<MediaItem>> {
            mediaItems.map { item ->
                val query = item.requestMetadata.searchQuery
                if (query.isNullOrBlank()) item
                else {
                    val json = LumenBridge.native { LumenBridge.nativeSearch(query) }
                    val first = json?.let { items(it).firstOrNull() }
                    first ?: item
                }
            }.toMutableList()
        }
    }

    // ---- tree helpers ----------------------------------------------------------------------------

    private fun folder(id: String, title: String): MediaItem = MediaItem.Builder()
        .setMediaId(id)
        .setMediaMetadata(
            MediaMetadata.Builder().setTitle(title).setIsBrowsable(true).setIsPlayable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED).build()
        ).build()

    private fun offlineRoot(): ImmutableList<MediaItem> = ImmutableList.of(
        folder("cat:playlists", "Playlists"), folder("cat:albums", "Albums"),
        folder("cat:artists", "Artists"), folder("cat:songs", "Songs"),
    )

    // C++ answers [{"id","title","subtitle","browsable","cover"}]; page slicing already happened there for browse
    private fun items(json: String): ImmutableList<MediaItem> {
        val arr = JSONArray(json)
        val out = ImmutableList.builder<MediaItem>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val browsable = o.optBoolean("browsable")
            val meta = MediaMetadata.Builder()
                .setTitle(o.optString("title"))
                .setSubtitle(o.optString("subtitle"))
                .setArtist(o.optString("subtitle"))
                .setIsBrowsable(browsable)
                .setIsPlayable(!browsable)
                .setMediaType(if (browsable) MediaMetadata.MEDIA_TYPE_FOLDER_MIXED else MediaMetadata.MEDIA_TYPE_MUSIC)
                .setArtworkUri(LumenBridge.artworkUri(applicationContext, o.optString("cover")))
                .build()
            out.add(MediaItem.Builder().setMediaId(o.getString("id")).setMediaMetadata(meta).build())
        }
        return out.build()
    }

    private fun slice(json: String, page: Int, pageSize: Int): String {
        val arr = JSONArray(json)
        val from = page.coerceAtLeast(0) * pageSize.coerceAtLeast(1)
        val out = JSONArray()
        for (i in from until minOf(arr.length(), from + pageSize.coerceAtLeast(1))) out.put(arr.get(i))
        return out.toString()
    }
}
