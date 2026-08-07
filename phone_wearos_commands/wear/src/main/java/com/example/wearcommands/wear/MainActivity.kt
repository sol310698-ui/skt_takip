package com.example.wearcommands.wear

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.example.wearcommands.shared.CommandBus
import com.example.wearcommands.shared.CommandProtocol
import com.example.wearcommands.shared.CommandSender
import com.example.wearcommands.wear.databinding.ActivityMainBinding
import kotlinx.coroutines.launch

/**
 * Saat uygulamasinin ana ekrani.
 *
 * Telefona komut gonderir (PING / VIBRATE / HELLO) ve telefondan gelen
 * komutlari [CommandBus] uzerinden dinleyip ekranda gosterir.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.pingButton.setOnClickListener { send(CommandProtocol.CMD_PING) }
        binding.vibrateButton.setOnClickListener { send(CommandProtocol.CMD_VIBRATE) }
        binding.helloButton.setOnClickListener { send(CommandProtocol.CMD_HELLO) }

        observeIncoming()
    }

    /** Telefondan gelen komutlari dinleyip ekrana yazar. */
    private fun observeIncoming() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                CommandBus.incoming.collect { command ->
                    binding.lastCommandText.text = "Gelen: $command"
                }
            }
        }
    }

    /** [command] komutunu bagli telefona gonderir. */
    private fun send(command: String) {
        lifecycleScope.launch {
            runCatching { CommandSender.send(applicationContext, command) }
                .onSuccess { count ->
                    if (count == 0) {
                        binding.lastCommandText.text = "Bagli telefon yok"
                    } else {
                        binding.lastCommandText.text = "Gonderildi: $command"
                    }
                }
                .onFailure { error ->
                    Toast.makeText(this@MainActivity, "Hata: ${error.message}", Toast.LENGTH_SHORT).show()
                }
        }
    }
}
