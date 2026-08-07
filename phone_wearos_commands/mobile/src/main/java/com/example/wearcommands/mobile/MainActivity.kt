package com.example.wearcommands.mobile

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.example.wearcommands.mobile.databinding.ActivityMainBinding
import com.example.wearcommands.shared.CommandBus
import com.example.wearcommands.shared.CommandProtocol
import com.example.wearcommands.shared.CommandSender
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Telefon uygulamasinin ana ekrani.
 *
 * Saate komut gonderir (PING / VIBRATE / ozel) ve saatten gelen komutlari
 * [CommandBus] uzerinden dinleyip ekrana yazar.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val log = StringBuilder()
    private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.pingButton.setOnClickListener { send(CommandProtocol.CMD_PING) }
        binding.vibrateButton.setOnClickListener { send(CommandProtocol.CMD_VIBRATE) }
        binding.customButton.setOnClickListener {
            val text = binding.commandInput.text.toString().trim().uppercase(Locale.getDefault())
            if (text.isEmpty()) {
                toast("Once bir komut yaz")
            } else {
                send(text)
            }
        }

        observeIncoming()
        refreshConnectedNodes()
    }

    /** Saatten gelen komutlari dinleyip loga ekler. */
    private fun observeIncoming() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                CommandBus.incoming.collect { command ->
                    appendLog("⬇️ GELEN: $command")
                }
            }
        }
    }

    /** [command] komutunu bagli saate gonderir. */
    private fun send(command: String) {
        lifecycleScope.launch {
            runCatching { CommandSender.send(applicationContext, command) }
                .onSuccess { count ->
                    if (count == 0) {
                        appendLog("⚠️ GONDERILEMEDI (bagli saat yok): $command")
                        toast("Bagli saat bulunamadi")
                    } else {
                        appendLog("⬆️ GONDERILDI ($count cihaz): $command")
                    }
                }
                .onFailure { error ->
                    appendLog("❌ HATA: ${error.message}")
                }
        }
    }

    /** Bagli saat var mi diye kontrol edip durum satirini gunceller. */
    private fun refreshConnectedNodes() {
        lifecycleScope.launch {
            runCatching {
                Wearable.getNodeClient(applicationContext).connectedNodes.await()
            }.onSuccess { nodes ->
                binding.statusText.text = if (nodes.isEmpty()) {
                    "Bagli saat yok. Wear OS emulatoru/saati eslesmis olmali."
                } else {
                    "Bagli saat(ler): " + nodes.joinToString { it.displayName }
                }
            }.onFailure {
                binding.statusText.text = "Baglanti durumu okunamadi: ${it.message}"
            }
        }
    }

    private fun appendLog(line: String) {
        log.insert(0, "[${timeFormat.format(Date())}] $line\n")
        binding.logText.text = log.toString()
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    override fun onResume() {
        super.onResume()
        refreshConnectedNodes()
    }
}
