import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'db_source_prefs.dart';

/// Internetten barkod -> urun adi cozumu.
///
/// MERKEZI SORGU NOKTASI: Uygulamadaki TUM internet barkod sorgulari bu
/// servisten gecer. Hangi acik veri tabanlarinin kullanilacagi
/// DbSourcePrefs'ten okunur:
///   - Open Food Facts (OFF): gida/market urunleri
///   - Open Beauty Facts (OBF): kozmetik/kisisel bakim urunleri
/// Ikisi de aciksa once OFF, bulunamazsa OBF denenir (gida urunleri daha
/// yaygin oldugu icin OFF once). Tek bir tanesi aciksa sadece o denenir.
/// Hicbiri acik degilse sorgu yapilmaz (disabled doner).
///
/// Her iki veri tabani da AYNI API semasini kullanir (Open*Facts ailesi):
///   GET {base}/api/v2/product/{barkod}.json
/// Bu yuzden tek bir parse mantigi her ikisi icin de yeterlidir; sadece
/// taban URL degisir.
///
/// Open*Facts kurallari geregi ozel bir User-Agent gonderilir. Okuma
/// islemleri kimlik dogrulama gerektirmez.
class BarcodeLookupService {
  BarcodeLookupService._();
  static final BarcodeLookupService instance = BarcodeLookupService._();

  // Open*Facts, bot sanilmamak icin "AppAdi/Surum (iletisim)" biciminde
  // bir User-Agent ister.
  static const String _userAgent =
      'SKTTakip/1.0 (skt-takip-app@example.com)';

  // Veri tabani taban uc noktalari.
  static const String _offBase = 'https://world.openfoodfacts.org';
  static const String _obfBase = 'https://world.openbeautyfacts.org';

  // Asiri bekleme olmasin: kullanici hemen geri bildirim gormeli.
  static const Duration _timeout = Duration(seconds: 6);

  /// "el:fitness-bars" → "Fitness Bars" (on eki kaldir, tire→bosluk, basharfle).
  static String _cleanCategory(String raw) {
    // "xx:" on ekini kaldir.
    final noPrefix = raw.contains(':') ? raw.split(':').last : raw;
    // Tire ve alt cizgiyi bosluga cevir, kelimeler basharfle.
    return noPrefix
        .replaceAll(RegExp(r'[-_]'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Barkoddan urun adini cozer. Bulunamazsa / hata olursa null doner
  /// (cagiran taraf bir sonraki adima -Google'da Ara- gecebilir).
  Future<String?> lookupName(String barcode) async {
    final r = await lookupDetailed(barcode);
    return r.name;
  }

  /// Tanilama icin: adi + ne olduğunu (bulundu / bulunamadi / hata) doner.
  ///
  /// Aktif kaynaklari (DbSourcePrefs) sirayla dener; ilkinde bulunursa onu
  /// doner, bulunamazsa sonrakini dener. Boylece kozmetik bir urun OFF'ta
  /// yoksa otomatik OBF'te aranir (ikisi de acikken).
  Future<BarcodeLookupResult> lookupDetailed(String barcode) async {
    // Sadece rakamlari al (kamera bazen bosluk/gizli karakter ekler).
    final code = barcode.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (code.isEmpty) {
      return const BarcodeLookupResult(
          name: null, status: BarcodeLookupStatus.invalid);
    }

    // Hangi kaynaklar acik? (Merkezi tercih.)
    final prefs = DbSourcePrefs.instance;
    final bases = <String>[];
    if (prefs.offEnabled) bases.add(_offBase);
    if (prefs.obfEnabled) bases.add(_obfBase);

    // Hicbir kaynak acik degil: internet sorgusu yapma.
    if (bases.isEmpty) {
      return const BarcodeLookupResult(
          name: null, status: BarcodeLookupStatus.disabled);
    }

    BarcodeLookupResult? lastNonFound;
    for (final base in bases) {
      final result = await _lookupFromBase(base, code);
      if (result.found) return result; // ilk bulan kazanir
      lastNonFound = result;
    }
    // Hicbiri bulamadi: son anlamli sonucu (notFound/timeout/error) dondur.
    return lastNonFound ??
        const BarcodeLookupResult(
            name: null, status: BarcodeLookupStatus.notFound);
  }

  /// Tek bir veri tabani tabanindan (OFF veya OBF) sorgular. Iki veri tabani
  /// da ayni semayi kullandigi icin parse mantigi ortaktir.
  Future<BarcodeLookupResult> _lookupFromBase(
      String base, String code) async {
    // Yanit boyutunu kucult: ad/marka/kategori/gorsel/miktar alanlari.
    final uri = Uri.parse(
      '$base/api/v2/product/$code.json'
      '?fields=product_name,product_name_tr,brands,categories,'
      'categories_tags_tr,quantity,image_front_small_url,image_small_url',
    );

    try {
      final res = await http.get(
        uri,
        headers: const {'User-Agent': _userAgent},
      ).timeout(_timeout);

      if (res.statusCode != 200) {
        return const BarcodeLookupResult(
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
        category = _cleanCategory(catTags.last.toString());
      } else {
        final catStr = (product['categories'] as String?)?.trim();
        if (catStr != null && catStr.isNotEmpty) {
          category = _cleanCategory(catStr.split(',').last.trim());
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

enum BarcodeLookupStatus {
  found,
  notFound,
  timeout,
  httpError,
  error,
  invalid,
  disabled, // hicbir veri tabani kaynagi acik degil
}

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
