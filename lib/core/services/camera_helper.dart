import 'package:image_picker/image_picker.dart';

import 'app_lock_service.dart';

/// Kamera/galeri ile fotograf almak icin MERKEZI yardimci.
///
/// Neden merkezi? ImagePicker acildiginda uygulama kisa sure "paused" olur;
/// donuste kilit mantigi bunu "kullanici arka plana aldi" sanip yeniden
/// kilitleyebilir ve devam eden akisi (orn. mesai girisi) yarida keser.
/// Tum kamera cagrilarini bu yardimcidan gecirerek, her birini otomatik
/// olarak AppLockService.runWithoutRelock korumasiyla sariyoruz. Boylece
/// ileride eklenen kamera kullanimlari da kendiliginden korunur.
class CameraHelper {
  CameraHelper._();

  /// Kamera/galeri ile bir fotograf cek/sec. Kilit tetiklemeden calisir.
  /// Iptal/hata durumunda null doner.
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
}
