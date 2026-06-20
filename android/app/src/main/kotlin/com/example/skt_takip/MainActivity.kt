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
import android.view.WindowInsets
import android.view.WindowInsetsController
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

    // TAM EKRAN — IKI KATMANLI COZUM:
    //  1) styles.xml'deki NormalTheme parent'i Theme.*.Fullscreen +
    //     android:windowFullscreen=true: status bar'i Flutter motoru hic
    //     devreye girmeden, pencere OLUSTURULURKEN native olarak kaldirir.
    //     Bu katman Flutter'in SystemUiMode.immersiveSticky bug'indan
    //     (flutter/flutter#177857, #95403 - bircok Android cihazda siyah
    //     serit birakan, resmi olarak bilinen/acik motor hatasi) TAMAMEN
    //     bagimsizdir.
    //  2) Bu fonksiyon: sistem navigasyon cubugunu da gizler + "sticky"
    //     (kullanici kenardan kaydirinca gecici gorunme) davranisini
    //     ekler. Tema katmani zaten status bar'i kaldirdigi icin burada
    //     asil is nav bar + swipe davranisidir; status bar icin de ekstra
    //     bir guvenlik katmani olarak ayni cagriyi tekrarliyoruz.
    private fun applyImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ (API 30+): modern WindowInsetsController API.
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            // Android 10 ve altı: eski bayrak tabanlı yöntem.
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveMode()
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode()
    }

    // Pencere odagi her geri geldiginde (orn. bildirim cekmecesi kapaninca,
    // baska bir dialog kapaninca) immersive modu yeniden zorla. Bu, Android'in
    // sistem UI bayraklarini "sticky" tutmasini saglayan en guvenilir noktadir.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyImmersiveMode()
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
