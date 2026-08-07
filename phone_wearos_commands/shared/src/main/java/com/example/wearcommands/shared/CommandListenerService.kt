package com.example.wearcommands.shared

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Karsi cihazdan gelen komut mesajlarini dinleyen servis.
 *
 * Hem telefon hem de saat uygulamasi bu servisi kendi AndroidManifest'inde
 * `com.google.android.gms.wearable.MESSAGE_RECEIVED` intent-filter'i ile
 * kaydeder. Google Play Services, `/command` yoluna bir mesaj geldiginde bu
 * servisi otomatik olarak baslatir; uygulama kapali olsa bile calisir.
 *
 * Gelen komutlar:
 *  - [CommandBus] uzerinden ekrandaki Activity'ye iletilir,
 *  - PING ise otomatik olarak PONG cevabi gonderilir,
 *  - VIBRATE ise cihaz titretilir.
 */
class CommandListenerService : WearableListenerService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != CommandProtocol.PATH_COMMAND) {
            return
        }

        val command = String(event.data, Charsets.UTF_8)

        // Ekrandaki Activity'ye ilet.
        CommandBus.publish(command)

        // Bazi komutlara otomatik tepki ver.
        when (command) {
            CommandProtocol.CMD_PING -> respondPong()
            CommandProtocol.CMD_VIBRATE -> vibrate()
        }
    }

    private fun respondPong() {
        scope.launch {
            runCatching { CommandSender.send(applicationContext, CommandProtocol.CMD_PONG) }
        }
    }

    private fun vibrate() {
        val vibrator = resolveVibrator() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(400)
        }
    }

    private fun resolveVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(VibratorManager::class.java)
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
