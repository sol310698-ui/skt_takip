import 'dart:io';

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

  static String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.length - 6) return '.jpg';
    return path.substring(dot);
  }
}
