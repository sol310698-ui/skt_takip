package com.example.skt_takip

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOnLockScreen()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        showOnLockScreen()
    }

    // Alarm tam ekran intent'i ile acildiginda kilit ekraninin
    // UZERINDE gosterir + ekrani uyandirir. Kilidi ACMAZ (sifre sormaz).
    private fun showOnLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            // requestDismissKeyguard YOK — kilit acilmasin, sifre sorulmasin.
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                // FLAG_DISMISS_KEYGUARD YOK.
            )
        }
    }
}
