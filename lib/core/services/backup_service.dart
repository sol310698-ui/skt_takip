import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import 'database_service.dart';

/// DB dosyasini disari aktar (paylasim menusu) ve geri yukle.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// DB dosyasinin yolunu dondurur.
  Future<String> _dbPath() async {
    final dbDir = await getDatabasesPath();
    return p.join(dbDir, AppConstants.dbName);
  }

  /// DB dosyasini Documents klasorune kopyalar ve paylasim menusunu acar.
  /// Kullanici Google Drive, WhatsApp, dosya yoneticisi vb. ile kaydedebilir.
  Future<void> exportDb() async {
    final src = File(await _dbPath());
    if (!src.existsSync()) {
      throw const BackupException('Veritabanı dosyası bulunamadı.');
    }

    // Okunabilir isimle gecici klasore kopyala.
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    final dst = File(p.join(tmp.path, 'skt_takip_yedek_$stamp.db'));
    await src.copy(dst.path);

    await Share.shareXFiles(
      [XFile(dst.path, mimeType: 'application/octet-stream')],
      subject: 'SKT Takip Yedek — $stamp',
    );
  }

  /// Disaridan secilen .db dosyasini uygulamanin DB'sinin uzerine yazar.
  /// DIKKAT: mevcut veri tamamen silinir. Cagiran onay almali.
  Future<void> importDb(String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) {
      throw const BackupException('Kaynak dosya bulunamadı.');
    }

    // Temel dogrulama: SQLite magic bytes (ilk 16 byte).
    final header = await src.openRead(0, 16).first;
    final magic = String.fromCharCodes(header.take(15));
    if (!magic.startsWith('SQLite format 3')) {
      throw const BackupException('Geçersiz yedek dosyası (SQLite değil).');
    }

    // Aktif DB baglantisini kapat.
    await DatabaseService.instance.close();

    final dst = File(await _dbPath());
    await src.copy(dst.path);

    // DB bir sonraki erisimde otomatik yeniden acilir.
  }
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}
