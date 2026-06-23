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

  /// Servisin en son okudugu "Sistem Fiyati" degerini getirir.
  /// Donus: (price, raw). Hicbir sey okunmadiysa price null.
  static Future<({double? price, String? raw})> getLastSystemPrice() async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
          'getLastSystemPrice');
      final price = (r?['price'] as num?)?.toDouble();
      final raw = r?['raw'] as String?;
      return (price: price, raw: raw);
    } catch (_) {
      return (price: null, raw: null);
    }
  }

  /// Yeni taramadan once eski sistem fiyatini temizler (yanlislikla bir
  /// onceki urunun fiyatiyla karsilastirmamak icin).
  static Future<void> clearLastSystemPrice() async {
    try {
      await _ch.invokeMethod('clearLastSystemPrice');
    } catch (_) {}
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
}
