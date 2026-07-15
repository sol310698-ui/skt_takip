import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_lock_service.dart';

/// Kamera/galeri ile fotograf almak icin MERKEZI yardimci.
///
/// Neden merkezi? ImagePicker acildiginda uygulama kisa sure "paused" olur;
/// donuste kilit mantigi bunu "kullanici arka plana aldi" sanip yeniden
/// kilitleyebilir ve devam eden akisi (orn. mesai girisi) yarida keser.
/// Tum kamera cagrilarini bu yardimcidan gecirerek, her birini otomatik
/// olarak AppLockService.runWithoutRelock korumasiyla sariyoruz.
class CameraHelper {
  CameraHelper._();

  /// Kamera/galeri ile bir fotograf cek/sec. Kilit tetiklemeden calisir.
  /// Iptal/hata durumunda null doner.
  ///
  /// DIKKAT: ImagePicker'in dondurdugu dosya ONBELLEK (cache) dizinindedir.
  /// Android "onbellegi temizle" yapinca bu dosya SILINIR. Kalici olarak
  /// saklanacak fotograflar icin pickImagePersistent() kullanin.
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.camera,
    int imageQuality = 85,
    double? maxWidth,
    double? maxHeight,
  }) {
    return AppLockService.runWithoutRelock(() async {
      try {
        return await ImagePicker().pickImage(
          source: source,
          imageQuality: imageQuality,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      } catch (_) {
        return null;
      }
    });
  }

  /// Fotograf cek/sec ve KALICI dizine kopyala; kalici dosya yolunu dondur.
  ///
  /// ImagePicker onbellege yazar (temizlenince kaybolur). Bu metod cekilen
  /// fotografi hemen <app_documents>/photos/ altina kopyalar; boylece
  /// "onbellegi temizle" veri kaybina yol acmaz. Mesai, palet, denetim gibi
  /// kalici saklanmasi gereken TUM fotograflar bunu kullanmali.
  ///
  /// Iptal/hata durumunda null doner.
  static Future<String?> pickImagePersistent({
    ImageSource source = ImageSource.camera,
    int imageQuality = 85,
    double? maxWidth,
    double? maxHeight,
  }) async {
    final x = await pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    if (x == null) return null;
    try {
      return await persistPhoto(x.path);
    } catch (_) {
      // Kopyalama basarisiz olursa en azindan onbellek yolunu dondur
      // (hic yoktan iyidir; ama normalde kopyalama basarili olur).
      return x.path;
    }
  }

  /// Verilen (onbellekteki) fotograf yolunu KALICI dizine kopyalar ve yeni
  /// kalici yolu dondurur. Zaten kalici dizindeyse oldugu gibi birakir.
  static Future<String> persistPhoto(String sourcePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${docs.path}/photos');
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    // Zaten kalici photos dizinindeyse tekrar kopyalama.
    if (sourcePath.startsWith(photoDir.path)) return sourcePath;

    final ext = _extOf(sourcePath);
    final name = 'img_${DateTime.now().millisecondsSinceEpoch}_'
        '${sourcePath.hashCode.toUnsigned(20)}$ext';
    final destPath = '${photoDir.path}/$name';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Fotograf cek/sec, KUCULT (en uzun kenar [maxSide] px) ve <docs>/[subdir]/
  /// altina JPEG olarak kaydet. Reyon dizilim gibi COK sayida foto tutan
  /// yerlerde disk/RAM tasarrufu icin kullanilir (720 px ~ 60-120 KB).
  ///
  /// Iptal/hata durumunda null doner.
  static Future<String?> pickImageDownscaled({
    ImageSource source = ImageSource.camera,
    int maxSide = 720,
    int quality = 80,
    String subdir = 'shelf_photos',
  }) async {
    // ImagePicker'in kendi maxWidth/Height'i cihazdan cihaza tutarsiz; bu yuzden
    // once orijinali (biraz sinirli) alip, sonra 'image' paketiyle KESIN olcuye
    // indiriyoruz. quality=100 aliyoruz cunku asil sikistirmayi biz yapacagiz.
    final x = await pickImage(
      source: source,
      imageQuality: 100,
      maxWidth: (maxSide * 2).toDouble(),
      maxHeight: (maxSide * 2).toDouble(),
    );
    if (x == null) return null;
    try {
      return await downscaleToFile(x.path, maxSide: maxSide, quality: quality, subdir: subdir);
    } catch (_) {
      // Kucultme basarisiz olursa hic olmazsa kalici kopyayi dondur.
      try {
        return await persistPhoto(x.path);
      } catch (_) {
        return x.path;
      }
    }
  }

  /// Verilen fotograf yolunu kucultup <docs>/[subdir]/ altina JPEG yazar,
  /// yeni yolu dondurur. Kaynak zaten kucukse yine de yeniden kodlanir
  /// (boyutu garanti altina almak icin).
  static Future<String> downscaleToFile(
    String sourcePath, {
    int maxSide = 720,
    int quality = 80,
    String subdir = 'shelf_photos',
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // Cozulemezse orijinali kalici dizine kopyala.
      return persistPhoto(sourcePath);
    }
    // En uzun kenari maxSide'a indir (kucukse buyutme).
    final img.Image resized = (decoded.width >= decoded.height)
        ? (decoded.width > maxSide
            ? img.copyResize(decoded, width: maxSide)
            : decoded)
        : (decoded.height > maxSide
            ? img.copyResize(decoded, height: maxSide)
            : decoded);
    final jpg = img.encodeJpg(resized, quality: quality);

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name =
        'p_${DateTime.now().millisecondsSinceEpoch}_${sourcePath.hashCode.toUnsigned(16)}.jpg';
    final destPath = '${dir.path}/$name';
    await File(destPath).writeAsBytes(jpg, flush: true);
    return destPath;
  }

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.length - 6) return '.jpg';
    return path.substring(dot);
  }
}
