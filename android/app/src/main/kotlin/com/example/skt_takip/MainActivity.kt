package com.example.skt_takip

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// NOT: FlutterActivity yerine FlutterFragmentActivity kullaniliyor.
// local_auth (parmak izi/yuz tanima) paketinin resmi gereksinimi budur;
// biyometri dialog'u bir Fragment uzerinden gosterilir. Bu degisiklik
// alarm paketinin kilit ekrani davranisini ETKILEMEZ (asagidaki not
// gecerliligini koruyor, sadece temel Activity sinifi degisti).
class MainActivity : FlutterFragmentActivity() {
    private val channel = "skt_takip/fullscreen"

    // ONEMLI: Activity'ye kilit ekrani bayraklari (setShowWhenLocked /
    // setTurnScreenOn) EKLEMIYORUZ. "alarm" paketi 5.x, alarm calarken kilit
    // ekrani uzerinde gosterimi ve ekrani uyandirmayi KENDI yonetir. Resmi
    // kurulum rehberi de v5'e gecerken bu bayraklarin KALDIRILMASINI soyler.
    // Bunlari MainActivity'de zorlamak, paketin full-screen intent yonetimiyle
    // CAKISARAK alarm ekraninin acilip kapanmasina ve kilit ekraninin one
    // gecip parola istemesine yol aciyordu. Bu yuzden tamamen kaldirildi.

    // EDGE-TO-EDGE (status bar GIZLENMEZ, ICERIK ALTINA UZANIR):
    //  Eski yaklasim status bar'i tamamen gizliyordu (fullscreen +
    //  immersiveSticky). Bu, Xiaomi/MIUI cihazlarda status bar bolgesinde
    //  SIYAH SERIT birakiyordu. Yeni yaklasim status bar'i GIZLEMEZ;
    //  onun yerine SEFFAF yapar ve uygulama icerigini (banner gradient /
    //  AppBar) status bar'in ARKASINA uzatir. Boylece status bar her zaman
    //  ust bardaki renkle ayni gorunur; siyah serit OLUSMAZ.
    //
    //  setDecorFitsSystemWindows(false): icerigi sistem cubuklari arkasina
    //  uzat. Cubuk renkleri styles.xml'de transparent. Flutter tarafinda
    //  MediaQuery.padding.top zaten dogru insets'i verir, banner bu kadar
    //  yukari uzanir.
    private fun applyEdgeToEdge() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge()
    }

    override fun onResume() {
        super.onResume()
        applyEdgeToEdge()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyEdgeToEdge()
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
