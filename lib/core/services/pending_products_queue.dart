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

/// "Fiyat Kontrol ekrani su an Navigator yiginda acik mi?" bilgisini
/// tutan GLOBAL bayrak.
///
/// v2 — NEDEN BURAYA TASINDI (eskiden MainShell'in State'i icindeydi):
/// Eski koddaki `_priceCheckOpen`, MainShell widget State'inin bir alaniydi.
/// Baloncuktan/onNewIntent'ten gelen "openQuickScan" istegi her zaman
/// MainShell uzerinden isleniyordu, ANCAK Fiyat Kontrol ekrani Navigator
/// yiginda MainShell'in USTUNDE (push edilmis) durur — yani istek geldigi
/// anda gercek karari veren widget (`MainShell`) o anda EKRANDA GORUNMEYEN,
/// arka planda duran bir widget'tir. Bu, normal kosullarda calissa da,
/// MainShell'in State'i herhangi bir nedenle yeniden olusturulursa (derin
/// baglanti, OEM'in arka plan surecini kismen kapatip Flutter motorunu
/// canli tutmasi, hot-restart vb.) bayrak sessizce `false`'a donup yanlislikla
/// YENI bir PriceCheckScreen push edilmesine yol aciyordu. Bu da kullanicinin
/// gozlemledigi iki seyi ayni anda acikliyor: "baloncuga basinca yeni sayfa
/// gibi aciliyor" VE "sag usttekiokunan urun kuyrugu siliniyor" (yeni push
/// edilen PriceCheckScreen'in route'u eskisinin USTUNE bindigi icin, geri
/// tusu artik bir ONCEKI PriceCheckScreen'e degil MainShell'e donuyor —
/// kullaniciya "kayit kayboldu" gibi gorunuyor, oysa aslinda alt route'ta
/// hala duruyor ama erisilemez/unutulmus haldedir).
///
/// Cozum: Bu bayragi WIDGET AGACINDAN TAMAMEN BAGIMSIZ, basit bir global
/// degiskene almak. Artik hangi widget'in State'inin yasam dongusunde
/// oldugu onemli degil; tek dogru kaynak budur.
bool priceCheckScreenOpen = false;

/// Fiyat Kontrol ekranini ac/tazele kararini veren TEK fonksiyon.
/// main_shell.dart ve baloncuktan gelen tetikleyici (onNewIntent) BU
/// fonksiyonu KULLANMALIDIR; dogrudan Navigator.push cagirmamalidir —
/// boylece "zaten acik mi" karari HER ZAMAN ayni yerde, ayni mantikla
/// verilir.
///
/// Donus degeri: ekran zaten aciktiysa false (sadece tazelendi), henuz
/// acik degilse true (caller yeni bir push yapmali).
bool requestPriceCheckOpen() {
  if (priceCheckScreenOpen) {
    requestQuickScan();
    return false;
  }
  return true;
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
