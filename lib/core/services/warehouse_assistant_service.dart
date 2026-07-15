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

  /// Tum reyonlarin urun+konum ozetini metne dokerek dondurur.
  Future<String> buildLocalContext() async {
    final summaries = await ShelfLayoutService.instance.getUnitSummaries();
    if (summaries.isEmpty) {
      return '(Henüz reyon/ürün kaydı yok.)';
    }

    final buf = StringBuffer();
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
          buf.writeln('  ... (daha fazla ürün var, kısaltıldı)');
          break;
        }
        final name = (sl.productName?.trim().isNotEmpty ?? false)
            ? sl.productName!.trim()
            : sl.barcode;
        buf.writeln(
            '  - $name [${sl.barcode}] → Sütun ${sl.sectionNo}, Raf ${sl.rowNo}');
        total++;
      }
      if (total >= _maxProducts) break;
    }
    return buf.toString();
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
