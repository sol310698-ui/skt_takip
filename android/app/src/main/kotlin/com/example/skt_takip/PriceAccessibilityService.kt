package com.example.skt_takip

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.regex.Pattern

/**
 * ════════════════════════════════════════════════════════════════════
 *  FIYAT KONTROL ASISTANI — SISTEM FIYATI OKUMA SERVISI
 * ────────────────────────────────────────────────────────────────────
 *  Bu servis sadece TEK bir is yapar: en son gorulen "Sistem Fiyati"
 *  etiketinin YANINDAKI/ALTINDAKI fiyat degerini hafizada (RAM) tutar.
 *
 *  Kullanici Ayarlar > Erisilebilirlik'ten bu servisi ELLE acmadikca
 *  CALISMAZ (Android bunu otomatik vermez, kotuye kullanim riski
 *  yuzunden bilerek zorlastirilmistir).
 *
 *  Gizlilik notu: SADECE "Sistem Fiyati" metni iceren ekranlarda fiyat
 *  arar; baska hicbir veri toplamaz, hicbir yere gondermez, sadece
 *  bellekte tutar. Kalici kayit YOK.
 *
 *  NOT (skt_takip entegrasyonu): Bu servis SKT Takip'in ana
 *  islevlerinden (SKT/barkod/mesai/alarm) tamamen BAGIMSIZDIR. Sadece
 *  "Fiyat Kontrol" ekrani aciksa anlam ifade eder. Servis kapaliyken
 *  uygulamanin geri kalani normal calismaya devam eder.
 * ════════════════════════════════════════════════════════════════════
 */
class PriceAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "PriceA11yService"

        // Kendi uygulamamizin paketi — bunu OKUMAYIZ (kendi ekranindaki
        // "Sistem fiyati 9,95" gibi test metinleri yanlis veri yaratmasin).
        private const val OWN_PACKAGE = "com.example.skt_takip"

        // "Sistem Fiyati" etiketinin aranacagi metin.
        private const val PRICE_LABEL = "Sistem Fiyatı"

        // Fiyat formatini yakalayan regex: "9.95", "9,95", "9.95 ₺",
        // "9,95TL" gibi varyasyonlari kapsar. Ondalik kismi 1-2 hane.
        private val PRICE_PATTERN: Pattern = Pattern.compile(
            "(\\d{1,6}[.,]\\d{1,2})"
        )

        // 8-13 haneli barkod (EAN-13/EAN-8 vb.)
        private val BARCODE_PATTERN: Pattern = Pattern.compile("\\b(\\d{8,13})\\b")

        // Son okunan sistem fiyati, Flutter tarafinin (MethodChannel ile)
        // erisebilmesi icin statik tutulur (ayni process icinde, basit ve
        // yeterli).
        @Volatile
        var lastSystemPrice: Double? = null
            private set

        @Volatile
        var lastSystemPriceRaw: String? = null
            private set

        // ── Denetim Formu'ndan cikarilan urun bilgileri ──
        @Volatile
        var lastBarcode: String? = null
            private set

        @Volatile
        var lastStockCode: String? = null
            private set

        @Volatile
        var lastProductName: String? = null
            private set

        @Volatile
        var serviceRunning: Boolean = false
            private set

        // ── DEBUG alanlari (Fiyat Kontrol ekranindaki tani gostergesi icin) ──
        @Volatile
        var lastEventTime: Long = 0L
            private set

        @Volatile
        var lastPackage: String? = null
            private set

        @Volatile
        var lastLabelFound: Boolean = false
            private set

        // Son taranan ekrandan ornek metinler (tani icin; "Sistem Fiyati"
        // gercekte ekranda nasil yaziyor gormek icin cok faydali).
        @Volatile
        var lastScreenSample: String? = null
            private set

        /** Flutter "yeni tarama" baslattiginda eski degeri temizlemek icin. */
        fun clearLastPrice() {
            lastSystemPrice = null
            lastSystemPriceRaw = null
            lastBarcode = null
            lastStockCode = null
            lastProductName = null
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceRunning = true
        Log.i(TAG, "Servis baglandi, ekran taramasi basliyor.")
    }

    override fun onInterrupt() {
        Log.w(TAG, "Servis kesintiye ugradi.")
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceRunning = false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val root = rootInActiveWindow ?: return
        try {
            lastEventTime = System.currentTimeMillis()
            val pkg = event?.packageName?.toString()
            lastPackage = pkg

            // Kendi uygulamamizi OKUMA — kendi ekranindaki metinler yanlis
            // veri uretmesin. Sadece debug paketi gosterilir, veri alinmaz.
            if (pkg == OWN_PACKAGE) {
                return
            }

            // Ekrandaki tum metinleri topla.
            val texts = ArrayList<String>()
            collectTexts(root, texts, 80)
            lastLabelFound = texts.any { it.contains(PRICE_LABEL, ignoreCase = true) }
            lastScreenSample = texts.take(8).joinToString(" | ")

            // Fiyat: "Sistem Fiyati" etiketine yakin olani al.
            val price = findPriceNearLabel(root, PRICE_LABEL)
            if (price != null) {
                lastSystemPriceRaw = price.second
                lastSystemPrice = price.first
            }

            // Barkod + stok kodu + urun adi: tum ekrandan cikar.
            extractProductInfo(texts)

        } catch (e: Exception) {
            Log.e(TAG, "Ekran taranirken hata: ${e.message}")
        } finally {
            root.recycle()
        }
    }

    /**
     * Denetim Formu ekranindaki metinlerden barkod, stok kodu ve urun
     * adini cikarir.
     *
     * KONUMSAL yaklasim (uzunluk DEGIL): Denetim Formu'nda urun barkodu
     * her zaman USTTE, stok kodu hemen ALTINDA gosterilir. Ekran agaci
     * yukaridan asagi sirayla tarandigi icin, karsilastigimiz SAYISAL
     * kodlardan:
     *   - 1. sirada gelen  -> BARKOD
     *   - 2. sirada gelen  -> STOK KODU
     * Boylece "8 haneli yabanci barkod" veya "5 haneli kisa stok kodu"
     * gibi durumlar uzunluga takilmadan dogru ayrilir.
     *
     * Sayisal kod adayi: en az 4 haneli, sadece rakam (bosluk/tire temizli).
     * Fiyat (ondalikli, "9,95") koddan sayilmaz; cesit no gibi cok kisa
     * (<4) degerler de elenir.
     */
    private fun extractProductInfo(texts: List<String>) {
        // Bu ekranda "Sistem Fiyati" yoksa urun ekrani degildir, dokunma.
        if (!texts.any { it.contains(PRICE_LABEL, ignoreCase = true) }) return

        // Ekran sirasinda gorulen sayisal kodlar (barkod/stok adaylari).
        val codes = ArrayList<String>()
        var productName: String? = null
        var longestNameLen = 0
        // Barkod/stok kodu "Sistem Fiyati" etiketinin USTUNDE yer alir.
        // Fiyattan SONRAKI sayilar (tarih, ID, kampanya vb.) karismasin diye
        // etiketi gorunce kod toplamayi durdururuz.
        var reachedPriceLabel = false

        for (t in texts) {
            val clean = t.trim()
            if (clean.isEmpty()) continue

            if (clean.contains(PRICE_LABEL, ignoreCase = true)) {
                reachedPriceLabel = true
            }

            // Ondalikli fiyat (9,95 / 9.95) bir KOD degildir; atla.
            if (clean.matches(".*\\d[.,]\\d.*".toRegex()) &&
                clean.replace("[^0-9]".toRegex(), "").length <= 6) {
                // kucuk ondalikli sayi (fiyat) -> kod degil
                continue
            }

            val digitsOnly = clean.replace("[\\s-]".toRegex(), "")
            // Tamamen rakamsa, yeterince uzunsa (>=4) ve henuz fiyat
            // etiketine gelmediysek bir koddur (barkod/stok ustte olur).
            if (!reachedPriceLabel && digitsOnly.matches("\\d{4,14}".toRegex())) {
                if (!codes.contains(digitsOnly)) codes.add(digitsOnly)
                continue
            }

            // Urun adi adayi: en az 5 karakter, harf icermeli, etiket/fiyat
            // metni olmamali. (En uzun aday secilir.)
            if (clean.length >= 5 &&
                clean.any { it.isLetter() } &&
                !clean.contains(PRICE_LABEL, ignoreCase = true) &&
                !clean.contains("₺") &&
                clean.length > longestNameLen
            ) {
                longestNameLen = clean.length
                productName = clean
            }
        }

        // KONUMSAL ayrim: ilk kod = barkod, ikinci kod = stok kodu.
        val barcode = codes.getOrNull(0)
        val stockCode = codes.getOrNull(1)

        if (barcode != null) lastBarcode = barcode
        if (stockCode != null) lastStockCode = stockCode
        if (productName != null) lastProductName = productName
    }

    /** DEBUG: agactaki metinleri toplar (en fazla [max] adet). */
    private fun collectTexts(
        node: AccessibilityNodeInfo,
        out: ArrayList<String>,
        max: Int
    ) {
        if (out.size >= max) return
        val t = node.text?.toString()
        if (!t.isNullOrBlank()) out.add(t.trim())
        for (i in 0 until node.childCount) {
            if (out.size >= max) return
            node.getChild(i)?.let { collectTexts(it, out, max) }
        }
    }

    /**
     * Ekran agacinda [labelText] icerigine sahip dugumu bulur, sonra o
     * dugumun YAKININDAKI fiyat formatli metni arar.
     * Donus: Pair(fiyatDegeri, hamMetin) veya bulunamazsa null.
     */
    private fun findPriceNearLabel(
        root: AccessibilityNodeInfo,
        labelText: String
    ): Pair<Double, String>? {
        val labelNode = findNodeByText(root, labelText) ?: return null

        // 1) Ebeveynin cocuklari arasinda, etiketten SONRAKI dugumlerde ara.
        val parent = labelNode.parent
        if (parent != null) {
            var foundLabel = false
            for (i in 0 until parent.childCount) {
                val child = parent.getChild(i) ?: continue
                if (!foundLabel) {
                    if (nodeContainsText(child, labelText)) foundLabel = true
                    continue
                }
                val price = extractPrice(child)
                if (price != null) return price
            }
        }

        // 2) Bulunamadiysa: grandparent alt agacinda ilk fiyatli metni ara.
        val grandparent = parent?.parent
        if (grandparent != null) {
            val price = searchSubtreeForPrice(grandparent, excludeText = labelText)
            if (price != null) return price
        }

        return null
    }

    private fun searchSubtreeForPrice(
        node: AccessibilityNodeInfo,
        excludeText: String
    ): Pair<Double, String>? {
        val text = node.text?.toString()
        if (text != null && !text.contains(excludeText)) {
            val price = parsePrice(text)
            if (price != null) return Pair(price, text)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = searchSubtreeForPrice(child, excludeText)
            if (result != null) return result
        }
        return null
    }

    private fun extractPrice(node: AccessibilityNodeInfo): Pair<Double, String>? {
        val text = node.text?.toString() ?: return null
        val price = parsePrice(text) ?: return null
        return Pair(price, text)
    }

    private fun parsePrice(raw: String): Double? {
        val matcher = PRICE_PATTERN.matcher(raw)
        if (!matcher.find()) return null
        val numStr = matcher.group(1)?.replace(',', '.') ?: return null
        return numStr.toDoubleOrNull()
    }

    private fun findNodeByText(
        root: AccessibilityNodeInfo,
        text: String
    ): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            if (nodeContainsText(node, text)) return node
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    private fun nodeContainsText(node: AccessibilityNodeInfo, text: String): Boolean {
        val nodeText = node.text?.toString() ?: return false
        return nodeText.contains(text, ignoreCase = true)
    }
}
