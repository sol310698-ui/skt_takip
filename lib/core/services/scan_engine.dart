import 'package:mobile_scanner/mobile_scanner.dart';

/// ════════════════════════════════════════════════════════════════════
///  ORTAK TARAMA MOTORU
/// ────────────────────────────────────────────────────────────────────
///  Uygulamadaki TUM barkod tarayicilar ayni davranisi paylassin diye:
///   - Varsayilan (strictEan13 = switch ACIK): yalnizca GECERLI EAN-13 /
///     EAN-8 / UPC-A barkodlar kabul edilir — KONTROL BASAMAGI dogrulanir
///     (yanlis/eksik okumalar elenir).
///   - switch KAPALI (strictEan13 = false): Code128 dahil HER formati okur
///     ("hepsini oku").
///   - QR / DataMatrix'ten barkod cikarma HER ZAMAN aciktir: etiket uzerindeki
///     QR bir urun barkodu (ya da icinde gecerli bir barkod) tasiyorsa,
///     kesin modda bile o barkod cikarilip dogrulanir.
///
///  Kullanim (her ekranin _onDetect'inde):
///     final code = ScanEngine.accept(capture, strictEan13: _strictScan);
///     if (code == null) return;
///     ... code ile devam ...
/// ════════════════════════════════════════════════════════════════════
class ScanEngine {
  ScanEngine._();

  /// Donanimin okuyacagi GENIS format kumesi. Yazilimda strict/all'a gore
  /// suzulur; QR her zaman denenir. (Tum tarayici controller'lari bunu
  /// kullanmali ki QR + 1D barkodlar ayni anda yakalanabilsin.)
  static const List<BarcodeFormat> broadFormats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.itf,
    BarcodeFormat.codabar,
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
  ];

  /// Bir yakalamadan KABUL EDILEN barkodu dondurur (yoksa null).
  static String? accept(BarcodeCapture capture, {required bool strictEan13}) {
    // 1) Once 2D (QR/DataMatrix): icinde gecerli bir barkod varsa cikar
    //    (QR'dan barkod cikarma HER MODDA aciktir).
    for (final b in capture.barcodes) {
      if (b.format == BarcodeFormat.qrCode ||
          b.format == BarcodeFormat.dataMatrix) {
        final code = barcodeFromQr(b.rawValue);
        if (code != null) return code;
      }
    }
    // 2) Sonra 1D barkodlar.
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (b.format == BarcodeFormat.qrCode ||
          b.format == BarcodeFormat.dataMatrix) {
        continue; // yukarida ele alindi
      }
      if (strictEan13) {
        // KESIN mod: yalnizca kontrol basamagi dogru perakende barkodu.
        if (isValidRetailBarcode(raw)) return raw;
        continue; // gecersiz -> reddet (yanlis okuma birikmesin)
      }
      // HEPSI modu: Code128 dahil her sey.
      return raw;
    }
    return null;
  }

  /// QR/DataMatrix icerigi bir urun barkodu mu? Dogrudan gecerli barkodsa
  /// ya da icinden gecerli bir 8-14 haneli barkod dizisi ayiklanabiliyorsa
  /// onu dondurur (yoksa null).
  static String? barcodeFromQr(String? rawValue) {
    if (rawValue == null) return null;
    final v = rawValue.trim();
    if (v.isEmpty) return null;
    if (isValidRetailBarcode(v)) return v;
    for (final m in RegExp(r'\d{8,14}').allMatches(v)) {
      final s = m.group(0)!;
      if (isValidRetailBarcode(s)) return s;
    }
    return null;
  }

  /// Perakende barkodu (EAN-13 / EAN-8 / UPC-A) kontrol basamagi dogru mu?
  static bool isValidRetailBarcode(String s) =>
      validEan13(s) || validEan8(s) || validUpcA(s);

  /// EAN-13 saglama basamagi dogrulamasi.
  static bool validEan13(String s) {
    if (s.length != 13 || int.tryParse(s) == null) return false;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = s.codeUnitAt(i) - 48;
      sum += i.isEven ? d : d * 3;
    }
    return (10 - (sum % 10)) % 10 == (s.codeUnitAt(12) - 48);
  }

  /// EAN-8 saglama basamagi dogrulamasi.
  static bool validEan8(String s) {
    if (s.length != 8 || int.tryParse(s) == null) return false;
    var sum = 0;
    for (var i = 0; i < 7; i++) {
      final d = s.codeUnitAt(i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - (sum % 10)) % 10 == (s.codeUnitAt(7) - 48);
  }

  /// UPC-A saglama basamagi dogrulamasi.
  static bool validUpcA(String s) {
    if (s.length != 12 || int.tryParse(s) == null) return false;
    var sum = 0;
    for (var i = 0; i < 11; i++) {
      final d = s.codeUnitAt(i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - (sum % 10)) % 10 == (s.codeUnitAt(11) - 48);
  }
}
