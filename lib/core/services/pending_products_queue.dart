import 'package:flutter/foundation.dart';

/// ════════════════════════════════════════════════════════════════════
///  FIYAT KONTROL — BEKLEYEN URUNLER KUYRUGU
/// ────────────────────────────────────────────────────────────────────
///  Erisilebilirlik servisinden okunan urun bilgileri (barkod, stok kodu,
///  urun adi) DOGRUDAN veritabanina yazilmaz. Once bu kuyruga eklenir,
///  kullanici onay sayfasinda kontrol eder, sonra toplu kaydeder.
///
///  Oturum ici (bellekte) tutulur — yeni paket/DB migration gerektirmez,
///  mevcut yapiyi bozmaz. "Okut → kontrol et → kaydet" ayni oturumda
///  yapildigi icin yeterlidir.
/// ════════════════════════════════════════════════════════════════════
class PendingProduct {
  final String barcode;
  final String? stockCode;
  final String productName;
  final double? systemPrice;
  final DateTime scannedAt;

  PendingProduct({
    required this.barcode,
    this.stockCode,
    required this.productName,
    this.systemPrice,
    required this.scannedAt,
  });
}

/// Global, oturum-ici bekleyen urun kuyrugu. Fiyat Kontrol ekrani ekler,
/// onay sayfasi dinler/siler/kaydeder.
final pendingProductsQueue = ValueNotifier<List<PendingProduct>>([]);

/// Baloncuktan gelen "hizli QR" istegi icin global sinyal.
///
/// AMAC: Fiyat Kontrol ekrani ZATEN ACIKKEN baloncuga tiklayinca yeni bir
/// ekran ACMAMAK (eski davranis: her tikta ust uste yeni ekran push edilip
/// akis sifirlaniyor, kullanicinin kaydetmek istedigi urun kayboluyordu).
/// Onun yerine acik ekran bu sinyali dinler ve sadece taramayi tazeler.
/// Deger her artirildiginda "yeni bir tarama istendi" demektir.
final quickScanSignal = ValueNotifier<int>(0);

void requestQuickScan() {
  quickScanSignal.value = quickScanSignal.value + 1;
}

/// Kuyruga ekler. Ayni barkod zaten varsa gunceller (mukerrer olmasin).
void addPendingProduct(PendingProduct p) {
  final list = List<PendingProduct>.from(pendingProductsQueue.value);
  final idx = list.indexWhere((e) => e.barcode == p.barcode);
  if (idx >= 0) {
    list[idx] = p; // ayni barkod -> en son okunan kalsin
  } else {
    list.insert(0, p); // en yeni en ustte
  }
  pendingProductsQueue.value = list;
}

void removePendingProduct(String barcode) {
  pendingProductsQueue.value = pendingProductsQueue.value
      .where((e) => e.barcode != barcode)
      .toList();
}

void clearPendingProducts() {
  pendingProductsQueue.value = [];
}
