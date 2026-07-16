import '../../data/datasources/barcode_directory_datasource.dart';
import 'database_service.dart';
import 'gemini_ocr_service.dart';
import 'shelf_layout_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  DEPO ASISTANI SERVISI
/// ────────────────────────────────────────────────────────────────────
///  Telefondaki YEREL verilerden (reyon dizilimleri: hangi urun hangi
///  reyon/sutun/raf'ta) bir baglam metni olusturur ve kullanicinin sorusuyla
///  birlikte Gemini'ye gonderir. Gemini once bu yerel veriden cevaplar;
///  yetmezse Google Arama ile internetten arastirir (bkz.
///  GeminiOcrService.assistantAnswer).
///
///  Ornek: "pilavlık bulgur nerede?" -> "Bakliyat reyonu, Sütun 2, Raf 2".
/// ════════════════════════════════════════════════════════════════════
class WarehouseAssistantService {
  WarehouseAssistantService._();
  static final WarehouseAssistantService instance =
      WarehouseAssistantService._();

  /// Baglam metnini cok sismesin diye urun tavani.
  static const int _maxProducts = 500;
  static const int _maxDirectory = 800;

  /// Tum reyonlarin urun+konum ozetini VE kayitli urun dizinini metne
  /// dokerek dondurur. Iki kaynak:
  ///   1) REYON KONUMLARI — hangi urun hangi reyon/sutun/raf'ta (yer sorulari).
  ///   2) KAYITLI URUNLER — barkod dizinindeki tum urunler (ad + stok kodu).
  ///      Reyon konumu olmayan ama sistemde kayitli urunler icin. Boylece
  ///      "bu urun var mi / stok kodu ne" gibi sorulara da cevap verebilir.
  Future<String> buildLocalContext() async {
    final buf = StringBuffer();

    // ── 1) REYON KONUMLARI ──
    final summaries = await ShelfLayoutService.instance.getUnitSummaries();
    final Set<String> placedBarcodes = {};
    if (summaries.isEmpty) {
      buf.writeln('(Henüz reyon/konum kaydı yok.)');
    } else {
      buf.writeln('=== REYON KONUMLARI (ürün → yeri) ===');
      int total = 0;
      for (final s in summaries) {
        final unit = s.unit;
        buf.writeln('# Reyon: ${unit.name} (${unit.sections} sütun)');
        final slots = await ShelfLayoutService.instance.getSlots(unit.id!);
        if (slots.isEmpty) {
          buf.writeln('  (boş)');
          continue;
        }
        for (final sl in slots) {
          if (total >= _maxProducts) {
            buf.writeln('  ... (kısaltıldı)');
            break;
          }
          final name = (sl.productName?.trim().isNotEmpty ?? false)
              ? sl.productName!.trim()
              : sl.barcode;
          buf.writeln(
              '  - $name [${sl.barcode}] → Sütun ${sl.sectionNo}, Raf ${sl.rowNo}');
          placedBarcodes.add(sl.barcode);
          total++;
        }
        if (total >= _maxProducts) break;
      }
    }

    // ── 2) KAYITLI URUNLER (konumu olmayanlar) ──
    // Barkod dizinindeki tum urunler; reyonda zaten listelenenleri tekrar
    // yazmayiz. Bunlarin YERI bilinmez ama sistemde KAYITLIDIR.
    try {
      final all = await BarcodeDirectoryDataSource(DatabaseService.instance)
          .getAll();
      final others = all.where((e) => !placedBarcodes.contains(e.barcode));
      if (others.isNotEmpty) {
        buf.writeln();
        buf.writeln('=== KAYITLI ÜRÜNLER (yeri kayıtlı değil) ===');
        int c = 0;
        for (final e in others) {
          if (c >= _maxDirectory) {
            buf.writeln('  ... (kısaltıldı)');
            break;
          }
          final stok =
              (e.stockCode?.trim().isNotEmpty ?? false) ? ' (stok ${e.stockCode})' : '';
          buf.writeln('  - ${e.productName} [${e.barcode}]$stok');
          c++;
        }
      }
    } catch (_) {}

    final out = buf.toString().trim();
    return out.isEmpty ? '(Kayıtlı veri yok.)' : out;
  }

  /// Kullanicinin sorusunu (gecmisle birlikte) yanitlar.
  /// [history] : [{'role':'user'|'model','text':...}]
  Future<String> ask({
    required List<Map<String, String>> history,
    required String question,
  }) async {
    final context = await buildLocalContext();
    return GeminiOcrService.instance.assistantAnswer(
      context: context,
      history: history,
      question: question,
    );
  }
}
