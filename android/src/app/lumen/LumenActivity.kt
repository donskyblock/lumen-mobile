package app.lumen

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import org.qtproject.qt.android.bindings.QtActivity

/**
 * Qt's activity plus the runtime permissions Lumen needs. Coming back from the permission prompt the app is
 * "active" again and the C++ side rescans the library if it was empty (see main.cpp).
 */
class LumenActivity : QtActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LumenBridge.appContext = applicationContext
        val wanted = ArrayList<String>()
        if (Build.VERSION.SDK_INT >= 33) {
            wanted += Manifest.permission.READ_MEDIA_AUDIO       // the music library
            wanted += Manifest.permission.POST_NOTIFICATIONS     // the playback notification
        } else {
            wanted += Manifest.permission.READ_EXTERNAL_STORAGE
        }
        val missing = wanted.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    private companion object {
        const val PERMISSION_REQUEST = 4711
    }
}
