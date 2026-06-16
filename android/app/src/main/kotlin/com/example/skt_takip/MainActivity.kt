package com.example.skt_takip

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "skt_takip/fullscreen"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Alarm ekraninin kilit ekrani UZERINDE gorunmesi ve ekrani
        // uyandirmasi icin (sessiz/kisik/kilitli fark etmez).
        // ONEMLI: Kilidi KALDIRMAYIZ (requestDismissKeyguard sesi kesiyordu);
        // sadece kilit ekraninin UZERINE cizeriz (showWhenLocked).
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Android 14+ (API 34): tam ekran intent izni var mi?
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT >= 34) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return nm.canUseFullScreenIntent()
        }
        return true // API 33 ve altinda otomatik var
    }

    // Tam ekran intent izni ayar sayfasini ac (Android 14+).
    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                // Yedek: uygulama detay ayarlari
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName")
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        }
    }
}
