import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  TAM YEDEKLEME / GERI YUKLEME  (DB + TUM FOTOGRAFLAR)
/// ────────────────────────────────────────────────────────────────────
///  TEK bir .zip dosyasina HER SEYI alir:
///    - Veritabani (skt_takip.db): ürünler, fiyatlar, SKT kayıtları,
///      reyonlar/raflar, barkod dizini, geçmiş — hepsi bu tek dosyadadır.
///    - TÜM fotoğraflar: documents altındaki photos / shelf_photos /
///      product_photos klasörleri.
///
///  Zip yapisi:
///    manifest.txt
///    db/skt_takip.db
///    files/<altklasor>/<foto...>
///
///  Geri yüklemede DB ve fotoğraflar yerine yazılır; ayrıca veritabanındaki
///  MUTLAK fotoğraf yolları bu cihazın güncel documents dizinine onarılır
///  (yedek başka cihazda alınmış olabilir).
/// ════════════════════════════════════════════════════════════════════
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// Documents altinda yedeklenecek fotograf klasorleri.
  static const List<String> _photoDirs = [
    'photos',
    'shelf_photos',
    'product_photos',
  ];

  Future<String> _dbPath() async {
    final dbDir = await getDatabasesPath();
    return p.join(dbDir, AppConstants.dbName);
  }

  // ── TAM YEDEK OLUŞTUR + PAYLAŞ ─────────────────────────────────────

  /// Her seyi bir .zip'e alir ve paylasim menusunu acar (Drive, WhatsApp,
  /// dosya yoneticisi...). [onProgress] durum bildirir.
  Future<void> exportAll({void Function(String)? onProgress}) async {
    onProgress?.call('Hazırlanıyor…');

    // WAL'i ana dosyaya yaz — kopya guncel olsun.
    final db = await DatabaseService.instance.database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}

    final dbPath = await _dbPath();
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 16);
    final outPath = p.join(tmp.path, 'skt_takip_yedek_$stamp.zip');

    // Onceki ayni isimli gecici zip varsa temizle.
    final outFile = File(outPath);
    if (outFile.existsSync()) outFile.deleteSync();

    // Fotograf sayisi (manifest + ilerleme icin).
    int photoTotal = 0;
    for (final d in _photoDirs) {
      final dir = Directory('${docs.path}/$d');
      if (dir.existsSync()) {
        photoTotal +=
            dir.listSync(recursive: true).whereType<File>().length;
      }
    }

    final encoder = ZipFileEncoder();
    encoder.create(outPath);

    // 1) Manifest
    final manifestFile = File(p.join(tmp.path, 'manifest.txt'))
      ..writeAsStringSync('SKT Takip Yedeği\n'
          'Tarih: ${DateTime.now()}\n'
          'DB: ${AppConstants.dbName}\n'
          'Fotoğraf: $photoTotal\n'
          'Sürüm: 1\n');
    encoder.addFile(manifestFile, 'manifest.txt');

    // 2) Veritabani
    onProgress?.call('Veritabanı ekleniyor…');
    if (File(dbPath).existsSync()) {
      encoder.addFile(File(dbPath), 'db/${AppConstants.dbName}');
    }

    // 3) Fotograflar
    int added = 0;
    for (final d in _photoDirs) {
      final dir = Directory('${docs.path}/$d');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: docs.path); // photos/xxx.jpg
        encoder.addFile(f, 'files/$rel');
        added++;
        if (added % 15 == 0) {
          onProgress?.call('Fotoğraflar ekleniyor ($added/$photoTotal)');
        }
      }
    }

    encoder.close();

    onProgress?.call('Paylaşılıyor…');
    await Share.shareXFiles(
      [XFile(outPath, mimeType: 'application/zip')],
      subject: 'SKT Takip Tam Yedek — $stamp',
    );
  }

  // ── GERI YUKLE ─────────────────────────────────────────────────────

  /// Bir yedek .zip'inden (yeni biçim) DB + fotograflari YERINE yazar.
  /// Eski biçim (düz .db dosyası) da desteklenir: doğrudan DB'nin üstüne yazar.
  /// DIKKAT: mevcut veriler silinir; cagiran once onay almali.
  Future<void> restoreAll(String sourcePath,
      {void Function(String)? onProgress}) async {
    final src = File(sourcePath);
    if (!src.existsSync()) {
      throw const BackupException('Kaynak dosya bulunamadı.');
    }

    // Eski biçim: düz SQLite .db dosyası mı?
    final head = await src.openRead(0, 16).first;
    final magic = String.fromCharCodes(head.take(15));
    if (magic.startsWith('SQLite format 3')) {
      onProgress?.call('Veritabanı geri yükleniyor…');
      await DatabaseService.instance.close();
      await src.copy(await _dbPath());
      return;
    }

    // Yeni biçim: .zip
    onProgress?.call('Yedek okunuyor…');
    final archive = ZipDecoder().decodeBytes(src.readAsBytesSync());
    final docs = await getApplicationDocumentsDirectory();

    await DatabaseService.instance.close();

    // 1) Fotograflar
    int restored = 0;
    for (final e in archive) {
      if (e.isFile && e.name.startsWith('files/')) {
        final rel = e.name.substring('files/'.length);
        final out = File('${docs.path}/$rel');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(e.content as List<int>);
        restored++;
        if (restored % 15 == 0) {
          onProgress?.call('Fotoğraflar geri yükleniyor ($restored)');
        }
      }
    }

    // 2) Veritabani
    onProgress?.call('Veritabanı geri yükleniyor…');
    bool dbWritten = false;
    for (final e in archive) {
      if (e.isFile && e.name.startsWith('db/')) {
        final out = File(await _dbPath());
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(e.content as List<int>);
        dbWritten = true;
      }
    }
    if (!dbWritten) {
      throw const BackupException('Yedekte veritabanı bulunamadı.');
    }

    // 3) Fotograf yollarini bu cihaza gore onar.
    onProgress?.call('Yollar onarılıyor…');
    await _fixPhotoPaths(docs.path);
    onProgress?.call('Tamamlandı');
  }

  /// Yedek baska cihazda alinmis olabilir; DB'deki MUTLAK fotograf yollari
  /// eski documents dizinini gosterir. Yolun "/<altklasor>/<dosya>" kismini
  /// koruyup basini bu cihazin documents diziniyle degistiririz.
  Future<void> _fixPhotoPaths(String docsPath) async {
    final db = await DatabaseService.instance.database;

    Future<void> fix(String table, String col) async {
      try {
        final rows = await db.query(table,
            columns: ['rowid', col], where: '$col IS NOT NULL');
        for (final r in rows) {
          final old = r[col] as String?;
          if (old == null || old.isEmpty) continue;
          for (final d in _photoDirs) {
            final idx = old.indexOf('/$d/');
            if (idx >= 0) {
              final np = docsPath + old.substring(idx);
              if (np != old) {
                await db.update(table, {col: np},
                    where: 'rowid = ?', whereArgs: [r['rowid']]);
              }
              break;
            }
          }
        }
      } catch (_) {}
    }

    await fix(AppConstants.shelfSlotTable, 'photo_path');
    await fix(AppConstants.barcodeTable, 'local_image_path');
  }
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}
