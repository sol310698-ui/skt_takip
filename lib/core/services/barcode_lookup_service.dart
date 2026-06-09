import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Internetten barkod -> urun adi cozumu (Open Food Facts).
///
/// Kademeli aramanin SON halkasidir: once yerel dizin ve aktif/gecmis
/// urunler denenir, bulunamazsa bu servis cagrilir.
///
/// Open Food Facts kurallari geregi ozel bir User-Agent gonderilir.
/// Okuma islemleri kimlik dogrulama gerektirmez.
class BarcodeLookupService {
  BarcodeLookupService._();
  static final BarcodeLookupService instance = BarcodeLookupService._();

  // OFF, bot sanilmamak icin "AppAdi/Surum (iletisim)" biciminde
  // bir User-Agent ister.
  static const String _userAgent =
      'SKTTakip/1.0 (skt-takip-app@example.com)';

  // Uretim uc noktasi (.net test/staging icindir).
  static const String _base = 'https://world.openfoodfacts.org';

  // Asiri bekleme olmasin: kullanici hemen geri bildirim gormeli.
  static const Duration _timeout = Duration(seconds: 6);

  /// Barkoddan urun adini cozer. Bulunamazsa / hata olursa null doner
  /// (cagiran taraf bir sonraki adima -Google'da Ara- gecebilir).
  Future<String?> lookupName(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    // Yanit boyutunu kucult: sadece ad/marka alanlari.
    final uri = Uri.parse(
      '$_base/api/v2/product/$code.json?fields=product_name,product_name_tr,brands',
    );

    try {
      final res = await http.get(
        uri,
        headers: const {'User-Agent': _userAgent},
      ).timeout(_timeout);

      if (res.statusCode != 200) return null;

      final Map<String, dynamic> data = json.decode(res.body);

      // status == 1 -> urun bulundu. (0 -> bulunamadi)
      final status = data['status'];
      if (status != 1) return null;

      final product = data['product'];
      if (product is! Map) return null;

      // Once Turkce ad, sonra genel ad; bos ise markayla destekle.
      final nameTr = (product['product_name_tr'] as String?)?.trim();
      final name = (product['product_name'] as String?)?.trim();
      final brand = (product['brands'] as String?)?.trim();

      final chosen = (nameTr != null && nameTr.isNotEmpty)
          ? nameTr
          : (name != null && name.isNotEmpty)
              ? name
              : null;

      if (chosen == null) return null;

      // Marka varsa ve adda gecmiyorsa basina ekle (daha taninabilir).
      if (brand != null &&
          brand.isNotEmpty &&
          !chosen.toLowerCase().contains(brand.toLowerCase())) {
        // brands virgulle birden cok olabilir; ilkini al.
        final firstBrand = brand.split(',').first.trim();
        if (firstBrand.isNotEmpty) {
          return '$firstBrand $chosen';
        }
      }
      return chosen;
    } on TimeoutException {
      return null;
    } catch (_) {
      // Ag hatasi, JSON hatasi vb. - sessizce null don.
      return null;
    }
  }
}
