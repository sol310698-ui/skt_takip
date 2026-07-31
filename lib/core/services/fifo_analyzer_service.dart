import '../constants/app_constants.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  FIFO / FEFO ANALIZ SERVISI
/// ────────────────────────────────────────────────────────────────────
///  Amac: AYNI urunun (barkod) DEPO/PALET (arka stok) ve REYON (musteriye
///  acik on stok) partilerinin son kullanma tarihlerini karsilastirir ve
///  "yer degistirmesi gereken" durumlari — yani FIFO/FEFO ihlallerini —
///  KESIN sekilde tespit eder.
///
///  FIFO/FEFO kurali: musteriye en yakin (reyondaki) stok, EN ERKEN son
///  kullanma tarihli olmali; daha uzun omurlu stok arkada (palette)
///  beklemeli. Eger palette reyondan DAHA ERKEN tarihli ayni urun varsa,
///  o erken tarihli stok arkada kalmis demektir -> once o satisa/reyona
///  cikarilmali, yerleri degismeli.
///
///  Ornek: palette 01.01.2026, reyonda 01.05.2026 olan ayni urun ->
///  "FIFO yapilmamis; paletteki 01.01.2026 stok reyona alinmali."
///
///  Tespit tamamen VERIDEN hesaplanir (products tablosu; her satir bir
///  parti: barcode + expiry_date + location_type 'pallet'/'shelf'). Sonuc
///  asistan baglamina eklenir; boylece yapay zeka bu onerileri kendisi
///  profesyonelce dile getirebilir (bkz. WarehouseAssistantService —
///  buildLocalContext icine proaktif olarak eklenir). Ayri bir "arac"
///  degildir: deterministik hesap yalnizca dogruluk icindir; model isterse
///  ayni karsilastirmayi db_query ile de yapabilir.
/// ════════════════════════════════════════════════════════════════════
class FifoAnalyzerService {
  FifoAnalyzerService._();
  static final FifoAnalyzerService instance = FifoAnalyzerService._();

  /// Baglami sismesin diye en fazla bu kadar bulgu dokulur (en ciddi once).
  static const int _maxFindings = 40;

