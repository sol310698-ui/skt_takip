package com.example.skt_takip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Cihaz yeniden baslatildiginda (reboot) tetiklenir.
 *
 * Android AlarmManager alarmlari reboot'ta UNUTUR. "alarm" paketinin kendi
 * BootReceiver'i var ama bazi cihazlarda tetiklenmeyebiliyor; bu ek alici
 * BOOT_COMPLETED yayinini yakalayarak uygulama surecinin uyanmasini ve
 * paketin alarmlari yeniden kurmasini saglar.
 *
 * Not: Bu yalnizca REBOOT (telefon kapanip acilma) durumunu kapsar.
 * Kullanici uygulamayi "son kullanilanlar"dan kaydirip atarsa (force-stop),
 * Android guvenlik geregi hicbir yayini (bu dahil) o uygulamaya ulastirmaz.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            // Yayini yakalamak, uygulama surecini "stopped" durumundan cikarir
            // ve "alarm" paketinin kendi reschedule mekanizmasinin calismasina
            // izin verir. Ek bir is yapmaya gerek yok.
        }
    }
}
