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
    final r = await lookupDetailed(barcode);
    return r.name;
  }

  /// Tanilama icin: adi + ne olduğunu (bulundu / bulunamadi / hata) doner.
  Future<BarcodeLookupResult> lookupDetailed(String barcode) async {
    // Sadece rakamlari al (kamera bazen bosluk/gizli karakter ekler).
    final code = barcode.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (code.isEmpty) {
      return const BarcodeLookupResult(
          name: null, status: BarcodeLookupStatus.invalid);
    }

    // Yanit boyutunu kucult: ad/marka/kategori/gorsel/miktar alanlari.
    final uri = Uri.parse(
      '$_base/api/v2/product/$code.json'
      '?fields=product_name,product_name_tr,brands,categories,'
      'categories_tags_tr,quantity,image_front_small_url,image_small_url',
    );

    try {
      final res = await http.get(
        uri,
        headers: const {'User-Agent': _userAgent},
      ).timeout(_timeout);

      if (res.statusCode != 200) {
        return BarcodeLookupResult(
            name: null, status: BarcodeLookupStatus.httpError);
      }

      final Map<String, dynamic> data = json.decode(res.body);

      // status == 1 -> urun bulundu. (0 -> bulunamadi)
      if (data['status'] != 1) {
        return const BarcodeLookupResult(
            name: null, status: BarcodeLookupStatus.notFound);
      }

      final product = data['product'];
      if (product is! Map) {
        return const BarcodeLookupResult(
            name: null, status: BarcodeLookupStatus.notFound);
      }

      final nameTr = (product['product_name_tr'] as String?)?.trim();
      final name = (product['product_name'] as String?)?.trim();
      final brandRaw = (product['brands'] as String?)?.trim();
      final firstBrand = (brandRaw != null && brandRaw.isNotEmpty)
          ? brandRaw.split(',').first.trim()
          : null;

      String? chosen;
      if (nameTr != null && nameTr.isNotEmpty) {
        chosen = nameTr;
      } else if (name != null && name.isNotEmpty) {
        chosen = name;
      }

      if (chosen == null) {
        return const BarcodeLookupResult(
            name: null, status: BarcodeLookupStatus.notFound);
      }

      // Marka adda gecmiyorsa basina ekle (daha taninabilir).
      String displayName = chosen;
      if (firstBrand != null &&
          firstBrand.isNotEmpty &&
          !chosen.toLowerCase().contains(firstBrand.toLowerCase())) {
        displayName = '$firstBrand $chosen';
      }

      // Kategori: once TR etiketleri, yoksa genel kategori metni.
      String? category;
      final catTags = product['categories_tags_tr'];
      if (catTags is List && catTags.isNotEmpty) {
        category = catTags.last.toString().trim();
      } else {
        final catStr = (product['categories'] as String?)?.trim();
        if (catStr != null && catStr.isNotEmpty) {
          category = catStr.split(',').last.trim();
        }
      }

      final imageUrl = (product['image_front_small_url'] as String?) ??
          (product['image_small_url'] as String?);

      return BarcodeLookupResult(
        name: displayName,
        brand: firstBrand,
        category: category,
        quantity: (product['quantity'] as String?)?.trim(),
        imageUrl: imageUrl,
        status: BarcodeLookupStatus.found,
      );
    } on TimeoutException {
      return const BarcodeLookupResult(
          name: null, status: BarcodeLookupStatus.timeout);
    } catch (_) {
      return const BarcodeLookupResult(
          name: null, status: BarcodeLookupStatus.error);
    }
  }
}

enum BarcodeLookupStatus { found, notFound, timeout, httpError, error, invalid }

class BarcodeLookupResult {
  final String? name;
  final String? brand;
  final String? category;
  final String? quantity;
  final String? imageUrl;
  final BarcodeLookupStatus status;
  const BarcodeLookupResult({
    required this.name,
    this.brand,
    this.category,
    this.quantity,
    this.imageUrl,
    required this.status,
  });

  bool get found => status == BarcodeLookupStatus.found;
}
