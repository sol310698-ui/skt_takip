package com.example.wearcommands.shared

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/**
 * Bagli tum cihazlara (telefon -> saat ya da saat -> telefon) komut gonderir.
 *
 * Ayni [CommandProtocol.PATH_COMMAND] yolu ve UTF-8 byte payload'u kullanilir.
 */
object CommandSender {

    /**
     * [command] komutunu su an bagli olan tum node'lara gonderir.
     *
     * @return komutu basariyla teslim edilen node sayisi.
     * @throws Exception ag/baglanti hatalarinda cagiran taraf yakalamalidir.
     */
    suspend fun send(context: Context, command: String): Int {
        val appContext = context.applicationContext
        val nodeClient = Wearable.getNodeClient(appContext)
        val messageClient = Wearable.getMessageClient(appContext)

        val payload = command.toByteArray(Charsets.UTF_8)
        val nodes = nodeClient.connectedNodes.await()

        var delivered = 0
        for (node in nodes) {
            messageClient
                .sendMessage(node.id, CommandProtocol.PATH_COMMAND, payload)
                .await()
            delivered++
        }
        return delivered
    }
}
