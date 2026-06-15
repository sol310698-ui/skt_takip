import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// OCR oncesi goruntu on isleme.
/// Zor okunan etiketler (dusuk kontrast, kirmizi zemin, soluk baski) icin
/// ayni goruntunun birden fazla islenmis versiyonunu uretir.
class ImagePreprocessService {
  ImagePreprocessService._();
  static final instance = ImagePreprocessService._();

  /// Bir foto yolundan, OCR icin denenecek goruntu yollarini uretir.
  /// Sirayla: orijinal, gri+kontrast, invert (koyu zemin icin).
  /// Her biri ML Kit'e ayri verilip sonuclar birlestirilir.
  Future<List<String>> generateVariants(String sourcePath) async {
    final variants = <String>[sourcePath]; // 1) orijinal her zaman var

    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return variants;

      // Cok buyukse kucult (hiz icin) - en fazla 1600px genislik
      img.Image base = decoded;
      if (decoded.width > 1600) {
        base = img.copyResize(decoded, width: 1600);
      }

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      // 2) Gri tonlama + yuksek kontrast (soluk/dusuk kontrast icin)
      final gray = img.grayscale(img.Image.from(base));
      final contrasted = img.adjustColor(gray, contrast: 1.8);
      final p2 = '${dir.path}/ocr_contrast_$ts.jpg';
      await File(p2).writeAsBytes(img.encodeJpg(contrasted, quality: 90));
      variants.add(p2);

      // 3) Invert (kirmizi/koyu zemin uzerine acik yazi icin)
      final grayInv = img.grayscale(img.Image.from(base));
      final inverted = img.invert(img.adjustColor(grayInv, contrast: 1.6));
      final p3 = '${dir.path}/ocr_invert_$ts.jpg';
      await File(p3).writeAsBytes(img.encodeJpg(inverted, quality: 90));
      variants.add(p3);
    } catch (_) {
      // Isleme basarisiz olsa bile orijinal yol her zaman dondurulur.
    }

    return variants;
  }

  /// Gecici islenmis dosyalari temizle.
  Future<void> cleanup(List<String> paths, String keepOriginal) async {
    for (final p in paths) {
      if (p == keepOriginal) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
