package com.example.skt_takip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * ════════════════════════════════════════════════════════════════════
 *  YUZEN ASISTAN BALONCUGU (v159)
 * ────────────────────────────────────────────────────────────────────
 *  Telefonun HER YERINDE gorunen, surukleneblir baloncuk. Dokununca
 *  kucuk bir sohbet kutusu acilir; yazilan soru uygulamanin Depo
 *  Asistani ekranina iletilir (uygulama kapaliysa acilir).
 *
 *  Neden native? Overlay penceresi (TYPE_APPLICATION_OVERLAY) yalnizca
 *  Android pencere yoneticisiyle cizilebilir; Flutter widget'lari
 *  uygulama disinda gorunmez.
 * ════════════════════════════════════════════════════════════════════
 */
class AssistantBubbleService : Service() {

    companion object {
        const val ACTION_START = "skt.bubble.START"
        const val ACTION_STOP = "skt.bubble.STOP"

        /** Baloncuktan gonderilen soru — MainActivity acilirken okunur. */
        const val EXTRA_QUESTION = "skt.bubble.question"

        @Volatile
        var running: Boolean = false
            private set

        private const val CHANNEL_ID = "skt_bubble"
        private const val NOTIF_ID = 4711
    }

    private lateinit var wm: WindowManager
    private var root: FrameLayout? = null
    private var bubble: ImageView? = null
    private var panel: LinearLayout? = null
    private var input: EditText? = null
    private var params: WindowManager.LayoutParams? = null
    private var expanded = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        if (root == null) {
            startForegroundSafely()
            showBubble()
        }
        running = true
        return START_STICKY
    }

    // ── BILDIRIM (foreground service zorunlulugu) ──────────────────────
    private fun startForegroundSafely() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Asistan Baloncuğu",
                    NotificationManager.IMPORTANCE_MIN
                )
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
            val open = PendingIntent.getActivity(
                this, 0,
                packageManager.getLaunchIntentForPackage(packageName),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            // Kanalli yapici API 26+; minSdk 23 oldugu icin ayrilmali.
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val n: Notification = builder
                .setContentTitle("Depo Asistanı hazır")
                .setContentText("Baloncuğa dokunarak soru sorabilirsin")
                .setSmallIcon(android.R.drawable.ic_menu_help)
                .setContentIntent(open)
                .setOngoing(true)
                .build()
            startForeground(NOTIF_ID, n)
        } catch (_: Exception) {
            // Bildirim kurulamazsa servis yine de calismaya devam etsin.
        }
    }

    // ── OVERLAY ────────────────────────────────────────────────────────
    private fun dp(v: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

    @Suppress("DEPRECATION", "ClickableViewAccessibility")
    private fun showBubble() {
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            WindowManager.LayoutParams.TYPE_PHONE

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // Kapaliyken odak ALMAZ (altindaki uygulama normal calisir);
            // sohbet acilinca klavye icin odak verilir.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            android.graphics.PixelFormat.TRANSLUCENT
        )
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = dp(8)
        lp.y = dp(220)
        params = lp

        val container = FrameLayout(this)
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL

        // ── SOHBET KUTUSU (baslangicta gizli) ──
        panel = buildPanel()
        panel?.visibility = View.GONE
        col.addView(panel)

        // ── BALONCUK ──
        val b = ImageView(this)
        b.setImageResource(android.R.drawable.ic_menu_search)
        b.setColorFilter(Color.BLACK)
        val bg = GradientDrawable()
        bg.shape = GradientDrawable.OVAL
        bg.setColor(Color.parseColor("#4DD0C7")) // uygulamanin turkuazi
        bg.setStroke(dp(2), Color.parseColor("#FFFFFF"))
        b.background = bg
        b.setPadding(dp(12), dp(12), dp(12), dp(12))
        val bl = LinearLayout.LayoutParams(dp(52), dp(52))
        bl.topMargin = dp(6)
        b.layoutParams = bl
        bubble = b
        col.addView(b)

        container.addView(col)
        root = container

        attachDragAndTap(b, lp)
        try {
            wm.addView(container, lp)
        } catch (_: Exception) {
            stopSelf()
        }
    }

    /** Kucuk sohbet kutusu: baslik + giris alani + gonder. */
    private fun buildPanel(): LinearLayout {
        val p = LinearLayout(this)
        p.orientation = LinearLayout.VERTICAL
        val pbg = GradientDrawable()
        pbg.cornerRadius = dp(16).toFloat()
        pbg.setColor(Color.parseColor("#F21C1F2A"))
        pbg.setStroke(dp(1), Color.parseColor("#3AFFFFFF"))
        p.background = pbg
        p.setPadding(dp(12), dp(10), dp(12), dp(10))
        val plp = LinearLayout.LayoutParams(dp(260), LinearLayout.LayoutParams.WRAP_CONTENT)
        p.layoutParams = plp

        val title = TextView(this)
        title.text = "Depo Asistanı"
        title.setTextColor(Color.WHITE)
        title.textSize = 14f
        p.addView(title)

        val hint = TextView(this)
        hint.text = "Sor ya da işlem iste — uygulamada açılır"
        hint.setTextColor(Color.parseColor("#B0FFFFFF"))
        hint.textSize = 11f
        p.addView(hint)

        val e = EditText(this)
        e.hint = "Örn: pilavlık bulgur nerede?"
        e.setHintTextColor(Color.parseColor("#80FFFFFF"))
        e.setTextColor(Color.WHITE)
        e.textSize = 13f
        e.maxLines = 3
        e.imeOptions = EditorInfo.IME_ACTION_SEND
        e.setSingleLine(false)
        val ebg = GradientDrawable()
        ebg.cornerRadius = dp(10).toFloat()
        ebg.setColor(Color.parseColor("#33FFFFFF"))
        e.background = ebg
        e.setPadding(dp(10), dp(8), dp(10), dp(8))
        val elp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        elp.topMargin = dp(8)
        e.layoutParams = elp
        e.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendQuestion(e.text.toString())
                true
            } else false
        }
        e.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable?) {}
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
        })
        input = e
        p.addView(e)

        val send = TextView(this)
        send.text = "Gönder"
        send.setTextColor(Color.BLACK)
        send.textSize = 13f
        send.gravity = Gravity.CENTER
        val sbg = GradientDrawable()
        sbg.cornerRadius = dp(10).toFloat()
        sbg.setColor(Color.parseColor("#4DD0C7"))
        send.background = sbg
        send.setPadding(dp(10), dp(8), dp(10), dp(8))
        val slp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        slp.topMargin = dp(8)
        send.layoutParams = slp
        send.setOnClickListener { sendQuestion(input?.text?.toString() ?: "") }
        p.addView(send)

        return p
    }

    /** Soruyu uygulamaya iletir (uygulama kapaliysa acar). */
    private fun sendQuestion(text: String) {
        val q = text.trim()
        collapse()
        try {
            val i = packageManager.getLaunchIntentForPackage(packageName)
            i?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (q.isNotEmpty()) i?.putExtra(EXTRA_QUESTION, q)
            startActivity(i)
            input?.setText("")
        } catch (_: Exception) {
        }
    }

    private fun expand() {
        expanded = true
        panel?.visibility = View.VISIBLE
        // Klavye yazabilsin diye odagi ac (NOT_FOCUSABLE bayragini kaldir).
        val p = params
        if (p != null) {
            p.flags = p.flags and
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
        }
        try {
            wm.updateViewLayout(root, params)
        } catch (_: Exception) {
        }
        input?.requestFocus()
    }

    private fun collapse() {
        expanded = false
        panel?.visibility = View.GONE
        params?.flags = (params?.flags ?: 0) or
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        try {
            wm.updateViewLayout(root, params)
        } catch (_: Exception) {
        }
    }

    /** Suruklenebilirlik + dokunusla ac/kapa. */
    @Suppress("ClickableViewAccessibility")
    private fun attachDragAndTap(view: View, lp: WindowManager.LayoutParams) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false

        view.setOnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x
                    startY = lp.y
                    touchX = ev.rawX
                    touchY = ev.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (ev.rawX - touchX).toInt()
                    val dy = (ev.rawY - touchY).toInt()
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) moved = true
                    lp.x = startX + dx
                    lp.y = startY + dy
                    try {
                        wm.updateViewLayout(root, lp)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        if (expanded) collapse() else expand()
                    }
                    true
                }
                else -> false
            }
        }
    }

    override fun onDestroy() {
        running = false
        try {
            root?.let { wm.removeView(it) }
        } catch (_: Exception) {
        }
        root = null
        super.onDestroy()
    }
}
