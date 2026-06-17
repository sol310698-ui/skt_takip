package com.example.skt_takip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Kalici (persistent) on plan servisi.
 *
 * Amac: Uygulama "son kullanilanlar"dan kaydirilsa (swipe-kill) bile
 * surecin canli kalmasi ve alarmlarin tetiklenebilmesi. START_STICKY ile
 * sistem servisi oldurse bile yeniden baslatir.
 *
 * NOT: Bu, force-stop'u (Ayarlar > Zorla Durdur) asamaz - o Android'in
 * kesin kuralidir. Ama cogu swipe-kill senaryosunda sureci ayakta tutar.
 *
 * Maliyet: Surekli gorunen bir bildirim ve bir miktar pil kullanimi.
 */
class KeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "skt_keepalive"
        private const val NOTIF_ID = 424242
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        startForeground(NOTIF_ID, buildNotification())
        // START_STICKY: sistem servisi oldurse de yeniden baslat.
        return START_STICKY
    }

    // Kullanici uygulamayi recent'ten kaydirinca da servisi yeniden ayaga
    // kaldirmaya calis (bazi cihazlarda etkili).
    override fun onTaskRemoved(rootIntent: Intent?) {
        val restart = Intent(applicationContext, KeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(restart)
        } else {
            startService(restart)
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Alarm Koruma",
                    // DUSUK onem: sessiz, titresimsiz, kullaniciyi rahatsiz etmez.
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Alarmlarin guvenilir calismasi icin uygulamayi aktif tutar"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(): Notification {
        // Bildirime tiklayinca uygulamayi ac.
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("SKT Takip aktif")
            .setContentText("Alarmlar guvenilir calissin diye arka planda calisiyor")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pi)
            .setOngoing(true) // kullanici kaydirip atamaz
            .build()
    }
}
