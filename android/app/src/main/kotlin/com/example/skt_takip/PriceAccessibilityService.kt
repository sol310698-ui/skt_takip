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

    /**
     * VERI TOPLAMA MODU dinleyicisi. Sirket uygulamasinin URUN DETAY
     * ekraninda YENI bir urun goruldugunde (barkod + ad + stok kodu) bu
     * tetiklenir. Fiyat kontrol akisindan TAMAMEN BAGIMSIZDIR; sadece
     * "Veri Toplama" ekrani acikken aktiftir.
     */
    interface ProductCollectedListener {
        fun onProductCollected(barcode: String, productName: String, stockCode: String?)
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
        //  VERI TOPLAMA MODU (fiyat kontrolunden bagimsiz)
        // ────────────────────────────────────────────────────────────────
        //  collectMode = true iken, sirket uygulamasinin URUN DETAY
        //  ekranlari taranir ve her YENI urun (barkod + ad + stok kodu)
        //  collectListener'a iletilir. Flutter "Veri Toplama" ekrani bu
        //  modu acar/kapatir ve gelen urunleri barcode_directory'ye yazar.
        // ════════════════════════════════════════════════════════════════
        @Volatile
        var collectMode: Boolean = false
            private set

        @Volatile
        private var collectListener: ProductCollectedListener? = null

        // Ayni urunu pespese (ekran her kaydirildiginda) tekrar tekrar
        // gondermemek icin son toplanan barkodu hatirlar.
        @Volatile
        private var lastCollectedBarcode: String? = null

        fun setCollectMode(on: Boolean) {
            collectMode = on
            if (!on) lastCollectedBarcode = null
        }

        fun setCollectListener(l: ProductCollectedListener?) {
            collectListener = l
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
        instance = null
        setCollectMode(false)
        setCollectListener(null)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString()
        lastEventTime = System.currentTimeMillis()
        lastPackage = pkg
        // Kendi uygulamamizi OKUMA — kendi ekranindaki metinler yanlis
        // veri uretmesin. Sadece debug paketi gosterilir, veri alinmaz.
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
        // ── VERI TOPLAMA MODU ──
        // Bu mod aktifse (kullanici "Veri Toplama" ekranini acmissa), sirket
        // uygulamasinin URUN DETAY ekranindan barkod + ad + stok kodu cikarip
        // Flutter'a gonderir. Fiyat kontrol mantigindan TAMAMEN bagimsizdir;
        // mod aciksa fiyat tarama mantigi CALISMAZ (ikisi ayni anda gerekli
        // degil, ekranlar farkli).
        if (collectMode) {
            collectProductDetail()
            return
        }

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
     * VERI TOPLAMA MODU — sirket uygulamasinin URUN DETAY ekranindan
     * barkod + urun adi + stok kodu cikarir ve YENI bir urunse
     * collectListener'a iletir.
     *
     * Ekran yapisi (kullanicinin paylastigi ornek):
     *   - Baslikta magaza/personel (atlanir)
     *   - URUN ADI: buyuk baslik, orn. "BURCU RANCH SOS 290GR*10 (PLT-160)"
     *   - STOK KODU: kisa sayisal (orn. 44008471) — QR ikonu yaninda
     *   - BARKOD: uzun sayisal (orn. 8691573072970, 13 hane) — barkod ikonu
     *   - Fiyat, lojistik stok bilgileri, sekmeler (Hareket/Analiz/...)
     *
     * AYRIM KURALI (uzunluk tabanli — burada konumsal degil, cunku detay
     * ekraninda barkod ve stok kodu yan yana/ayri kartlarda olabilir ve
     * okuma sirasi degisebilir):
     *   - 12-13 haneli sayisal  -> BARKOD (EAN-13/EAN-8 standardi)
     *   - 6-9   haneli sayisal  -> STOK KODU
     * Boylece okuma sirasindan bagimsiz, dogru ayrim yapilir.
     *
     * URUN ADI: ekrandaki, sayisal olmayan, yeterince uzun (>=5 harf iceren)
     * ve magaza/sekme/sabit-etiket OLMAYAN ilk anlamli metin satiri.
     */
    private fun collectProductDetail() {
        try {
            val root = bestContentRoot() ?: rootInActiveWindow ?: return
            val texts = ArrayList<String>()
            try {
                collectTexts(root, texts, 200)
            } finally {
                root.recycle()
            }

            lastEventTime = System.currentTimeMillis()
            lastScreenSample = texts.take(10).joinToString(" | ")

            // ── BU BIR URUN DETAY EKRANI MI? ──
            // Detay ekraninda HEM uzun (barkod) HEM kisa (stok kodu) sayisal
            // kod bulunmali; ayrica detay ekranina ozgu sabit metinlerden en
            // az biri (Lojistik Stok / Koli Ici / Reyon vb.) gorunmeli.
            // Boylece liste/arama gibi baska ekranlardan yanlis veri
            // toplanmasi engellenir.
            val looksLikeDetail = texts.any { t ->
                val u = t.uppercase()
                u.contains("LOJISTIK STOK") || u.contains("KOLI") ||
                    u.contains("SEVIYE") || u.contains("REYON") ||
                    u.contains("SATINALMA") || u.contains("ADET")
            }
            if (!looksLikeDetail) return

            var barcode: String? = null
            var stockCode: String? = null
            var productName: String? = null
            var longestNameLen = 0

            for (raw in texts) {
                val clean = raw.trim()
                if (clean.isEmpty()) continue

                // Ondalikli sayi (fiyat: 36.95) — kod degildir, atla.
                if (clean.matches(".*\\d[.,]\\d.*".toRegex())) continue

                val digits = clean.replace("[\\s-]".toRegex(), "")
                if (digits.matches("\\d+".toRegex())) {
                    // Tamamen sayisal: barkod mu, stok kodu mu?
                    when (digits.length) {
                        in 12..13 -> if (barcode == null) barcode = digits
                        in 6..9 -> if (stockCode == null) stockCode = digits
                        // Diger uzunluklar (orn. lojistik stok adetleri:
                        // 2360, 840...) goz ardi edilir.
                    }
                    continue
                }

                // Urun adi adayi: harf icerir, >=5 karakter, sabit/magaza/
                // sekme metni degil. En uzun aday secilir (urun adlari
                // genelde en uzun metindir).
                if (clean.length >= 5 &&
                    clean.any { it.isLetter() } &&
                    !isCollectNoiseLabel(clean) &&
                    clean.length > longestNameLen
                ) {
                    longestNameLen = clean.length
                    productName = clean
                }
            }

            // Barkod ve urun adi ZORUNLU; stok kodu opsiyonel olabilir.
            if (barcode == null || productName == null) return

            // Ayni urunu pespese tekrar gondermeyi engelle (ekran her
            // kaydirildiginda event tetiklenir).
            if (barcode == lastCollectedBarcode) return
            lastCollectedBarcode = barcode

            val finalBarcode = barcode
            val finalName = productName
            val finalStock = stockCode
            val l = collectListener ?: return
            mainHandler.post {
                l.onProductCollected(finalBarcode, finalName, finalStock)
            }
        } catch (e: Exception) {
            Log.e(TAG, "collectProductDetail hata: ${e.message}")
        }
    }

    /**
     * Veri toplama modunda urun adi olarak SECILMEMESI gereken sabit/gurultu
     * metinleri (magaza adi, sekme baslıklari, sabit alan etiketleri).
     */
    private fun isCollectNoiseLabel(line: String): Boolean {
        val u = line.uppercase().trim()
        val noise = listOf(
            "LOJISTIK STOK", "MAX. SEVIYE", "MAX SEVIYE", "KOLI ICI", "KOLI İÇİ",
            "SATINALMA", "ACIK SIP", "AÇIK SIP", "HAREKET", "ANALIZ", "SATIS",
            "SATIŞ", "STOK", "OKUTMA", "BILDIRIM", "BİLDİRİM", "YORUMLAR",
            "MARKA", "REYON", "GORSEL HAZIRLANMAKTADIR", "GÖRSEL HAZIRLANMAKTADIR",
            "MUSTERI", "MÜŞTERİ", "AVM", "MAGAZA", "MAĞAZA", "SUBE", "ŞUBE"
        )
        // Tam esitlik veya icerme: magaza adlari (BJK FULYA AVM) ve sekmeler
        // genelde tam bu kelimelerden olusur ya da bunlari icerir.
        if (noise.any { u == it || u.contains(it) }) return true
        // Kisi adi gibi gorunenler (SAMET DEMIRAL): genelde 2-3 kelime, hepsi
        // harf, kisa. Urun adlari rakam/sembol (GR, *, parantez) icerir.
        // Urun adinda neredeyse her zaman rakam veya * vardir; hic rakam/
        // sembol icermeyen kisa metinler urun adi DEGILDIR.
        val hasDigitOrSymbol = line.any { it.isDigit() || it == '*' || it == '(' }
        if (!hasDigitOrSymbol && line.split("\\s+".toRegex()).size <= 3) {
            return true
        }
        return false
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
