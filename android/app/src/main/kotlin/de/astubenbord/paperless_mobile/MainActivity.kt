package de.astubenbord.paperless_mobile

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isGooglePlayServicesAvailable" -> result.success(isGooglePlayServicesAvailable())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Checks whether Google Play Services are installed and enabled, without depending on the
     * Play Services client libraries. The ML Kit document scanner requires them; on devices
     * without them (e.g. de-googled ROMs), the app falls back to the OpenCV based scanner.
     */
    private fun isGooglePlayServicesAvailable(): Boolean {
        return try {
            packageManager.getApplicationInfo(GMS_PACKAGE, 0).enabled
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private companion object {
        const val PLATFORM_CHANNEL = "de.astubenbord.paperless_mobile/platform"
        const val GMS_PACKAGE = "com.google.android.gms"
    }
}
