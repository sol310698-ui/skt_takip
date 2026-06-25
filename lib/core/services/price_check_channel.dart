import 'package:flutter/services.dart';

/// ════════════════════════════════════════════════════════════════════
///  FIYAT KONTROL — NATIVE KOPRU
/// ────────────────────────────────────────────────────────────────────
///  Erisilebilirlik servisi (sistem fiyatini okuyan) ile Flutter arasinda
///  kopru. Mevcut "skt_takip/fullscreen" kanalindan BAGIMSIZ, ayri kanal:
///  "skt_takip/price_check".
///
///  Bu sinif SADECE Fiyat Kontrol ekrani tarafindan kullanilir; uygulamanin
///  geri kalanini etkilemez.
///
/// ────────────────────────────────────────────────────────────────────
///  v2: CANLI VERI ARTIK STREAM (push), POLLING DEGIL.
///  Eskiden ekran her 600ms'de bir [getLastSystemPrice] cagirip native'i
///  SORGULUYORDU. Bu, "sirket uygulamasindan geri donunce fiyati gec
///  okuyor" sikayetinin birebir sebebiydi: en kotu durumda gercek okuma
///  ile ekranin bunu GORMESI arasinda ~600ms+ fark olusuyordu.
///
///  Artik [systemPriceStream] adinda tek, paylasilan bir broadcast stream
///  var. Native taraf (PriceAccessibilityService) deger GERCEKTEN
///  degistigi anda bu stream'e bir olay basar. Ekran sadece dinler;
///  hicbir Timer.periodic YOK.
/// ════════════════════════════════════════════════════════════════════
class PriceCheckChannel {
  static const _ch = MethodChannel('skt_takip/price_check');
  static const _eventCh = EventChannel('skt_takip/price_check_events');

  /// Native'den anlik (push) sistem fiyati/urun guncellemeleri.
  ///
  /// Birden fazla dinleyici (ornegin ekran + baloncuk renk mantigi) ayni
  /// stream'i guvenle paylasabilsin diye broadcast'tir. Native taraf yeni
  /// bir dinleyici baglandiginda mevcut son durumu da hemen gonderir, bu
  /// yuzden ekran acilir acilmaz (henuz hicbir degisiklik olmasa da) en az
  /// bir deger alinir.
  static final Stream<SystemPriceSnapshot> systemPriceStream = _eventCh
      .receiveBroadcastStream()
      .map((event) => SystemPriceSnapshot._fromMap(event as Map))
      .asBroadcastStream();

  /// Erisilebilirlik servisi acik mi (kullanici Ayarlar'dan acmis mi)?
  static Future<bool> isServiceRunning() async {
    try {
      final r = await _ch.invokeMethod<bool>('isAccessibilityServiceRunning');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android Erisilebilirlik ayarlar sayfasini acar (kullanici servisi
  /// elle acsin diye).
  static Future<void> openAccessibilitySettings() async {
    try {
      await _ch.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// Servisin en son okudugu degerleri getirir (fiyat + urun bilgileri).
  ///
  /// NOT: Bu artik SADECE ilk yukleme / fallback icin kullanilir (ornegin
  /// stream henuz ilk olayini yollamadan once anlik bir durum gerekirse).
  /// Canli takip icin [systemPriceStream] kullanin.
  static Future<SystemPriceSnapshot> getLastSystemPrice() async {
    try {
      final r =
          await _ch.invokeMethod<Map<dynamic, dynamic>>('getLastSystemPrice');
      return SystemPriceSnapshot._fromMap(r ?? const {});
    } catch (_) {
      return SystemPriceSnapshot.empty;
    }
  }

  /// Yeni taramadan once eski sistem fiyatini temizler (yanlislikla bir
  /// onceki urunun fiyatiyla karsilastirmamak icin).
  static Future<void> clearLastSystemPrice() async {
    try {
      await _ch.invokeMethod('clearLastSystemPrice');
    } catch (_) {}
  }

  /// TANI icin: servisin son durumu (acik mi, ne okudu, ekranda ne gordu).
  static Future<Map<String, dynamic>> getDebugInfo() async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('getDebugInfo');
      return r == null
          ? <String, dynamic>{}
          : r.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Native TTS ile Turkce sesli okuma (gorme dostu).
  static Future<void> speak(String text) async {
    try {
      await _ch.invokeMethod('speak', {'text': text});
    } catch (_) {}
  }

  /// Titresim. mismatch=true ise guclu/tekrarli (uyari), aksi halde kisa.
  static Future<void> vibrate({required bool mismatch}) async {
    try {
      await _ch.invokeMethod('vibrate', {'mismatch': mismatch});
    } catch (_) {}
  }

  /// Baloncuktan "hizli QR" istegi bekliyor mu? (acilista/resume'da sorulur)
  static Future<bool> consumeQuickScan() async {
    try {
      return (await _ch.invokeMethod<bool>('consumeQuickScan')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// onNewIntent'ten gelen anlik "QR modu ac" cagrisini dinlemek icin.
  static void setQuickScanHandler(void Function() onOpen) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'openQuickScan') onOpen();
      return null;
    });
  }
}

/// Native tarafin tek bir anda gonderdigi sistem fiyati + urun bilgisi
/// goruntusu (snapshot). Hem [PriceCheckChannel.getLastSystemPrice] hem de
/// [PriceCheckChannel.systemPriceStream] bu tipi kullanir, boylece ekran
/// kodu ikisi arasinda gecis yaparken tip degistirmek zorunda kalmaz.
class SystemPriceSnapshot {
  final double? price;
  final String? raw;
  final String? barcode;
  final String? stockCode;
  final String? productName;

  const SystemPriceSnapshot({
    this.price,
    this.raw,
    this.barcode,
    this.stockCode,
    this.productName,
  });

  static const empty = SystemPriceSnapshot();

  factory SystemPriceSnapshot._fromMap(Map<dynamic, dynamic> r) {
    return SystemPriceSnapshot(
      price: (r['price'] as num?)?.toDouble(),
      raw: r['raw'] as String?,
      barcode: r['barcode'] as String?,
      stockCode: r['stockCode'] as String?,
      productName: r['productName'] as String?,
    );
  }

  bool get hasData => price != null || productName != null;
}
