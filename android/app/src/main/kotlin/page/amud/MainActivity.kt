package page.amud

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var readerFullscreen = false

    /// The Do Not Disturb mode the reader replaced, restored when it ends.
    /// Null when the reader didn't change it (DND was already on, or off).
    private var dndBefore: Int? = null
    private val notifications get() = getSystemService(android.app.NotificationManager::class.java)
    private fun setReaderDnd(on: Boolean): Boolean {
        val nm = notifications ?: return false
        if (!nm.isNotificationPolicyAccessGranted) return false
        if (on) {
            // Only take over when nothing is set: never override a Focus
            // or schedule the user already has on.
            if (dndBefore == null && nm.currentInterruptionFilter == android.app.NotificationManager.INTERRUPTION_FILTER_ALL) {
                dndBefore = nm.currentInterruptionFilter
                nm.setInterruptionFilter(android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            }
        } else {
            dndBefore?.let { nm.setInterruptionFilter(it) }
            dndBefore = null
        }
        return true
    }
    private fun applyReaderFullscreen() {
        val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (readerFullscreen) controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
        else controller.show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
    }
    override fun onDestroy() {
        // Closed while reading: give the phone its notifications back.
        setReaderDnd(false)
        super.onDestroy()
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyReaderFullscreen()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amud/integrations").setMethodCallHandler { call, result ->
            when (call.method) {
                "setReaderDnd" -> result.success(setReaderDnd(call.arguments == true))
                "readerDndAccess" -> result.success(notifications?.isNotificationPolicyAccessGranted == true)
                "openReaderDndSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    result.success(null)
                }
                "setReaderFullscreen" -> {
                    readerFullscreen = call.arguments == true
                    applyReaderFullscreen()
                    result.success(null)
                }
                "publishTimeline" -> {
                    val json = call.arguments as? String ?: "{}"
                    // Asset transport supports the timeline and short siddur without
                    // approaching DataMap's 100 KB inline limit.
                    val request = com.google.android.gms.wearable.PutDataMapRequest.create("/amud/timeline")
                    request.dataMap.putAsset("timeline", com.google.android.gms.wearable.Asset.createFromBytes(json.toByteArray(Charsets.UTF_8)))
                    request.dataMap.putLong("generatedAt", System.currentTimeMillis())
                    com.google.android.gms.wearable.Wearable.getDataClient(this).putDataItem(request.asPutDataRequest().setUrgent())
                        .addOnSuccessListener { result.success(null) }
                        .addOnFailureListener { result.error("watch_sync", it.message, null) }
                }
                "pinPrayer" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val key = call.argument<String>("key") ?: "shacharit"
                        val title = call.argument<String>("title") ?: key
                        val shortcut = android.content.pm.ShortcutInfo.Builder(this, "pinned-$key")
                            .setShortLabel(title)
                            .setIcon(android.graphics.drawable.Icon.createWithResource(this, R.mipmap.ic_launcher))
                            .setIntent(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse("amud://pray/$key")))
                            .build()
                        val supported = getSystemService(android.content.pm.ShortcutManager::class.java).requestPinShortcut(shortcut, null)
                        if (supported) result.success(null) else result.error("pin", "This launcher does not support pinned shortcuts", null)
                    } else result.error("pin", "Pinned shortcuts need Android 8 or later", null)
                }
                else -> result.notImplemented()
            }
        }
        // In-app updates: the Dart side downloads the release APK into
        // cacheDir/updates and asks here for the system installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "siddur/installer").setMethodCallHandler { call, result ->
            when (call.method) {
                "updatesDir" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.absolutePath)
                "canInstall" -> result.success(canInstall())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "install" -> {
                    try {
                        val file = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                        startActivity(Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
}
