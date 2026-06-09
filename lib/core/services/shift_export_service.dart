import 'dart:io';

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
