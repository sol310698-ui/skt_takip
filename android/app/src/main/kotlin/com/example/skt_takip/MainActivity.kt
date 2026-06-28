package com.example.skt_takip

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Vibrator
import android.os.VibrationEffect
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.View
import java.util.Locale
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// NOT: FlutterActivity yerine FlutterFragmentActivity kullaniliyor.
// local_auth (parmak izi/yuz tanima) paketinin resmi gereksinimi budur;
// biyometri dialog'u bir Fragment uzerinden gosterilir. Bu degisiklik
// alarm paketinin kilit ekrani davranisini ETKILEMEZ (asagidaki not
// gecerliligini koruyor, sadece temel Activity sinifi degisti).
class MainActivity : FlutterFragmentActivity() {
    private val channel = "skt_takip/fullscreen"

    // FIYAT KONTROL ASISTANI icin ayri kanal. Mevcut "fullscreen" kanaliyla
    // hicbir ilgisi yoktur; bagimsiz calisir.
    private val priceChannel = "skt_takip/price_check"

    // v2: Sistem fiyati guncellemelerini Flutter'a PUSH ile iletmek icin.
    // Eskiden Flutter tarafi 600ms'lik Timer.periodic ile native'i
    // POLLUYORDU; bu da "sirket uygulamasindan geri donunce fiyat gec
    // okunuyor" sikayetinin birebir sebebiydi. Artik
    // PriceAccessibilityService deger DEGISTIGI ANDA bu EventChannel
    // uzerinden Flutter'a haber veriyor — gecikme native event-loop
    // gecikmesinden ibaret (genelde <100ms), polling araligindan degil.
    private val priceEventChannel = "skt_takip/price_check_events"
    private var priceEventSink: EventChannel.EventSink? = null

    // VERI TOPLAMA: sirket uygulamasinin urun detay ekranlarindan otomatik
    // toplanan urunler (barkod + ad + stok kodu) bu EventChannel ile
    // Flutter'a push edilir. Fiyat kontrol kanalindan bagimsizdir.

    private var tts: TextToSpeech? = null
    private var ttsReady = false

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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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

        // ── FIYAT KONTROL ASISTANI KANALI ───────────────────────────────
        // Mevcut "fullscreen" kanalindan tamamen bagimsiz. Flutter tarafi
        // bu kanal uzerinden: erisilebilirlik servisinin durumunu sorar,
        // son okunan sistem fiyatini ceker (ilk yukleme / fallback icin),
        // ayar sayfasini acar, sesli okuma (TTS) ve titresim tetikler.
        val priceCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, priceChannel)
        priceCh
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityServiceRunning" ->
                        result.success(PriceAccessibilityService.serviceRunning)
                    "openAccessibilitySettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "getLastSystemPrice" -> {
                        result.success(PriceAccessibilityService.snapshot())
                    }
                    "getDebugInfo" -> {
                        result.success(PriceAccessibilityService.debugSnapshot())
                    }
                    "clearLastSystemPrice" -> {
                        PriceAccessibilityService.clearLastPrice()
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        speak(text)
                        result.success(true)
                    }
                    "vibrate" -> {
                        val mismatch = call.argument<Boolean>("mismatch") ?: false
                        vibrate(mismatch)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── FIYAT KONTROL — CANLI VERI AKISI (EventChannel) ─────────────
        // PUSH modeli: PriceAccessibilityService deger degistirdigi anda
        // PriceAccessibilityService.setListener(...) ile kayitli bu
        // dinleyiciyi tetikler, biz de aninda guncel snapshot'i Flutter'a
        // gondeririz. Flutter tarafi artik PERIYODIK SORGU (polling)
        // YAPMAZ — sadece bu stream'i dinler. "Gec okuma" sikayetinin
        // koku buradaydi; cozum budur.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, priceEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    priceEventSink = sink
                    PriceAccessibilityService.setListener(object :
                        PriceAccessibilityService.PriceUpdateListener {
                        override fun onPriceUpdate() {
                            // sink Flutter tarafi dinlemeyi kestiyse null
                            // olabilir; o an icin guvenli sekilde yut.
                            priceEventSink?.success(PriceAccessibilityService.snapshot())
                        }
                    })
                    // Dinleyici ilk baglandiginda mevcut durumu da hemen
                    // gonder (ekran acildiginda son bilineni gostersin).
                    priceEventSink?.success(PriceAccessibilityService.snapshot())
                }

                override fun onCancel(args: Any?) {
                    PriceAccessibilityService.setListener(null)
                    priceEventSink = null
                }
            })
    }

    // ── TTS (sesli okuma) ───────────────────────────────────────────────
    private fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                try {
                    tts?.language = Locale("tr", "TR")
                    // Daha hizli okuma (varsayilan 1.0 -> 1.5).
                    tts?.setSpeechRate(1.5f)
                } catch (_: Exception) {
                }
                ttsReady = true
            }
        }
    }

    private fun speak(text: String) {
        ensureTts()
        try {
            if (ttsReady) {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "price_check")
            } else {
                // TTS hazir degilse kisa bir gecikmeyle tekrar dene.
                tts?.setOnUtteranceProgressListener(null)
            }
        } catch (_: Exception) {
        }
    }

    // ── Titresim ────────────────────────────────────────────────────────
    private fun vibrate(mismatch: Boolean) {
        try {
            val vib = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
            // Uyusmazlik: guclu, tekrarli desen. Uyumlu: tek kisa titresim.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (mismatch) {
                    val pattern = longArrayOf(0, 400, 150, 400, 150, 400)
                    vib.vibrate(VibrationEffect.createWaveform(pattern, -1))
                } else {
                    vib.vibrate(VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE))
                }
            } else {
                @Suppress("DEPRECATION")
                if (mismatch) {
                    vib.vibrate(longArrayOf(0, 400, 150, 400, 150, 400), -1)
                } else {
                    vib.vibrate(120)
                }
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
        }
        tts = null
        PriceAccessibilityService.setListener(null)
        priceEventSink = null
        super.onDestroy()
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
