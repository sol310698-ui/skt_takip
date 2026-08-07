package com.example.wearcommands.shared

/**
 * Telefon ve Wear OS saat arasinda gonderilen komutlarin ortak sozlesmesi.
 *
 * Iki uygulama da (mobile + wear) ayni [PATH_COMMAND] yolunu ve ayni komut
 * sabitlerini kullanir. Boylece bir tarafta gonderilen komut, diger tarafta
 * dogru sekilde cozumlenir.
 */
object CommandProtocol {

    /** Wearable MessageClient mesajlarinin gonderildigi yol. */
    const val PATH_COMMAND = "/command"

    // --- Ornek komutlar ---
    /** Karsi tarafin acik/bagli oldugunu test eder; cevabi [CMD_PONG]'dur. */
    const val CMD_PING = "PING"

    /** [CMD_PING]'e otomatik verilen cevap. */
    const val CMD_PONG = "PONG"

    /** Karsi cihazi titretir. */
    const val CMD_VIBRATE = "VIBRATE"

    /** Ornek bir kullanici tanimli komut (istege gore genisletilebilir). */
    const val CMD_HELLO = "HELLO"
}
