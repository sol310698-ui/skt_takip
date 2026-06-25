package com.example.skt_takip

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.os.Handler
import android.os.Looper
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
 *
 * ────────────────────────────────────────────────────────────────────
 *  v2 DEGISIKLIKLERI — kullanicinin bildirdigi iki hatanin koku icin:
 *
 *  HATA 1: "Sirket uygulamasindan geri donunce fiyati GEC okuyor."
 *    Eski mimaride Flutter tarafi native'i 600ms'lik Timer.periodic ile
 *    POLLUYORDU. En kotu durumda gercek okuma ile Flutter'in bunu
 *    GORMESI arasinda ~600ms+ gecikme oluyordu — "gec okuma" hissinin
 *    birebir sebebi buydu. Cozum: native taraf artik deger GERCEKTEN
 *    degistigi anda bir dinleyiciyi (PriceUpdateListener) tetikliyor;
 *    MainActivity bunu bir EventChannel'a baglayip Flutter'a aninda,
 *    push olarak iletiyor. Polling tamamen kaldirildi.
 *
 *  HATA 2 (alt nedeni): Baloncuga basinca/sirket uygulamasindan
 *  donuste eski/yanlis bir fiyatin ekranda bir an gorunmesi, ekran
 *  GECIS yarisindan (eski pencerenin son event'i yeni pencere render
 *  olmadan once islenmesi) kaynaklaniyordu. Cozum: NESIL SAYACI.
 *  clearLastPrice() her cagrildiginda bir sayac artar; o anda hala
 *  devam eden bir tarama biterse ISLEDIGI nesil ile GUNCEL nesli
 *  karsilastirir, farkliysa sonucu sessizce atar. Boylece bayat veri
 *  matematiksel olarak guncel veriyi ezemez.
 * ════════════════════════════════════════════════════════════════════
 */
class PriceAccessibilityService : AccessibilityService() {

    /** Native'den Flutter'a (EventChannel araciligiyla) anlik veri itmek icin. */
    interface PriceUpdateListener {
        fun onPriceUpdate()
    }

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

        // Bu deger her clearLastPrice() cagrisinda 1 artar. Halen suren bir
        // onAccessibilityEvent taramasi bittiginde nesli kontrol eder; nesil
        // degismisse (Flutter "yeni tarama" istemis) sonuc BAYAT sayilir ve
        // sessizce atilir. "Eski urunun fiyati yeni urunun ustune yaziliyor"
        // yarisini engelleyen tek mekanizma budur.
        @Volatile
        private var generation: Int = 0

        // MainActivity, EventChannel acildiginda kendini buraya kaydeder.
        // Kayitli degilse de statik alanlar MethodChannel ile okunabilir
        // (geriye donuk uyumluluk / fallback).
        @Volatile
        private var listener: PriceUpdateListener? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun setListener(l: PriceUpdateListener?) {
            listener = l
        }

        private fun notifyListener() {
            val l = listener ?: return
            // onAccessibilityEvent zaten ana thread'de calisir, ama
            // EventChannel.EventSink cagrilarinin HER ZAMAN ana thread'den
            // yapildigini garanti etmek ucuz ve guvenli bir savunmadir.
            mainHandler.post { l.onPriceUpdate() }
        }

        /** Flutter "yeni tarama" baslattiginda eski degeri temizlemek icin. */
        fun clearLastPrice() {
            generation++
            lastSystemPrice = null
            lastSystemPriceRaw = null
            lastBarcode = null
            lastStockCode = null
            lastProductName = null
            notifyListener()
        }

        fun snapshot(): Map<String, Any?> = mapOf(
            "price" to lastSystemPrice,
            "raw" to lastSystemPriceRaw,
            "barcode" to lastBarcode,
            "stockCode" to lastStockCode,
            "productName" to lastProductName,
        )

