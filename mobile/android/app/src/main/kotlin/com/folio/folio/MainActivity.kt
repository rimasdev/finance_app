package com.folio.folio

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
            when (call.method) {
                "setSession" -> {
                    prefs.edit()
                        .putString("token", call.argument<String>("token"))
                        .putString("api_base", call.argument<String>("baseUrl"))
                        .apply()
                    result.success(null)
                }
                "clearSession" -> {
                    prefs.edit().remove("token").remove("api_base").apply()
                    result.success(null)
                }
                "setAutoTrack" -> {
                    prefs.edit().putBoolean("enabled", call.argument<Boolean>("enabled") ?: true).apply()
                    result.success(null)
                }
                "autoTrackEnabled" -> result.success(prefs.getBoolean("enabled", true))
                "notificationAccessEnabled" -> result.success(listenerEnabled())
                "openNotificationAccess" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "smsPermissionGranted" -> result.success(smsGranted())
                "requestSmsPermission" -> {
                    requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS), 41)
                    result.success(null)
                }
                "takeSharedText" -> {
                    val text = pendingShare
                    pendingShare = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureShare(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            pendingShare = intent.getStringExtra(Intent.EXTRA_TEXT)
        }
    }

    private fun smsGranted(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED
    }

    private fun listenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return flat.contains(packageName)
    }

    companion object {
        private const val CHANNEL = "com.folio/capture"
        private const val PREFS = "folio_native"
        private var pendingShare: String? = null
    }
}
