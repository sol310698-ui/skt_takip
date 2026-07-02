package com.example.skt_takip

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.os.Bundle
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

    /** Otomatik barkod girisi ilerlemesi icin dinleyici. */
    interface AutoEntryListener {
        fun onProgress(done: Int, total: Int, lastBarcode: String, ok: Boolean)
        fun onFinished(done: Int, total: Int)
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
        //  OTOMATIK BARKOD GIRISI (sirket uygulamasina)
        // ────────────────────────────────────────────────────────────────
        //  Kullanicinin ELLE yaptigi tekrarli isi hizlandirir: verilen barkod
        //  listesini sirasiyla sirket uygulamasinin giris kutusuna yazip
        //  onay (Ekle) butonuna basar. Fiyat kontrolunden bagimsizdir.
        // ════════════════════════════════════════════════════════════════
        const val TARGET_PACKAGE = "com.anpagross.work"

        @Volatile
        var autoRunning: Boolean = false
            private set

        @Volatile
        private var autoListener: AutoEntryListener? = null

        fun setAutoListener(l: AutoEntryListener?) {
            autoListener = l
        }

        // Girilecek barkodlar ve ilerleme durumu.
        private val autoQueue = ArrayList<String>()

        @Volatile
        var autoInfo: String = ""
            private set

        fun requestStartAuto(barcodes: List<String>, delayMs: Long) {
            instance?.startAutoEntry(barcodes, delayMs)
        }

        fun requestStopAuto() {
            instance?.stopAutoEntry()
        }

        /**
         * Event beklemeden, dis bir tetikleyiciyle "su anki ekrani hemen oku"
         * taramasini calistirir. Su an hicbir yerden cagrilmiyor; ileride
         * "aninda yenile" ihtiyaci icin altyapida tutuluyor.
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
        stopAutoEntry()
        instance = null
    }

    // ════════════════════════════════════════════════════════════════════
    //  OTOMATIK BARKOD GIRISI MOTORU
    // ────────────────────────────────────────────────────────────────────
    //  Her barkod icin SIRA: (1) giris kutusunu bul, (2) kutuya barkodu YAZ
    //  (ACTION_SET_TEXT), (3) kisa bekle, (4) onay/Ekle butonunu bul,
    //  (5) butona TIKLA (ACTION_CLICK), (6) ~1sn bekle, sonraki barkoda gec.
    //  ONCE METIN, SONRA TIKLAMA — bos kutuyla onaya basmamak icin sart.
    // ════════════════════════════════════════════════════════════════════

    private var autoDelayMs: Long = 1000
    private var autoIndex = 0
    private val autoHandler = Handler(Looper.getMainLooper())
    private var autoRunnable: Runnable? = null

    fun startAutoEntry(barcodes: List<String>, delayMs: Long) {
        if (autoRunning) return
        if (barcodes.isEmpty()) return
        autoQueue.clear()
        autoQueue.addAll(barcodes)
        autoDelayMs = delayMs.coerceAtLeast(300)
        autoIndex = 0
        autoRunning = true
        autoInfo = "Otomatik giris basladi (${autoQueue.size} barkod)"

        autoRunnable = object : Runnable {
            override fun run() {
                if (!autoRunning) return
                if (autoIndex >= autoQueue.size) {
                    finishAuto()
                    return
                }
                val barcode = autoQueue[autoIndex]
                val ok = enterOneBarcode(barcode)
                autoIndex++

                autoInfo = "Giris ${autoIndex}/${autoQueue.size}: $barcode " +
                    if (ok) "✓" else "✗ (kutu/buton bulunamadi)"
                val l = autoListener
                mainHandler.post {
                    l?.onProgress(autoIndex, autoQueue.size, barcode, ok)
                }

                if (autoIndex >= autoQueue.size) {
                    finishAuto()
                } else {
                    autoHandler.postDelayed(this, autoDelayMs)
                }
            }
        }
        // Ilk girisi kisa gecikmeyle baslat (kullanici sirket ekranina donsun).
        autoHandler.postDelayed(autoRunnable!!, 500)
    }

    fun stopAutoEntry() {
        autoRunning = false
        autoRunnable?.let { autoHandler.removeCallbacks(it) }
        autoRunnable = null
    }

    private fun finishAuto() {
        val done = autoIndex
        val total = autoQueue.size
        stopAutoEntry()
        autoInfo = "Otomatik giris bitti: $done/$total"
        val l = autoListener
        mainHandler.post { l?.onFinished(done, total) }
    }

    /**
     * Tek bir barkodu girer: ONCE kutuya yazar, SONRA onay butonuna tiklar.
     * Basari (kutu bulundu + yazildi + buton tiklandi) durumunda true doner.
     */
    private fun enterOneBarcode(barcode: String): Boolean {
        try {
            // Sirket penceresinin kokunu al.
            val root = companyRoot() ?: run {
                autoInfo = "SIRKET EKRANI YOK"
                return false
            }

            // ── 1) GIRIS KUTUSUNU BUL ──
            val editNode = findEditableNode(root)
            if (editNode == null) {
                root.recycle()
                autoInfo = "Giris kutusu bulunamadi"
                return false
            }

            // ── 2) KUTUYA BARKODU YAZ + DOGRULA (gerekirse tekrar dene) ──
            // ACTION_SET_TEXT bazen metni tam oturtamaz. Yazdiktan sonra
            // kutuyu tekrar okuyup barkodun gercekten girildigini DOGRULARIZ;
            // olmadiysa 3 kez tekrar deneriz. Bu, "metin oturmadan butona
            // basma" sorununu (elle eklemeden calismama) onler.
            var writeOk = false
            for (attempt in 0 until 3) {
                val args = Bundle()
                args.putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    barcode
                )
                editNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                Thread.sleep(200)

                // Kutuyu YENIDEN oku, icindeki metni dogrula.
                val checkRoot = companyRoot()
                val checkNode = if (checkRoot != null) findEditableNode(checkRoot) else null
                val currentText = checkNode?.text?.toString() ?: ""
                checkNode?.recycle()
                checkRoot?.recycle()

                if (currentText.contains(barcode)) {
                    writeOk = true
                    break
                }
                // Oturmadi — kisa bekle, tekrar dene.
                Thread.sleep(150)
            }
            editNode.recycle()

            if (!writeOk) {
                root.recycle()
                autoInfo = "Kutuya yazilamadi (dogrulanamadi): $barcode"
                return false
            }

            // ── 3) BEKLE (butonun aktiflesmesi/UI'in oturmasi icin) ──
            Thread.sleep(300)

            // ── 4) ONAY/EKLE BUTONUNU BUL ──
            // Kokten yeniden al (yazma sonrasi agac degismis olabilir).
            val root2 = companyRoot() ?: root
            val addBtn = findAddButton(root2)
            if (addBtn == null) {
                root2.recycle()
                if (root2 !== root) root.recycle()
                autoInfo = "Ekle butonu bulunamadi"
                return false
            }

            // ── 5) BUTONA TIKLA — once ACTION_CLICK, olmazsa GERCEK DOKUNMA ──
            // Bazi custom butonlar ACTION_CLICK'e yanit vermiyor. O durumda
            // butonun ekran koordinatina gercek parmak dokunusu (dispatchGesture)
            // gonderiyoruz. Boylece hangi yontem calisiyorsa o kullanilir.
            var clicked = addBtn.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            if (!clicked) {
                val clickable = firstClickableAncestor(addBtn)
                if (clickable != null) {
                    clicked = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    clickable.recycle()
                }
            }

            // ACTION_CLICK ise yaramadiysa: butonun konumuna gercek dokunma.
            if (!clicked) {
                val rect = android.graphics.Rect()
                addBtn.getBoundsInScreen(rect)
                if (rect.width() > 0 && rect.height() > 0) {
                    clicked = tapAt(rect.exactCenterX(), rect.exactCenterY())
                    autoInfo = if (clicked) "Gercek dokunma ile tiklandi"
                               else "Tiklama basarisiz (her iki yontem)"
                }
            }

            addBtn.recycle()
            root2.recycle()
            if (root2 !== root) root.recycle()

            return clicked
        } catch (e: Exception) {
            autoInfo = "HATA: ${e.message}"
            Log.e(TAG, "enterOneBarcode hata: ${e.message}")
            return false
        }
    }

    /**
     * Ekranda (x,y) noktasina gercek bir DOKUNMA gonderir (dispatchGesture).
     * ACTION_CLICK islemeyen custom butonlarda calisir.
     */
    private fun tapAt(x: Float, y: Float): Boolean {
        return try {
            val path = android.graphics.Path().apply { moveTo(x, y) }
            val stroke = GestureDescription.StrokeDescription(path, 0, 50)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()
            dispatchGesture(gesture, null, null)
        } catch (e: Exception) {
            Log.e(TAG, "tapAt hata: ${e.message}")
            false
        }
    }

    /** Sirket uygulamasinin pencere kokunu dondurur (pakete kilitli). */
    private fun companyRoot(): AccessibilityNodeInfo? {
        try {
            for (w in windows) {
                val wr = w?.root ?: continue
                if (wr.packageName?.toString() == TARGET_PACKAGE) {
                    return wr
                }
                wr.recycle()
            }
        } catch (_: Exception) {}
        return null
    }

    /** Agacta DUZENLENEBILIR (EditText benzeri) ilk dugumu bulur. */
    private fun findEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable) return AccessibilityNodeInfo.obtain(node)
        // className ile de dene (bazi alanlar isEditable vermez).
        val cls = node.className?.toString() ?: ""
        if (cls.contains("EditText", ignoreCase = true) && node.isVisibleToUser) {
            return AccessibilityNodeInfo.obtain(node)
        }
        for (i in 0 until node.childCount) {
            val found = findEditableNode(node.getChild(i))
            if (found != null) return found
        }
        return null
    }

    /**
     * Onay/Ekle butonunu bulur. Once metnine gore ("Ekle", "Kaydet", "Onayla",
     * "Ekle" ikonu), yoksa giris kutusunun yanindaki tiklanabilir dugumu
     * arar.
     */
    private fun findAddButton(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        val text = (node.text?.toString() ?: "").trim()
        val desc = (node.contentDescription?.toString() ?: "").trim()
        val combined = "$text $desc".uppercase()
        val isAddLabel = combined.contains("EKLE") ||
            combined.contains("KAYDET") ||
            combined.contains("ONAYLA") ||
            combined.contains("ONAY") ||
            combined.contains("TAMAM") ||
            combined.contains("GIRIS") ||
            combined.contains("EKLE ")
        if (isAddLabel && (node.isClickable || firstClickableAncestorExists(node))) {
            return AccessibilityNodeInfo.obtain(node)
        }
        for (i in 0 until node.childCount) {
            val found = findAddButton(node.getChild(i))
            if (found != null) return found
        }
        return null
    }

    private fun firstClickableAncestorExists(node: AccessibilityNodeInfo): Boolean {
        var p = node.parent
        var depth = 0
        while (p != null && depth < 6) {
            if (p.isClickable) {
                p.recycle()
                return true
            }
            val next = p.parent
            p.recycle()
            p = next
            depth++
        }
        return false
    }

    private fun firstClickableAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var p = node.parent
        var depth = 0
        while (p != null && depth < 6) {
            if (p.isClickable) return p
            val next = p.parent
            p.recycle()
            p = next
            depth++
        }
        return null
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