        fun debugSnapshot(): Map<String, Any?> = mapOf(
            "running" to serviceRunning,
            "price" to lastSystemPrice,
            "raw" to lastSystemPriceRaw,
            "barcode" to lastBarcode,
            "stockCode" to lastStockCode,
            "productName" to lastProductName,
            "lastEventTime" to lastEventTime,
            "lastPackage" to lastPackage,
            "labelFound" to lastLabelFound,
            "screenSample" to lastScreenSample,
        )
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
            // notificationTimeout DUSURULDU: 200ms -> 40ms. Bu deger
            // Android'in ardisik onAccessibilityEvent cagrilarini ne kadar
            // "debounce" edecegini belirler. 200ms, sirket uygulamasindan
            // geri donuste ekranin GERCEKTE guncellendigi an ile bizim olayi
            // ALMA animiz arasinda gozle gorulur bir gecikme yaratiyordu.
            // 40ms hala pil/CPU acisindan guvenli ama "ani" hissettirir.
            info.notificationTimeout = 40
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
        // Bu taramanin basladigi andaki nesli sabitle. Tarama (kok secimi +
        // metin toplama + fiyat arama) bir kac milisaniye surebilir; bu sure
        // icinde Flutter "yeni tarama" isteyip clearLastPrice() cagirmis
        // olabilir. O durumda bu taramanin SONUCU artik gecersizdir.
        val myGeneration = generation
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
            // bos doner. Bu yuzden aktif pencereye kor guvenmek yerine, tum
            // pencereler arasindan EN COK metin iceren (kendi paketimiz/
            // baloncuk haric) uygulama penceresini seciyoruz. TEK root
            // cekilip HEM metin toplama HEM fiyat aramasi AYNI agactan
            // yapiliyor — eskiden iki ayri bestContentRoot() cagrisi farkli
            // pencereler dondurebiliyordu, bu da TUTARSIZ sonuca yol
            // aciyordu (orn. metinlerde "Sistem Fiyati" bulunuyor ama fiyat
            // baska bir pencereden arandigi icin bulunamiyordu).
            val root = bestContentRoot() ?: rootInActiveWindow ?: return

            val texts = ArrayList<String>()
            var price: Pair<Double, String>? = null
            var labelFound: Boolean
            try {
                collectTexts(root, texts, 150)
                labelFound = texts.any { it.contains(PRICE_LABEL, ignoreCase = true) }

                price = findPriceNearLabel(root, PRICE_LABEL)
                if (price == null && labelFound) {
                    price = priceFromTexts(texts)
                }
            } finally {
                root.recycle()
            }

            // ── NESIL KONTROLU ──
            // Tarama bittiginde nesil hala basladigimiz nesilse sonucu yaz.
            // Degismisse (clearLastPrice cagrildi) bu tarama BAYAT sayilir
            // ve sessizce atilir; eski urunun verisi yenisinin ustune
            // YAZILMAZ.
            if (myGeneration != generation) {
                return
            }

            lastLabelFound = labelFound
            lastScreenSample = texts.take(8).joinToString(" | ")

            var changed = false
            if (price != null && price.first != lastSystemPrice) {
                lastSystemPriceRaw = price.second
                lastSystemPrice = price.first
                changed = true
            }

            // Barkod + stok kodu + urun adi: tum ekrandan cikar.
            if (extractProductInfo(texts)) {
                changed = true
            }

            if (changed) {
                notifyListener()
            }

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
        return best
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
            return Pair(p, t)
        }
        return null
    }

    /**
     * Denetim Formu ekranindaki metinlerden barkod, stok kodu ve urun
     * adini cikarir. Bir sey degistiyse true doner (degisim bildirimi
     * gondermek icin kullanilir).
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
    private fun extractProductInfo(texts: List<String>): Boolean {
        // Bu ekranda "Sistem Fiyati" yoksa urun ekrani degildir, dokunma.
        if (!texts.any { it.contains(PRICE_LABEL, ignoreCase = true) }) return false

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

        var changed = false
        if (barcode != null && barcode != lastBarcode) {
            lastBarcode = barcode
            changed = true
        }
        if (stockCode != null && stockCode != lastStockCode) {
            lastStockCode = stockCode
            changed = true
        }
        if (productName != null && productName != lastProductName) {
            lastProductName = productName
            changed = true
        }
        return changed
    }

    /** Agactaki metinleri toplar (en fazla [max] adet). */
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
