package app.lumen

import android.content.Context
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Runs one yt-dlp command for the C++ side (src/YtdlpRunner.cpp, class AndroidRunner) and answers with
 * {"ok":bool,"out":string,"err":string}. yt-dlp, Python and the JavaScript runtime YouTube needs come from the
 * youtubedl-android library; this file is the only place that talks to it.
 *
 * If a newer library version renames something, the compiler will point here and nowhere else.
 */
object YtdlpBridge {
    private const val TAG = "LumenYtdlp"
    private const val PREFS = "lumen_ytdlp"
    private const val UPDATE_EVERY_MS = 24L * 60 * 60 * 1000

    // Options of the commands Lumen issues that take a separate value; everything else starting with "-" is a flag.
    private val VALUE_OPTIONS = setOf(
        "-f", "--socket-timeout", "--retries", "--extractor-retries", "--playlist-end",
        "--cookies", "--cookies-from-browser", "--extractor-args",
    )

    private val lock = Any()
    @Volatile private var ready = false
    @Volatile private var initError: String? = null

    private fun ensureInit(context: Context) {
        if (ready) return
        synchronized(lock) {
            if (ready) return
            try {
                YoutubeDL.getInstance().init(context.applicationContext)
                ready = true
                updateInBackground(context.applicationContext)
            } catch (e: Exception) {
                initError = "yt-dlp could not start: ${e.message}"
                Log.e(TAG, "init failed", e)
            }
        }
    }

    // YouTube changes weekly and yt-dlp follows; check once a day, never on the playback path.
    private fun updateInBackground(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val last = prefs.getLong("lastUpdate", 0L)
        if (System.currentTimeMillis() - last < UPDATE_EVERY_MS) return
        thread(name = "ytdlp-update", isDaemon = true) {
            try {
                val status = YoutubeDL.getInstance().updateYoutubeDL(context)
                Log.i(TAG, "yt-dlp update: $status")
                prefs.edit().putLong("lastUpdate", System.currentTimeMillis()).apply()
            } catch (e: Exception) {
                Log.w(TAG, "yt-dlp update failed: ${e.message}")
            }
        }
    }

    @JvmStatic
    fun run(context: Context, args: Array<String>, timeoutSec: Int): String {
        ensureInit(context)
        if (!ready) return reply(false, "", initError ?: "yt-dlp is not available")

        val urls = ArrayList<String>()
        val options = ArrayList<Pair<String, String?>>()
        var i = 0
        while (i < args.size) {
            val a = args[i]
            if (a.startsWith("-") && a.length > 1) {
                if (a in VALUE_OPTIONS && i + 1 < args.size) { options += a to args[i + 1]; i += 2 }
                else { options += a to null; i += 1 }
            } else {
                urls += a                                   // search terms, ytsearch5:..., :ytrec and addresses
                i += 1
            }
        }
        val request = YoutubeDLRequest(urls)
        for ((name, value) in options) if (value == null) request.addOption(name) else request.addOption(name, value)

        val processId = UUID.randomUUID().toString()
        val timedOut = AtomicBoolean(false)
        val watchdog = thread(name = "ytdlp-timeout", isDaemon = true) {
            try {
                Thread.sleep(timeoutSec.coerceAtLeast(1) * 1000L)
                timedOut.set(true)
                YoutubeDL.getInstance().destroyProcessById(processId)
            } catch (_: InterruptedException) {
                // finished in time
            }
        }
        return try {
            val response = YoutubeDL.getInstance().execute(request, processId)
            reply(true, response.out, "")
        } catch (e: Exception) {
            reply(false, "", if (timedOut.get()) "yt-dlp timed out" else lastLine(e.message))
        } finally {
            watchdog.interrupt()
        }
    }

    private fun lastLine(message: String?): String =
        message.orEmpty().trim().lines().lastOrNull { it.isNotBlank() }?.trim().orEmpty().ifEmpty { "yt-dlp failed" }

    private fun reply(ok: Boolean, out: String, err: String): String =
        JSONObject().put("ok", ok).put("out", out).put("err", err).toString()
}
