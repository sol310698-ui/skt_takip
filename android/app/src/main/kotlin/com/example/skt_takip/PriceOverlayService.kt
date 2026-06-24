package com.example.skt_takip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * ════════════════════════════════════════════════════════════════════
 *  FIYAT KONTROL — YUZEN BALONCUK (OVERLAY) SERVISI
 * ────────────────────────────────────────────────────────────────────
 *  Sirket uygulamasinin ustunde duran, surukenebilir yuvarlak bir buton.
 *  - Rengi son fiyat-kontrol sonucunu gosterir (yesil/kirmizi/sari/notr).
 *  - Basinca: bizim uygulamayi HIZLI QR moduyla acar (MainActivity'ye
 *    "openQuickScan" intent'i). QR okunup sonuc alininca otomatik geri
 *    donulur (Flutter tarafi halleder).
 *
 *  Kullanici Fiyat Kontrol ekranindaki anahtardan acip kapatir. "Ustte
 *  ciz" izni (SYSTEM_ALERT_WINDOW) bir kez elle verilir.
 * ════════════════════════════════════════════════════════════════════
 */
class PriceOverlayService : Service() {

    companion object {
        const val ACTION_START = "overlay_start"
        const val ACTION_STOP = "overlay_stop"
        const val ACTION_UPDATE = "overlay_update"
        const val EXTRA_STATE = "state" // "neutral"|"match"|"mismatch"|"wrong"|"nosystem"

        private const val CHANNEL_ID = "skt_overlay_channel"
        private const val NOTIF_ID = 4242

        @Volatile
        var isRunning: Boolean = false
            private set

        // Flutter'in baloncuk rengini guncellemesi icin son durum.
        @Volatile
        var pendingState: String = "neutral"
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var bubbleCircle: GradientDrawable? = null
    private var label: TextView? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: "neutral"
                applyState(state)
                return START_STICKY
            }
            else -> {
                startForegroundInternal()
                showBubble()
            }
        }
        return START_STICKY
    }

    private fun startForegroundInternal() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Fiyat Kontrol Baloncuğu",
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(ch)
        }
        val notif: Notification = Notification.Builder(
            this,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) CHANNEL_ID else ""
        )
            .setContentTitle("Fiyat Kontrol aktif")
            .setContentText("Baloncuk ekranda. Kapatmak için uygulamadan kapatın.")
            .setSmallIcon(android.R.drawable.ic_menu_search)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notif,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun showBubble() {
        // Ustte ciz izni yoksa kendini durdur (Flutter tarafi izin ister).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)
        ) {
            stopSelf()
            return
        }
        if (bubbleView != null) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val size = (64 * resources.displayMetrics.density).toInt()
        val container = FrameLayout(this)

        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(stateColor("neutral"))
            setStroke((2 * resources.displayMetrics.density).toInt(), Color.WHITE)
        }
        bubbleCircle = circle

        val tv = TextView(this).apply {
            text = "₺"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
            background = circle
        }
        label = tv
        container.addView(
            tv,
            FrameLayout.LayoutParams(size, size)
        )

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = 320
        }

        // Surukleme + tiklama ayrimi.
        var initX = 0
        var initY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initX = params.x
                    initY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (abs(dx) > 12 || abs(dy) > 12) moved = true
                    params.x = initX + dx
                    params.y = initY + dy
                    windowManager?.updateViewLayout(container, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) onBubbleTap()
                    true
                }
                else -> false
            }
        }

        try {
            windowManager?.addView(container, params)
            bubbleView = container
            isRunning = true
            applyState(pendingState)
        } catch (e: Exception) {
            stopSelf()
        }
    }

    /** Baloncuga tiklayinca: uygulamayi hizli QR moduyla ac. */
    private fun onBubbleTap() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            intent?.apply {
                action = Intent.ACTION_VIEW
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("openQuickScan", true)
            }
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun applyState(state: String) {
        pendingState = state
        handler.post {
            bubbleCircle?.setColor(stateColor(state))
            label?.text = when (state) {
                "match" -> "✓"
                "mismatch" -> "₺"
                "wrong" -> "!"
                "nosystem" -> "?"
                else -> "₺"
            }
            label?.invalidate()
        }
    }

    private fun stateColor(state: String): Int = when (state) {
        "match" -> Color.parseColor("#34D399")    // yesil
        "mismatch" -> Color.parseColor("#F43F5E") // kirmizi
        "wrong" -> Color.parseColor("#F43F5E")    // kirmizi
        "nosystem" -> Color.parseColor("#FBBF24") // sari
        else -> Color.parseColor("#7C8CF8")       // notr (mor)
    }

    override fun onDestroy() {
        try {
            bubbleView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        }
        bubbleView = null
        isRunning = false
        super.onDestroy()
    }
}
