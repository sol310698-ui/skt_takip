package com.example.skt_takip

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
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

    /** Kategori taramada toplanan her urun icin tetiklenir. */
    interface ProductCollectedListener {
        fun onProductCollected(barcode: String, productName: String, stockCode: String?)
        fun onScanFinished(total: Int)
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

        // Bu servisin CALISAN tek ornegine (instance) erisim icin. Disaridan
        // (ornegin Flutter'dan bir "manuel yenile" istegiyle) event beklemeden
        // ZORLA okuma tetiklemek istenirse forceRescanNow() bu referansi
        // kullanir. Servis kapaliysa null'dir; o durumda forceRescanNow()
        // guvenle hicbir sey yapmaz.
        @Volatile
        private var instance: PriceAccessibilityService? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun setListener(l: PriceUpdateListener?) {
            listener = l
        }

        // ════════════════════════════════════════════════════════════════
        //  KATEGORI TARAMA (LISTE MODU + OTOMATIK KAYDIRMA)
        // ────────────────────────────────────────────────────────────────
        //  Sirket uygulamasinin "Denetim Urunler" liste ekraninda, gorunen
        //  urunleri (BUYUK HARF ad + barkod) okur, otomatik asagi kaydirir,
        //  liste bitene kadar tekrarlar. Toplanan urunler collectListener'a
        //  iletilir. Fiyat kontrolunden TAMAMEN bagimsizdir.
        // ════════════════════════════════════════════════════════════════

        // Sirket uygulamasinin paketi — SADECE bunu okuruz (kendi ekranimiz,
        // launcher, smartcapture, status bar yanlislikla okunmasin).
        const val TARGET_PACKAGE = "com.anpagross.work"

        @Volatile
        var scanning: Boolean = false
            private set

        // Toplanan urun dinleyicisi (MainActivity -> Flutter'a aktarir).
        @Volatile
        private var collectListener: ProductCollectedListener? = null

        fun setCollectListener(l: ProductCollectedListener?) {
            collectListener = l
        }

        // Tarama boyunca gonderilen barkodlar (ayni urun kaydirmada tekrar
        // gorununce iki kez gonderilmesin).
        private val sentBarcodes = HashSet<String>()

        // Tarama durumu (tani panelinde gosterilir).
        @Volatile
        var lastScanInfo: String? = null
            private set

        // Tarama sirasindaki HER turun tanisi (kullanici sirket ekranindayken
        // ne gorundu — sonradan SKT'ye donunce incelemek icin). Tavuk-yumurta
        // sorununu cozer: tarama sirasinda ekrani goremiyoruz, bu yuzden
        // gecmisi biriktirip bitince gosteririz.
        @Volatile
        var scanHistory: String = ""
            private set

        fun appendScanHistory(line: String) {
            // Son 15 turu tut (cok uzamasin).
            val lines = (scanHistory + "\n" + line).trim().split("\n")
            scanHistory = lines.takeLast(15).joinToString("\n")
        }

        fun clearScanHistory() {
            scanHistory = ""
        }

        /** Flutter'dan tarama baslatma istegi. */
        fun requestStartScan() {
            instance?.startCategoryScan()
        }

        /** Flutter'dan tarama durdurma istegi. */
        fun requestStopScan() {
            instance?.stopCategoryScan()
        }

        /**
         * Event beklemeden, AKTIF olarak "su an ekranda ne var" taramasini
         * hemen calistirir.
         *
         * NEDEN GEREKLI: onAccessibilityEvent SADECE bir DEGISIKLIK event'i
         * geldiginde calisir; Android event'leri notificationTimeout kadar
         * gecikmeli yollar. Bazi senaryolarda (ornegin uygulamalar arasi
         * cok hizli gecis) bu pasif bekleme yetersiz kalabilir. Bu fonksiyon,
         * dis bir tetikleyici (ornegin Flutter tarafindan "su anki ekrani
         * hemen oku" istegi) geldiginde event'ten bagimsiz olarak ayni
         * tarama mantigini calistirir.
         *
         * NOT: Yuzen baloncuk ozelligi (eskiden bu fonksiyonun tek
         * cagiranıydı) kullanici talebiyle tamamen kaldirildi. Fonksiyon,
         * ileride benzer bir "aninda yenile" ihtiyaci dogarsa diye
         * altyapida tutulmaktadir; su an icin hicbir yerden cagrilmamaktadir.
         */
        fun forceRescanNow() {
            instance?.scanNow()
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
            "scanInfo" to lastScanInfo,
            "scanHistory" to scanHistory,
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceRunning = true
        instance = this

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
        stopCategoryScan()
        instance = null
    }

    // ════════════════════════════════════════════════════════════════════
    //  KATEGORI TARAMA MOTORU
    // ════════════════════════════════════════════════════════════════════

    // Tarama dongusu durumu.
    private var scanRound = 0
    private var noNewCount = 0
    private val scanHandler = Handler(Looper.getMainLooper())
    private var scanRunnable: Runnable? = null

    /**
     * Taramayi baslatir. Sirket uygulamasinin liste ekrani ON PLANDA
     * olmalidir (kullanici once "Denetim Urunler"i acar, sonra tetikler).
     */
    fun startCategoryScan() {
        if (scanning) return
        scanning = true
        scanRound = 0
        noNewCount = 0
        sentBarcodes.clear()
        clearScanHistory()
        lastScanInfo = "Tarama basladi..."

        // Ilk okumayi hemen yap, sonra dongu (oku -> kaydir -> bekle -> oku).
        scanRunnable = object : Runnable {
            override fun run() {
                if (!scanning) return

                val before = sentBarcodes.size
                readVisibleProducts()
                val after = sentBarcodes.size
                val newCount = after - before
                scanRound++

                lastScanInfo = "Tur $scanRound | toplam ${sentBarcodes.size} urun " +
                    "(+$newCount yeni)"

                // Durma kosulu: 2 tur ust uste YENI urun gelmediyse liste
                // bitmistir.
                if (newCount == 0) {
                    noNewCount++
                    if (noNewCount >= 2) {
                        finishScan()
                        return
                    }
                } else {
                    noNewCount = 0
                }

                // Guvenlik: cok uzun tarama olmasin (maks 60 tur ~ cok uzun
                // liste bile biter).
                if (scanRound >= 60) {
                    finishScan()
                    return
                }

                // Bir ekran asagi kaydir, sonra tekrar oku.
                scrollDownOnce()
                scanHandler.postDelayed(this, 900)
            }
        }
        // Ilk turu kisa gecikmeyle baslat (kullanici ekrana donsun).
        scanHandler.postDelayed(scanRunnable!!, 300)
    }

    fun stopCategoryScan() {
        scanning = false
        scanRunnable?.let { scanHandler.removeCallbacks(it) }
        scanRunnable = null
    }

    private fun finishScan() {
        val total = sentBarcodes.size
        stopCategoryScan()
        lastScanInfo = "Tarama bitti — toplam $total urun"
        val l = collectListener
        mainHandler.post { l?.onScanFinished(total) }
    }

    /**
     * SADECE sirket uygulamasinin liste ekranindan, o an gorunen urunleri
     * okur ve YENI olanlari collectListener'a gonderir.
     *
     * Liste karti yapisi (kanitlanmis gercek ekran):
     *   FORA Y.ZEYTIN KOKTEYL 400GR *12 KVN (PLT-90)   <- ad (BUYUK HARF)
     *   24   8695608230014                             <- adet rozeti + barkod
     *
     * Algoritma: yukaridan asagi tara; BUYUK-HARF urun adi bul; ondan
     * SONRA gelen ilk 12-14 haneli sayi o urunun barkodu. (ad, barkod)
     * ciftini, daha once gonderilmediyse, yolla.
     */
    private fun readVisibleProducts() {
        try {
            // Sirket penceresini bul (pakete kilitli).
            var root: AccessibilityNodeInfo? = null
            var winDump = StringBuilder()
            try {
                for (w in windows) {
                    val wr = w?.root ?: continue
                    val wp = wr.packageName?.toString() ?: "?"
                    winDump.append("$wp ")
                    if (wp == TARGET_PACKAGE) {
                        root = wr
                        break
                    }
                    wr.recycle()
                }
            } catch (_: Exception) {}

            if (root == null) {
                lastScanInfo = "SIRKET PENCERESI YOK. Pencereler: $winDump\n" +
                    "(Beklenen: $TARGET_PACKAGE)"
                appendScanHistory("T$scanRound: PENCERE YOK [$winDump]")
                return
            }

            val texts = ArrayList<String>()
            try {
                collectTexts(root, texts, 400)
            } finally {
                root.recycle()
            }

            // TANI: okunan ilk satirlar + kac urun adi/barkod bulundu.
            val sample = texts.take(12).joinToString(" | ")
            var nameCount = 0
            var bcCount = 0
            for (t in texts) {
                val c = t.trim()
                if (Regex("\\d{12,14}").containsMatchIn(c.replace("[\\s-]".toRegex(), ""))) bcCount++
                else if (isProductNameLine(c)) nameCount++
            }

            val l = collectListener
            if (l == null) {
                lastScanInfo = "LISTENER YOK | okunan=${texts.size} satir\n$sample"
                return
            }

            var pendingName: String? = null
            var addedNow = 0
            for (raw in texts) {
                val clean = raw.trim()
                if (clean.isEmpty()) continue

                val bcMatch = Regex("\\d{12,14}")
                    .find(clean.replace("[\\s-]".toRegex(), ""))
                if (bcMatch != null) {
                    val bc = bcMatch.value
                    val name = pendingName
                    pendingName = null
                    if (name != null && !sentBarcodes.contains(bc)) {
                        sentBarcodes.add(bc)
                        addedNow++
                        mainHandler.post {
                            l.onProductCollected(bc, name, null)
                        }
                    }
                    continue
                }

                if (isProductNameLine(clean)) {
                    pendingName = clean
                }
            }
            lastScanInfo = "okundu=${texts.size} | ad adayi=$nameCount | " +
                "barkod=$bcCount | bu turda eklenen=$addedNow | " +
                "toplam=${sentBarcodes.size}\n$sample"
            appendScanHistory(
                "T$scanRound: okundu=${texts.size} ad=$nameCount bc=$bcCount " +
                "yeni=$addedNow | ${sample.take(60)}")
        } catch (e: Exception) {
            lastScanInfo = "HATA: ${e.message}"
            Log.e(TAG, "readVisibleProducts hata: ${e.message}")
        }
    }

    /**
     * Urun adi satiri mi? Urun adlari: HEP BUYUK HARF, uzun (>=8), sekme/
     * baslik/etiket DEGIL, icinde 12-14 haneli barkod YOK.
     */
    private fun isProductNameLine(line: String): Boolean {
        val clean = line.trim()
        if (clean.length < 8) return false
        if (!clean.any { it.isLetter() }) return false
        if (Regex("\\d{12,14}").containsMatchIn(clean.replace("[\\s-]".toRegex(), ""))) {
            return false
        }
        val letters = clean.filter { it.isLetter() }
        if (letters.isEmpty()) return false
        val upperRatio = letters.count { it.isUpperCase() }.toDouble() / letters.length
        if (upperRatio < 0.8) return false
        if (isScanNoise(clean)) return false
        return true
    }

    /** Sekme / baslik / etiket gurultusu mu? */
    private fun isScanNoise(line: String): Boolean {
        val u = line.uppercase().trim()
        val containsNoise = listOf(
            "LOJISTIK", "SEVIYE", "KOLI", "SATINALMA", "ACIK SIP", "AÇIK SIP",
            "STOK:", "MÜŞTERI", "MUSTERI", "GÖRSEL HAZIRLAN", "GORSEL HAZIRLAN",
            "SEKME", "SEKTÖR", "SEKTOR", "OKUTULMAYAN", "OKUTULAN", "ARA...",
            "DENETIM", "DENETİM"
        )
        if (containsNoise.any { u.contains(it) }) return true
        val exactNoise = setOf(
            "HAREKET", "ANALIZ", "SATIS", "SATIŞ", "STOK", "OKUTMA", "BILDIRIM",
            "BİLDİRİM", "YORUMLAR", "MARKA", "REYON", "ADET", "BACK"
        )
        if (u in exactNoise) return true
        val storeKeywords = listOf("AVM", "MAĞAZA", "MAGAZA", "ŞUBE", "SUBE", "STORE", "PLAZA")
        if (storeKeywords.any { u.contains(it) }) return true
        return false
    }

    /**
     * Ekrani bir sayfa asagi kaydirir (dispatchGesture ile).
     * Ekranin ortasindan yukari dogru hizli bir swipe = liste asagi kayar.
     */
    private fun scrollDownOnce() {
        try {
            val dm = resources.displayMetrics
            val w = dm.widthPixels
            val h = dm.heightPixels
            val x = w / 2f
            val startY = h * 0.72f   // alt-orta
            val endY = h * 0.28f     // ust-orta (yukari swipe -> liste asagi)

            val path = android.graphics.Path().apply {
                moveTo(x, startY)
                lineTo(x, endY)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, 300)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            dispatchGesture(gesture, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "scrollDownOnce hata: ${e.message}")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        lastEventTime = System.currentTimeMillis()
        lastPackage = pkg
        // Kendi uygulamamizi OKUMA — kendi ekranindaki metinler yanlis
        // veri uretmesin.
        if (pkg == OWN_PACKAGE) return
        scanNow()
    }

    /**
     * Asil tarama mantigi: dogru pencereyi sec, metinleri topla, fiyati ve
     * urun bilgilerini cikar, degisiklik varsa Flutter'a haber ver.
     *
     * Bu fonksiyon IKI YERDEN cagrilabilir:
     *  1) onAccessibilityEvent — PASIF: Android bir ekran degisikligi
     *     event'i yolladiginda otomatik calisir. (Bu, su an icin TEK
     *     gercek tetikleyicidir.)
     *  2) forceRescanNow (companion'dan) — AKTIF: event beklemeden disaridan
     *     manuel tetiklenebilir. Su an hicbir yerden cagrilmamaktadir;
     *     ileride benzer bir "aninda yenile" ihtiyaci dogarsa diye
     *     altyapida tutulmaktadir.
     *
     * Iki cagiran da AYNI mantigi calistirir; davranis FARKLILASMAZ, sadece
     * tetiklenme ZAMANLAMASI farklidir.
     */
    private fun scanNow() {
        // Bu taramanin basladigi andaki nesli sabitle. Tarama (kok secimi +
        // metin toplama + fiyat arama) bir kac milisaniye surebilir; bu sure
        // icinde Flutter "yeni tarama" isteyip clearLastPrice() cagirmis
        // olabilir. O durumda bu taramanin SONUCU artik gecersizdir.
        val myGeneration = generation
        try {
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
        try {
            // ── ONCELIK 1: TYPE_APPLICATION tipindeki (gercek uygulama)
            // pencereler arasindan en cok metin icereni sec. Status bar /
            // bildirim panelleri TYPE_SYSTEM'dir; onlar ürün icermez ama
            // bazen birkac node (saat/pil/sinyal) ile "en cok"muş gibi
            // gorunup yanlis seciliyordu. Bu yuzden APP pencerelerini
            // sistem pencerelerinden KESIN olarak ayiriyoruz.
            var bestApp: AccessibilityNodeInfo? = null
            var bestAppCount = -1
            var bestOther: AccessibilityNodeInfo? = null
            var bestOtherCount = -1

            for (w in windows) {
                val r = w?.root ?: continue
                val pkg = r.packageName?.toString()
                if (pkg == OWN_PACKAGE) {
                    r.recycle()
                    continue
                }
                // Sistem UI (status bar / bildirim golgesi) — ürün penceresi
                // DEGIL. Okuma kapsamindan cikar.
                val isSystemUi = pkg == "com.android.systemui"
                val isAppWindow =
                    w.type == AccessibilityWindowInfo.TYPE_APPLICATION && !isSystemUi
                val count = countTextNodes(r, 0, 200)

                if (isAppWindow) {
                    if (count > bestAppCount) {
                        bestApp?.recycle()
                        bestApp = r
                        bestAppCount = count
                    } else r.recycle()
                } else if (!isSystemUi) {
                    // APP olmayan ama systemui de olmayan (ör. IME yok sayilir
                    // ama bazi uygulamalar TYPE_? kullanir) — yedek olarak tut.
                    if (count > bestOtherCount) {
                        bestOther?.recycle()
                        bestOther = r
                        bestOtherCount = count
                    } else r.recycle()
                } else {
                    r.recycle()
                }
            }

            // Gercek uygulama penceresi varsa ONU dondur; yoksa yedek.
            return when {
                bestApp != null && bestAppCount > 0 -> {
                    bestOther?.recycle()
                    bestApp
                }
                bestOther != null -> {
                    bestApp?.recycle()
                    bestOther
                }
                else -> {
                    bestApp?.recycle()
                    bestOther?.recycle()
                    null
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "bestContentRoot basarisiz: ${e.message}")
        }
        return null
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
        // Kod GORULMEDEN once gecen TUM metin satirlari, sirayla.
        // Gercek urun adi bunlarin SONUNCUSUDUR (barkoda en yakin olan),
        // BASKASI DEGIL. Form basligi ("Denetim Formu") ve sube/magaza adi
        // ("BJK FULYA AVM") da bu listeye girer ama onlar ilk siralarda
        // kalir; gercek urun adi varsa o satirlarin ALTINDA, barkoddan
        // hemen once gelir.
        val candidateLines = ArrayList<String>()
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

            // Henuz ilk koda (barkoda) ulasilmadiysa ve bu satir gercek bir
            // metin satiriysa (harf icerir, etiket/fiyat metni degil) aday
            // listesine ekle. SIRALAMA korunur — listenin SONU barkoda en
            // yakin olandir.
            if (!reachedPriceLabel &&
                codes.isEmpty() &&
                clean.length >= 5 &&
                clean.any { it.isLetter() } &&
                !clean.contains(PRICE_LABEL, ignoreCase = true) &&
                !clean.contains("₺")
            ) {
                candidateLines.add(clean)
            }
        }

        // ── URUN ADI SECIMI ──
        // v2 — KOK NEDEN DUZELTMESI: Eskiden "en uzun metin" sezgisi
        // kullaniliyordu. Bu, "Denetim Formu" / "BJK FULYA AVM" gibi SABIT
        // form basligi ve sube adi satirlarinin (ozellikle henuz hicbir
        // urun okutulmamisken, formun BOS/baslangic halinde) gercek urun
        // adi olarak yanlislikla secilmesine yol aciyordu — bu satirlar da
        // harf icerip yeterince uzun olabiliyordu.
        //
        // Artik tek kural: gercek urun adi, BARKOD KODUNDAN HEMEN ONCEKI
        // metin satiridir (candidateLines listesinin SONUNCU elemani).
        // Boylece "Denetim Formu" / sube adi gibi ustteki sabit satirlar,
        // varsa altlarinda gercek bir urun adi oldugunda otomatik elenir
        // (listede ONCEKI siraya duserler, secilmezler). Eger ekranda
        // GERCEKTEN hicbir urun adi yoksa (form henuz acilmis, urun
        // okutulmamis), candidateLines'da TEK sey form basligi/sube adi
        // kalir — bu durumda urun adini HICBIR SEKILDE KAYDETMEYIZ (asagidaki
        // bilinen-sabit-metin filtresi).
        var productName = candidateLines.lastOrNull()

        // Ek guvenlik: candidateLines'da SADECE bilinen sabit form/sube
        // metinleri varsa (yani barkoddan once baska hicbir gercek urun
        // satiri yoksa), bunlari urun adi olarak KABUL ETME. Bu, formun
        // "henuz urun okutulmadan once" tarandigi anlik durumun, kuyruga
        // hatali bir kayit eklemesini engeller.
        if (productName != null && isLikelyStaticFormLabel(productName)) {
            productName = null
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

    // Sirket uygulamasinin Denetim Formu ekraninda HER URUNDE/HER ACILISTA
    // AYNI KALAN, urune ozel olmayan sabit basliklar. Bunlar bir urun adi
    // OLAMAZ; "Denetim Formu" ekran basligidir, sube/magaza adlari ise
    // (ornegin "BJK FULYA AVM") formun ust kisminda sabit gosterilir ve
    // urun degistikce DEGISMEZ — gercek urun adinin tersine.
    //
    // NOT: Bu liste KAPALI bir kara liste degil, ek bir GUVENLIK AGIDIR.
    // Asil ayrim mekanizmasi konumsaldir (yukaridaki candidateLines
    // mantigi); bu liste sadece "form henuz bos/baslangic halinde" gibi
    // uc durumlarda son bir kontrol katmanidir.
    private val staticFormLabelPatterns = listOf(
        Regex("^denetim\\s*formu$", RegexOption.IGNORE_CASE),
        Regex("^kontrol\\s*formu$", RegexOption.IGNORE_CASE),
        Regex("^fiyat\\s*kontrol(u)?$", RegexOption.IGNORE_CASE),
        Regex("^urun\\s*denetim(i)?$", RegexOption.IGNORE_CASE),
    )

    private fun isLikelyStaticFormLabel(line: String): Boolean {
        val normalized = line.trim()
        if (staticFormLabelPatterns.any { it.matches(normalized) }) return true
        // AVM / magaza / sube adlari genelde TAMAMI BUYUK HARF, kisa (<=30
        // karakter) ve "AVM", "MAGAZA", "SUBE", "STORE" gibi kelimeler
        // icerir. Gercek urun adlari da buyuk harfli olabildigi icin SADECE
        // uzunluk/harf büyüklüğüne degil, bu anahtar kelimelere bakariz.
        val upper = normalized.uppercase()
        val storeKeywords = listOf("AVM", "MAĞAZA", "MAGAZA", "ŞUBE", "SUBE", "STORE", "MARKET MD", "PLAZA")
        if (storeKeywords.any { upper.contains(it) }) return true
        return false
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
