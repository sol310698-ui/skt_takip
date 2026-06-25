package com.example.skt_takip

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
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

        // ── KRITIK: Bazi kurumsal uygulamalar view'larini
        // importantForAccessibility=no olarak isaretler; XML flag'i bazen
        // yetmez. serviceInfo'yu RUNTIME'da yeniden yazarak "onemsiz" sayilan
        // view'lari da, web/Flutter icerigini de okumayi GARANTILERIZ.
        // Boylece "erisilebilirlik servisi bu uygulamayi okuyamiyor" sorunu
        // (bos node agaci) cogunlukla cozulur.
        try {
            val info = serviceInfo ?: AccessibilityServiceInfo()
            info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            info.flags = info.flags or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            @Suppress("DEPRECATION")
            run {
                info.flags = info.flags or
                    AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY
            }
            info.notificationTimeout = 100
            serviceInfo = info
        } catch (e: Exception) {
            Log.w(TAG, "serviceInfo runtime ayari basarisiz: ${e.message}")
        }

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
        try {
            lastEventTime = System.currentTimeMillis()
            val pkg = event?.packageName?.toString()
            lastPackage = pkg

            // Kendi uygulamamizi OKUMA — kendi ekranindaki metinler yanlis
            // veri uretmesin. Sadece debug paketi gosterilir, veri alinmaz.
            if (pkg == OWN_PACKAGE) {
                return
            }

            // ── DOGRU PENCEREYI SEC ──
            // MIUI/Xiaomi'de ve yuzen baloncuk (overlay) ekrandayken
            // rootInActiveWindow bazen BALONUN penceresini "aktif" sayar ve
            // bos doner. TalkBack metni okuyabiliyorsa metin AGAÇTA VARDIR;
            // sorun yanlis pencere secimidir. Bu yuzden aktif pencereye
            // korkormez guvenmek yerine, tum pencereler arasindan EN COK
            // metin iceren (kendi paketimiz/baloncuk haric) uygulama
            // penceresini seciyoruz.
            val texts = ArrayList<String>()
            val best = bestContentRoot()
            if (best != null) {
                try {
                    collectTexts(best, texts, 150)
                } finally {
                    best.recycle()
                }
            }
            // Yine de bos kaldiysa son care: aktif pencere.
            if (texts.isEmpty()) {
                val root = rootInActiveWindow
                if (root != null) {
                    try {
                        collectTexts(root, texts, 150)
                    } finally {
                        root.recycle()
                    }
                }
            }

            lastLabelFound = texts.any { it.contains(PRICE_LABEL, ignoreCase = true) }
            lastScreenSample = texts.take(8).joinToString(" | ")

            // Fiyat: once etikete yakin aramayi dene (dogru pencere agacindan).
            val priceRoot = bestContentRoot()
            if (priceRoot != null) {
                try {
                    val price = findPriceNearLabel(priceRoot, PRICE_LABEL)
                    if (price != null) {
                        lastSystemPriceRaw = price.second
                        lastSystemPrice = price.first
                    }
                } finally {
                    priceRoot.recycle()
                }
            }
            // Etikete yakin bulunamadiysa: toplanan metinlerden fiyat cikar.
            if (lastSystemPrice == null && lastLabelFound) {
                priceFromTexts(texts)?.let {
                    lastSystemPriceRaw = it.second
                    lastSystemPrice = it.first
                }
            }

            // Barkod + stok kodu + urun adi: tum ekrandan cikar.
            extractProductInfo(texts)

        } catch (e: Exception) {
            Log.e(TAG, "Ekran taranirken hata: ${e.message}")
        }
    }

    /**
     * Tum erisilebilir pencereler arasindan, OKUNMASI gereken gercek
     * uygulama penceresinin kok dugumunu dondurur.
     *
     *  - Kendi paketimizi (OWN_PACKAGE) atlar — kendi baloncuk/UI metinleri
     *    yanlis veri uretmesin.
     *  - En cok metin dugumu iceren pencereyi secer; boylece bos sistem
     *    katmanlari veya tek-iconlu overlay yerine asil icerik penceresi
     *    gelir.
     *  - Cagiran taraf donen node'u recycle ETMELIDIR.
     */
    private fun bestContentRoot(): AccessibilityNodeInfo? {
        var best: AccessibilityNodeInfo? = null
        var bestCount = -1
        try {
            for (w in windows) {
                val r = w?.root ?: continue
                val pkg = r.packageName?.toString()
                if (pkg == OWN_PACKAGE) {
                    r.recycle()
                    continue
                }
                val count = countTextNodes(r, 0, 200)
                if (count > bestCount) {
                    best?.recycle()
                    best = r
                    bestCount = count
                } else {
                    r.recycle()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "bestContentRoot basarisiz: ${e.message}")
        }
        // Hic pencere bulunamadiysa aktif pencereye dus.
        return best ?: rootInActiveWindow
    }

    /** Bir agactaki (metni/contentDescription'i olan) dugum sayisini sayar. */
    private fun countTextNodes(
        node: AccessibilityNodeInfo,
        acc: Int,
        cap: Int
    ): Int {
        if (acc >= cap) return acc
        var c = acc
        val t = node.text?.toString()
        val cd = node.contentDescription?.toString()
        if (!t.isNullOrBlank() || !cd.isNullOrBlank()) c++
        for (i in 0 until node.childCount) {
            if (c >= cap) break
            val child = node.getChild(i) ?: continue
            c = countTextNodes(child, c, cap)
        }
        return c
    }
    private fun priceFromTexts(texts: List<String>): Pair<Double, String>? {
        for (t in texts) {
            if (t.contains(PRICE_LABEL, ignoreCase = true)) continue
            val p = parsePrice(t) ?: continue
            // Cok kucuk/anlamsiz degerleri ele (orn. tek hane 0.0 gibi).
            return Pair(p, t)
        }
        return null
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
        // Bazi uygulamalar gorunur metni 'text' yerine 'contentDescription'
        // alaninda tutar (ozellikle custom/Compose view'lar). Onu da topla.
        val cd = node.contentDescription?.toString()
        if (!cd.isNullOrBlank() && cd != t) out.add(cd.trim())
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
