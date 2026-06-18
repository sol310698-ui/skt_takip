package com.example.skt_takip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Cihaz yeniden baslatildiginda (reboot) tetiklenir.
 *
 * Android AlarmManager alarmlari reboot'ta UNUTUR. "alarm" paketinin kendi
 * BootReceiver'i da kayitlidir; ancak bazi OEM cihazlarda (Samsung/Xiaomi/Oppo)
 * paketin reschedule mekanizmasi tek basina guvenilir olmayabilir.
 *
 * Bu alici BOOT_COMPLETED'i yakalar ve kullanici "kalici servis"i (KeepAlive)
 * actiysa onu yeniden baslatir. KeepAlive bir foreground servis oldugundan
 * Flutter surecini ayaga kaldirir; main() icindeki _ensureWeeklyAlarms /
 * _ensureSktDisposalAlarm calisir ve TUM alarmlar reboot sonrasi yeniden
 * kurulur. Boylece "telefon gece yeniden baslayinca sabah alarmi calmadi"
 * sorununun onune gecilir.
 *
 * KeepAlive kapaliysa: en azindan yayini yakalamak uygulama surecini
 * "stopped" durumundan cikarir ve "alarm" paketinin kendi reschedule
 * mekanizmasinin calismasina izin verir.
 *
 * Not: Kullanici uygulamayi force-stop ettiyse (Ayarlar > Zorla Durdur)
 * Android hicbir yayini ulastirmaz; bu Android'in kesin guvenlik kuralidir.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        // Kullanici kalici servisi actiysa reboot sonrasi yeniden baslat.
        // MainActivity start/stopKeepAlive sirasinda bu bayragi yazar.
        try {
            val prefs = context.getSharedPreferences(
                "skt_native_prefs", Context.MODE_PRIVATE
            )
            val keepAlive = prefs.getBoolean("keep_alive_on", false)
            if (keepAlive) {
                val svc = Intent(context, KeepAliveService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(svc)
                } else {
                    context.startService(svc)
                }
            }
        } catch (_: Exception) {
            // sessizce gec; en kotu durumda paketin kendi mekanizmasi devrede.
        }
    }
}
