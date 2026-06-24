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
/// ════════════════════════════════════════════════════════════════════
class PriceCheckChannel {
  static const _ch = MethodChannel('skt_takip/price_check');

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
  static Future<
      ({
        double? price,
        String? raw,
        String? barcode,
        String? stockCode,
        String? productName,
      })> getLastSystemPrice() async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
          'getLastSystemPrice');
      return (
        price: (r?['price'] as num?)?.toDouble(),
        raw: r?['raw'] as String?,
        barcode: r?['barcode'] as String?,
        stockCode: r?['stockCode'] as String?,
        productName: r?['productName'] as String?,
      );
    } catch (_) {
      return (
        price: null,
        raw: null,
        barcode: null,
        stockCode: null,
        productName: null,
      );
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

  // ── YUZEN BALONCUK (OVERLAY) ──
  static Future<bool> canDrawOverlays() async {
    try {
      return (await _ch.invokeMethod<bool>('canDrawOverlays')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _ch.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<bool> startOverlay() async {
    try {
      return (await _ch.invokeMethod<bool>('startOverlay')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopOverlay() async {
    try {
      await _ch.invokeMethod('stopOverlay');
    } catch (_) {}
  }

  static Future<bool> isOverlayRunning() async {
    try {
      return (await _ch.invokeMethod<bool>('isOverlayRunning')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Baloncuk rengini gunceller: neutral|match|mismatch|wrong|nosystem
  static Future<void> updateOverlayState(String state) async {
    try {
      await _ch.invokeMethod('updateOverlayState', {'state': state});
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
