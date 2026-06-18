package com.example.skt_takip

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
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
        applyLockScreenFlags()
    }

    // singleTask modunda activity yeniden kullanilirsa onCreate cagrilmaz,
    // onNewIntent cagrilir. Kilit ekrani bayraklarini burada da uygula.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlags()
    }

    /// Kilit ekrani uzerinde gosterim + ekrani uyandirma.
    ///
    /// ONEMLI: Bu bayraklar SADECE ekrani kilit ustune cikarir; kilidi
    /// ACMAZ (parola/biyometri yine gerekir, bu guvenlik geregi dogrudur).
    /// "alarm" paketi 5.x kendi full-screen intent'ini yonetir; biz burada
    /// yalnizca activity one geldiginde ekranin uyanmasini ve kilit ustune
    /// cikmasini garanti ederiz. Kilidi bypass ETMEYIZ; kullanici kilidi
    /// acinca alarm ekrani (AlarmRingScreen) onunde olur.
    ///
    /// Onceki surumde ayrica FLAG_KEEP_SCREEN_ON eklenmis ve bu, "alarm"
    /// paketi 5.x'in kendi full-screen intent yonetimiyle CAKISARAK ekranin
    /// acilip kapanmasina yol aciyordu. Kaldirildi.
    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
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
                    "startKeepAlive" -> {
                        setKeepAliveFlag(true)
                        val svc = Intent(this, KeepAliveService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(svc)
                        } else {
                            startService(svc)
                        }
                        result.success(true)
                    }
                    "stopKeepAlive" -> {
                        setKeepAliveFlag(false)
                        stopService(Intent(this, KeepAliveService::class.java))
                        result.success(true)
                    }
                    "raiseAlarmVolume" -> {
                        raiseAlarmVolume()
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

    // Boot sonrasi BootReceiver'in okuyabilmesi icin kalici servis tercihini
    // DUZ (sifresiz) SharedPreferences'a yaz. flutter_secure_storage native
    // taraftan kolay okunamadigi icin ayri bir bayrak tutuyoruz.
    private fun setKeepAliveFlag(on: Boolean) {
        try {
            val sp = getSharedPreferences("skt_native_prefs", Context.MODE_PRIVATE)
            sp.edit().putBoolean("keep_alive_on", on).apply()
        } catch (_: Exception) {
        }
    }

    // STREAM_ALARM ses seviyesini maksimuma cikar (alarm 1 dk kapatilmadiysa).
    private fun raiseAlarmVolume() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
        } catch (e: Exception) {
            // sessizce gec
        }
    }
}
