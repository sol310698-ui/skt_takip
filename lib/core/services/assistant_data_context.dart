import 'package:intl/intl.dart';

import '../../data/datasources/product_local_datasource.dart';
import '../../data/datasources/shift_local_datasource.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/shift_repository.dart';
import '../../data/repositories/barcode_directory_repository.dart';
import '../../data/models/product.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  ASISTAN VERI BAGLAMI — KESINLIKLE SALT OKUNUR.
///
///  Pia'ya gonderilecek veri ozetini uretir. Bu servis SADECE okuma
///  metodlarini cagirir (getActive, getOpenShift, count...). Hicbir yazma/
///  silme/guncelleme metodu BURADA cagrilamaz; dolayisiyla asistanin veriyi
///  degistirmesi MIMARI olarak imkansizdir. Asistan yalnizca bu metnin
///  uretildigi anlik fotografi gorur.
/// ════════════════════════════════════════════════════════════════════
class AssistantDataContext {
  AssistantDataContext._();
  static final AssistantDataContext instance = AssistantDataContext._();

  ProductRepository get _products =>
      ProductRepository(ProductLocalDataSource(DatabaseService.instance));
  ShiftRepository get _shifts =>
      ShiftRepository(ShiftLocalDataSource(DatabaseService.instance));
  BarcodeDirectoryRepository get _barcodes => BarcodeDirectoryRepository(
      BarcodeDirectoryDataSource(DatabaseService.instance));

  /// Asistana gonderilecek, o anki durumu ozetleyen METIN.
  /// Hata olursa bos/eksik ozet doner (asistan yine de calisir).
  Future<String> buildSummary() async {
    final df = DateFormat('dd.MM.yyyy');
    final now = DateTime.now();
    final buf = StringBuffer();

    try {
      final active = await _products.getProducts();

      // Durum sayilari.
      int expired = 0, today = 0, week = 0, safe = 0;
      final soonest = <Product>[];
      for (final p in active) {
        final d = p.expiryDate;
        final days = DateTime(d.year, d.month, d.day)
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        if (days < 0) {
          expired++;
        } else if (days == 0) {
          today++;
        } else if (days <= 7) {
          week++;
        } else {
          safe++;
        }
        soonest.add(p);
      }
      // En yakin dolacak 10 urun.
      soonest.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      final top = soonest.take(10).toList();

      buf.writeln('=== GÜNCEL ÜRÜN DURUMU (${df.format(now)}) ===');
      buf.writeln('Toplam aktif ürün: ${active.length}');
      buf.writeln('Süresi dolmuş: $expired');
      buf.writeln('Bugün dolan: $today');
      buf.writeln('Bu hafta (7 gün) dolacak: $week');
      buf.writeln('Güvenli (7 günden uzak): $safe');
      buf.writeln('');
      if (top.isNotEmpty) {
        buf.writeln('En yakın dolacak ürünler:');
        for (final p in top) {
          final loc = (p.location != null && p.location!.isNotEmpty)
              ? ' [${p.location}]'
              : '';
          final cat = (p.category != null && p.category!.isNotEmpty)
              ? ' (${p.category})'
              : '';
          buf.writeln(
              '- ${p.name}$cat — SKT ${df.format(p.expiryDate)}, ${p.quantity} adet$loc');
        }
        buf.writeln('');
      }
    } catch (_) {
      buf.writeln('(Ürün verisi okunamadı.)');
    }

    try {
      final open = await _shifts.getOpenShift();
      if (open != null) {
        buf.writeln(
            'Mesai durumu: AÇIK — ${DateFormat('HH:mm').format(open.clockIn)} itibarıyla mesaide.');
      } else {
        buf.writeln('Mesai durumu: Açık vardiya yok (mesaide değil).');
      }
    } catch (_) {}

    try {
      final dirCount = await _barcodes.count();
      buf.writeln('Barkod rehberinde kayıtlı ürün: $dirCount');
    } catch (_) {}

    return buf.toString().trim();
  }
}