  /// Aktif tum partileri (palet + reyon) cekip barkoda gore gruplar,
  /// ihlalleri en ciddi once sirali dondurur.
  Future<List<FifoFinding>> analyze() async {
    final db = await DatabaseService.instance.database;

    // Tek sorguda: her aktif parti + cozulmus konum etiketi.
    // pallet -> palet kodu, shelf -> reyon adi (+ sutun/raf).
    final rows = await db.rawQuery('''
      SELECT p.barcode      AS barcode,
             p.name         AS name,
             p.expiry_date  AS expiry_date,
             p.quantity     AS quantity,
             p.location_type AS ltype,
             wp.code        AS pallet_code,
             su.name        AS shelf_name,
             ss.section_no  AS sec,
             ss.row_no      AS rowno
      FROM ${AppConstants.productTable} p
      LEFT JOIN ${AppConstants.whPalletItemTable} i
             ON p.location_type = 'pallet' AND p.location_ref = i.id
      LEFT JOIN ${AppConstants.whPalletTable} wp
             ON i.pallet_id = wp.id
      LEFT JOIN ${AppConstants.shelfSlotTable} ss
             ON p.location_type = 'shelf' AND p.location_ref = ss.id
      LEFT JOIN ${AppConstants.shelfUnitTable} su
             ON ss.unit_id = su.id
      WHERE p.disposal_status = 'active'
        AND p.barcode IS NOT NULL AND p.barcode <> ''
        AND (p.location_type = 'pallet' OR p.location_type = 'shelf')
    ''');

    // Barkoda gore grupla.
    final byBarcode = <String, _Group>{};
    for (final r in rows) {
      final barcode = (r['barcode'] as String).trim();
      if (barcode.isEmpty) continue;
      final g = byBarcode.putIfAbsent(barcode, () => _Group(barcode));
      final batch = _Batch(
        name: (r['name'] as String?)?.trim() ?? '',
        expiry: DateTime.fromMillisecondsSinceEpoch(r['expiry_date'] as int),
        quantity: (r['quantity'] as int?) ?? 0,
        label: _label(r),
      );
      if (r['ltype'] == 'shelf') {
        g.shelf.add(batch);
      } else {
        g.pallet.add(batch);
      }
      if (g.name.isEmpty && batch.name.isNotEmpty) g.name = batch.name;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final findings = <FifoFinding>[];

    for (final g in byBarcode.values) {
      // Ihlal ancak urun HEM reyonda HEM palette varsa mumkun.
      if (g.shelf.isEmpty || g.pallet.isEmpty) continue;

      // Reyondaki EN ERKEN tarih (musteriye acik on stogun en iyisi).
      g.shelf.sort((a, b) => a.expiry.compareTo(b.expiry));
      g.pallet.sort((a, b) => a.expiry.compareTo(b.expiry));
      final shelfFront = g.shelf.first; // reyonun en erken tarihlisi

      // Palette, reyondaki en erken tarihten DAHA ERKEN parti var mi?
      // (Varsa arkada erken tarihli stok bekliyor demektir = ihlal.)
      final offending = g.pallet.first; // paletin en erken tarihlisi
      final gapDays =
          _dayOnly(shelfFront.expiry).difference(_dayOnly(offending.expiry)).inDays;
      if (gapDays <= 0) continue; // palet reyondan erken degil -> sorun yok

      final palletDaysLeft =
          _dayOnly(offending.expiry).difference(today).inDays;
      final severity = _severity(gapDays: gapDays, palletDaysLeft: palletDaysLeft);

      findings.add(FifoFinding(
        barcode: g.barcode,
        productName: g.name.isEmpty ? g.barcode : g.name,
        shelfExpiry: shelfFront.expiry,
        shelfLabel: shelfFront.label,
        palletExpiry: offending.expiry,
        palletLabel: offending.label,
        palletQuantity: offending.quantity,
        gapDays: gapDays,
        palletDaysLeft: palletDaysLeft,
        severity: severity,
      ));
    }

    // En ciddi once: once oncelik, sonra buyuk fark.
    findings.sort((a, b) {
      final s = b.severity.rank.compareTo(a.severity.rank);
      if (s != 0) return s;
      return b.gapDays.compareTo(a.gapDays);
    });
    if (findings.length > _maxFindings) {
      return findings.sublist(0, _maxFindings);
    }
    return findings;
  }

  /// Asistan baglamina eklenecek metin blogu. Ihlal yoksa BOS string doner
  /// (baglam sismesin). WarehouseAssistantService bunu context'e ekler.
  Future<String> promptBlock() async {
    List<FifoFinding> findings;
    try {
      findings = await analyze();
    } catch (_) {
      return '';
    }
    if (findings.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('=== FIFO/FEFO UYARILARI (otomatik tespit) ===');
    buf.writeln(
        'Asagidaki urunlerde DEPO/PALET stogu, REYONDAKI stoktan DAHA ERKEN '
        'son kullanma tarihli. FIFO/FEFO geregi once erken tarihli (depodaki) '
        'stok satisa/reyona cikmali; yerleri degistirilmeli.');
    for (final f in findings) {
      buf.writeln('- ${f.productName} [${f.barcode}]: '
          'reyon ${_fmt(f.shelfExpiry)} (${f.shelfLabel}), '
          'palet ${_fmt(f.palletExpiry)} (${f.palletLabel})'
          ' → paletteki stok ${f.gapDays} gun DAHA ERKEN'
          '${f.palletQuantity > 0 ? ', ${f.palletQuantity} adet' : ''}. '
          'Oncelik: ${f.severity.label}'
          '${f.palletDaysLeft < 0 ? ' (palet stogu SURESI GECMIS!)' : f.palletDaysLeft <= AppConstants.criticalDays ? ' (palet ${f.palletDaysLeft} gun icinde doluyor!)' : ''}.');
    }
    return buf.toString().trim();
  }

  // ── yardimcilar ─────────────────────────────────────────────────────

  static String _label(Map<String, Object?> r) {
    if (r['ltype'] == 'pallet') {
      final code = (r['pallet_code'] as String?)?.trim();
      return code != null && code.isNotEmpty ? 'Palet $code' : 'Palet';
    }
    final name = (r['shelf_name'] as String?)?.trim();
    final sec = r['sec'] as int?;
    final row = r['rowno'] as int?;
    if (name != null && name.isNotEmpty) {
      if (sec != null && row != null) {
        return '$name, Sütun $sec, Raf $row';
      }
      return name;
    }
    return 'Reyon';
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static FifoSeverity _severity(
      {required int gapDays, required int palletDaysLeft}) {
    // Palet stogu gecmis/kritikse ya da fark cok buyukse -> yuksek oncelik.
    if (palletDaysLeft < 0 ||
        palletDaysLeft <= AppConstants.criticalDays ||
        gapDays >= 60) {
      return FifoSeverity.high;
    }
    if (palletDaysLeft <= AppConstants.warningDays || gapDays >= 21) {
      return FifoSeverity.medium;
    }
    return FifoSeverity.low;
  }
}

/// Bir FIFO/FEFO ihlali bulgusu.
class FifoFinding {
  final String barcode;
  final String productName;
  final DateTime shelfExpiry; // reyonun en erken tarihi
  final String shelfLabel;
  final DateTime palletExpiry; // paletin (arkada bekleyen) en erken tarihi
  final String palletLabel;
  final int palletQuantity;
  final int gapDays; // palet, reyondan kac gun daha erken
  final int palletDaysLeft; // palet stogunun bugune gore kalan gunu
  final FifoSeverity severity;

  const FifoFinding({
    required this.barcode,
    required this.productName,
    required this.shelfExpiry,
    required this.shelfLabel,
    required this.palletExpiry,
    required this.palletLabel,
    required this.palletQuantity,
    required this.gapDays,
    required this.palletDaysLeft,
    required this.severity,
  });
}

enum FifoSeverity {
  low,
  medium,
  high;

  int get rank => index;

  String get label {
    switch (this) {
      case FifoSeverity.high:
        return 'yüksek';
      case FifoSeverity.medium:
        return 'orta';
      case FifoSeverity.low:
        return 'düşük';
    }
  }
}

// ── ic yardimci tipler ────────────────────────────────────────────────
class _Group {
  final String barcode;
  String name = '';
  final List<_Batch> shelf = [];
  final List<_Batch> pallet = [];
  _Group(this.barcode);
}

class _Batch {
  final String name;
  final DateTime expiry;
  final int quantity;
  final String label;
  const _Batch({
    required this.name,
    required this.expiry,
    required this.quantity,
    required this.label,
  });
}
