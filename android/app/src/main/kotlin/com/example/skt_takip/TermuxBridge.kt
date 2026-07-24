package com.example.skt_takip

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicInteger

/**
 * ════════════════════════════════════════════════════════════════════
 *  TERMUX KOPRUSU (v160)
 * ────────────────────────────────────────────────────────────────────
 *  Asistanin telefonda GERCEK KABUK erisimi. Termux'un RunCommandService
 *  servisine intent gonderilir; Termux sonucu, bizim verdigimiz
 *  PendingIntent'i tetikleyerek "result" bundle'i icinde geri yollar.
 *
 *  ONKOSULLAR (kullanici bir kez yapar):
 *    1) Termux kurulu olmali
 *    2) ~/.termux/termux.properties -> allow-external-apps = true
 *    3) Termux'a RUN_COMMAND izni verilmis olmali
 *
 *  GUVENLIK: Komut suzgeci Flutter tarafinda (TermuxService) uygulanir;
 *  burasi yalnizca tasima katmanidir.
 * ════════════════════════════════════════════════════════════════════
 */
object TermuxBridge {

    private const val TERMUX_PKG = "com.termux"
    private const val RUN_SERVICE = "com.termux.app.RunCommandService"
    private const val ACTION_RUN = "com.termux.RUN_COMMAND"

    private const val EXTRA_PATH = "com.termux.RUN_COMMAND_PATH"
    private const val EXTRA_ARGS = "com.termux.RUN_COMMAND_ARGUMENTS"
    private const val EXTRA_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR"
    private const val EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND"
    private const val EXTRA_SESSION_ACTION =
        "com.termux.RUN_COMMAND_SESSION_ACTION"
    private const val EXTRA_PENDING_INTENT =
        "com.termux.RUN_COMMAND_PENDING_INTENT"

    /** Termux sonucu bu anahtarli bundle icinde doner. */
    private const val RESULT_BUNDLE = "result"

    private val seq = AtomicInteger(1000)

    fun isInstalled(ctx: Context): Boolean {
        return try {
            ctx.packageManager.getLaunchIntentForPackage(TERMUX_PKG) != null
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Komutu Termux'ta calistirir; sonucu [onResult] ile dondurur:
     * ok / stdout / stderr / exitCode / error
     */
    fun run(
        ctx: Context,
        command: String,
        workdir: String?,
        timeoutMs: Long,
        onResult: (Map<String, Any?>) -> Unit
    ) {
        if (!isInstalled(ctx)) {
            onResult(fail("Termux kurulu değil."))
            return
        }

        val id = seq.incrementAndGet()
        val action = ctx.packageName + ".TERMUX_RESULT." + id
        val main = Handler(Looper.getMainLooper())
        var finished = false

        // Termux'un tetikleyecegi gecici alici.
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (finished) return
                finished = true
                try {
                    ctx.unregisterReceiver(this)
                } catch (_: Exception) {
                }
                val b: Bundle? = intent?.getBundleExtra(RESULT_BUNDLE)
                val err = b?.getString("errmsg")
                val code = b?.getInt("exitCode", -1) ?: -1
                onResult(
                    mapOf(
                        "ok" to (code == 0 && err.isNullOrBlank()),
                        "stdout" to (b?.getString("stdout") ?: ""),
                        "stderr" to (b?.getString("stderr") ?: ""),
                        "exitCode" to code,
                        "error" to (if (err.isNullOrBlank()) null else err)
                    )
                )
            }
        }

        try {
            val filter = IntentFilter(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ctx.registerReceiver(
                    receiver, filter, Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                ctx.registerReceiver(receiver, filter)
            }

            val callback = Intent(action).setPackage(ctx.packageName)
            val pi = PendingIntent.getBroadcast(
                ctx, id, callback,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            val i = Intent()
            i.setClassName(TERMUX_PKG, RUN_SERVICE)
            i.action = ACTION_RUN
            // Login shell: PATH ve pkg ortami tam olsun.
            i.putExtra(EXTRA_PATH, "/data/data/com.termux/files/usr/bin/bash")
            i.putExtra(EXTRA_ARGS, arrayOf("-lc", command))
            if (!workdir.isNullOrBlank()) i.putExtra(EXTRA_WORKDIR, workdir)
            i.putExtra(EXTRA_BACKGROUND, true)
            i.putExtra(EXTRA_SESSION_ACTION, "0")
            i.putExtra(EXTRA_PENDING_INTENT, pi)
            ctx.startService(i)
        } catch (e: Exception) {
            if (!finished) {
                finished = true
                try {
                    ctx.unregisterReceiver(receiver)
                } catch (_: Exception) {
                }
                onResult(
                    fail(
                        "Termux komutu başlatılamadı: " + e.message +
                            ". termux.properties içinde allow-external-apps=true " +
                            "olmalı ve RUN_COMMAND izni verilmeli."
                    )
                )
            }
            return
        }

        main.postDelayed({
            if (!finished) {
                finished = true
                try {
                    ctx.unregisterReceiver(receiver)
                } catch (_: Exception) {
                }
                onResult(
                    fail("Termux yanıt vermedi (zaman aşımı). İzin verilmemiş olabilir.")
                )
            }
        }, if (timeoutMs <= 0) 30000 else timeoutMs)
    }

    private fun fail(msg: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "stdout" to "",
        "stderr" to "",
        "exitCode" to -1,
        "error" to msg
    )
}
