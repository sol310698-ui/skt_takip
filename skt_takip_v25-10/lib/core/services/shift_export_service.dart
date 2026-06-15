import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/shift_entry.dart';

/// Mesai kayitlarini disa aktarma (Excel + metin ozet).
class ShiftExportService {
  ShiftExportService._();
  static final instance = ShiftExportService._();

  /// Excel olarak disa aktar ve paylas.
  Future<void> exportExcel(List<ShiftEntry> shifts) async {
    final excel = Excel.createExcel();
    final sheet = excel['Mesai'];
    excel.delete('Sheet1');

    // Baslik satiri
    final headers = [
      'Tarih', 'Giriş', 'Çıkış', 'Süre',
      'Giriş Konum', 'Çıkış Konum', 'Giriş Foto', 'Çıkış Foto', 'Not'
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    final df = DateFormat('dd.MM.yyyy');
    final tf = DateFormat('HH:mm');

    for (final s in shifts) {
      sheet.appendRow([
        TextCellValue(df.format(s.clockIn)),
        TextCellValue(tf.format(s.clockIn)),
        TextCellValue(s.clockOut != null ? tf.format(s.clockOut!) : '-'),
        TextCellValue(s.clockOut != null ? s.durationLabel : 'Devam ediyor'),
        TextCellValue(s.inLatitude != null
            ? '${s.inLatitude!.toStringAsFixed(5)}, ${s.inLongitude!.toStringAsFixed(5)}'
            : '-'),
        TextCellValue(s.outLatitude != null
            ? '${s.outLatitude!.toStringAsFixed(5)}, ${s.outLongitude!.toStringAsFixed(5)}'
            : '-'),
        TextCellValue(s.photoInPath != null ? 'Var' : '-'),
        TextCellValue(s.photoOutPath != null ? 'Var' : '-'),
        TextCellValue(s.note ?? ''),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final path = '${dir.path}/mesai_$ts.xlsx';
    await File(path).writeAsBytes(bytes);

    await Share.shareXFiles([XFile(path)], text: 'Mesai Kayıtları (Excel)');
  }

  /// Metin ozet olarak paylas.
  /// Mesai verisi + TÜM fotoğrafları tek ZIP'e paketler, paylaşır.
  /// Kullanıcı paylaşım menüsünden Google Drive'a kaydedebilir.
  Future<void> backupToZip(List<ShiftEntry> shifts) async {
    final archive = Archive();

    // 1) Excel'i oluştur ve arşive ekle.
    final excelBytes = _buildExcelBytes(shifts);
    if (excelBytes != null) {
      archive.addFile(
          ArchiveFile('mesai_kayitlari.xlsx', excelBytes.length, excelBytes));
    }

    // 2) Fotoğrafları ekle.
    int photoCount = 0;
    for (final s in shifts) {
      for (final entry in [
        ('giris', s.photoInPath),
        ('cikis', s.photoOutPath),
      ]) {
        final path = entry.$2;
        if (path == null) continue;
        final file = File(path);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        final dateStr =
            '${s.clockIn.year}${s.clockIn.month.toString().padLeft(2, '0')}${s.clockIn.day.toString().padLeft(2, '0')}';
        final ext = path.split('.').last;
        archive.addFile(ArchiveFile(
          'fotograflar/${dateStr}_${s.id ?? photoCount}_${entry.$1}.$ext',
          bytes.length,
          bytes,
        ));
        photoCount++;
      }
    }

    // 3) ZIP'i kaydet ve paylaş.
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now();
    final fname =
        'mesai_yedek_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.zip';
    final zipPath = '${dir.path}/$fname';
    await File(zipPath).writeAsBytes(zipData);

    await Share.shareXFiles(
      [XFile(zipPath)],
      text: 'Mesai Yedeği ($photoCount fotoğraf) — Google Drive\'a kaydedebilirsiniz',
    );
  }

  /// Excel'i byte olarak üretir (paylaşmadan).
  List<int>? _buildExcelBytes(List<ShiftEntry> shifts) {
    final excel = Excel.createExcel();
    final sheet = excel['Mesai'];
    excel.setDefaultSheet('Mesai');

    sheet.appendRow([
      TextCellValue('Tarih'),
      TextCellValue('Giriş'),
      TextCellValue('Çıkış'),
      TextCellValue('Süre'),
      TextCellValue('Giriş Foto'),
      TextCellValue('Çıkış Foto'),
    ]);

    final fmtDate = DateFormat('dd.MM.yyyy');
    final fmtTime = DateFormat('HH:mm');
    for (final s in shifts) {
      final dur = s.clockOut != null
          ? s.clockOut!.difference(s.clockIn)
          : null;
      sheet.appendRow([
        TextCellValue(fmtDate.format(s.clockIn)),
        TextCellValue(fmtTime.format(s.clockIn)),
        TextCellValue(
            s.clockOut != null ? fmtTime.format(s.clockOut!) : '-'),
        TextCellValue(dur != null
            ? '${dur.inHours}s ${dur.inMinutes % 60}dk'
            : '-'),
        TextCellValue(s.photoInPath != null ? 'Var' : '-'),
        TextCellValue(s.photoOutPath != null ? 'Var' : '-'),
      ]);
    }
    return excel.encode();
  }

  Future<void> exportText(List<ShiftEntry> shifts) async {
    final df = DateFormat('dd.MM.yyyy');
    final tf = DateFormat('HH:mm');
    final buffer = StringBuffer();
    buffer.writeln('MESAİ KAYITLARI');
    buffer.writeln('Oluşturma: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}');
    buffer.writeln('Toplam kayıt: ${shifts.length}');
    buffer.writeln('${'=' * 30}');
    buffer.writeln();

    Duration total = Duration.zero;
    for (final s in shifts) {
      buffer.writeln('Tarih: ${df.format(s.clockIn)}');
      buffer.writeln('  Giriş: ${tf.format(s.clockIn)}');
      buffer.writeln(
          '  Çıkış: ${s.clockOut != null ? tf.format(s.clockOut!) : "Devam ediyor"}');
      if (s.clockOut != null) {
        buffer.writeln('  Süre: ${s.durationLabel}');
        total += s.duration;
      }
      if (s.inLatitude != null) {
        buffer.writeln(
            '  Giriş konum: ${s.inLatitude!.toStringAsFixed(5)}, ${s.inLongitude!.toStringAsFixed(5)}');
      }
      if (s.note != null && s.note!.isNotEmpty) {
        buffer.writeln('  Not: ${s.note}');
      }
      buffer.writeln();
    }

    final th = total.inHours;
    final tm = total.inMinutes % 60;
    buffer.writeln('${'=' * 30}');
    buffer.writeln('TOPLAM SÜRE: ${th}s ${tm}dk');

    await Share.share(buffer.toString(), subject: 'Mesai Kayıtları');
  }
}
