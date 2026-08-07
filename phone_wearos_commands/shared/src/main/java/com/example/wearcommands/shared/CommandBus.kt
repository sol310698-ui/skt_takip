package com.example.wearcommands.shared

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Uygulama ici basit olay yolu (event bus).
 *
 * [CommandListenerService] karsi cihazdan bir komut aldiginda burayi tetikler;
 * ekrandaki Activity de bu akisi dinleyerek gelen komutlari gosterir. Servis ve
 * Activity ayni process icinde calistigi icin bu singleton nesne paylasilir.
 */
object CommandBus {

    /**
     * Gelen komutlar. Ekran kapaliyken yayilan komutlarin kaybolmamasi icin
     * kucuk bir tampon (buffer) tutulur.
     */
    private val _incoming = MutableSharedFlow<String>(
        replay = 0,
        extraBufferCapacity = 32
    )
    val incoming: SharedFlow<String> = _incoming.asSharedFlow()

    /** Karsi cihazdan gelen bir komutu dinleyicilere yayar. */
    fun publish(command: String) {
        _incoming.tryEmit(command)
    }
}
