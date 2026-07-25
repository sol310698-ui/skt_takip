import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/datasources/product_local_datasource.dart';
import '../../data/datasources/shift_local_datasource.dart';
import 'database_service.dart';
import 'agent_memory_service.dart';
import 'agent_tool_service.dart';
import 'gemini_ocr_service.dart';
import 'label_pending_queue_service.dart';
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

    // ── 3) SKT TAKIBI (yaklasan son kullanma tarihleri) ──
    // "Bu hafta SKT'si dolan var mi?" gibi sorular icin.
    try {
      final products =
          await ProductLocalDataSource(DatabaseService.instance).getActive();
      if (products.isNotEmpty) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        // En yakin tarihli 120 urun yeterli; tamami baglami sisirir.
        final sorted = [...products]
          ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
        buf.writeln();
        buf.writeln(
            '=== SKT TAKİBİ (son kullanma tarihleri, en yakın önce) ===');
        int c = 0;
        for (final p in sorted) {
          if (c >= 120) {
            buf.writeln('  ... (kısaltıldı)');
            break;
          }
          final d = DateTime(
              p.expiryDate.year, p.expiryDate.month, p.expiryDate.day);
          final diff = d.difference(today).inDays;
          final durum = diff < 0
              ? 'SÜRESİ GEÇTİ (${-diff} gün önce)'
              : diff == 0
                  ? 'BUGÜN DOLUYOR'
                  : '$diff gün kaldı';
          buf.writeln(
              '  - ${p.name}${p.barcode != null ? ' [${p.barcode}]' : ''} — '
              '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
              '($durum, ${p.quantity} adet'
              '${p.location != null ? ', konum: ${p.location}' : ''})');
          c++;
        }
      }
    } catch (_) {}

    // ── 4) VARDIYA + ETIKET KUYRUGU (kisa durum) ──
    try {
      final open =
          await ShiftLocalDataSource(DatabaseService.instance).getOpenShift();
      final pending = await LabelPendingQueueService.instance.pendingCount();
      buf.writeln();
      buf.writeln('=== DURUM ===');
      buf.writeln(open != null
          ? '  - Vardiya: AÇIK (giriş ${open.clockIn})'
          : '  - Vardiya: kapalı / giriş yapılmamış');
      buf.writeln('  - Etiket basım kuyruğu: $pending ürün bekliyor');
    } catch (_) {}

    final out = buf.toString().trim();
    // AJAN HAFIZASI: ogrenilen kurallar/hatalar baglama eklenir ki
    // kullanici ayni hatayi tekrar etmeden ONCE uyarilabilsin.
    final learned = await AgentMemoryService.instance.promptBlock();
    final baseCtx = out.isEmpty ? '(Kayıtlı veri yok.)' : out;
    return learned.isEmpty ? baseCtx : '$baseCtx\n\n$learned';
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

  /// ══════════════════════════════════════════════════════════════════
  ///  AGENT DONGUSU (v146)
  ///  Model tek seferde cevap vermek zorunda degil: ```tool bloklariyla
  ///  ARAC cagirir (sema kesfi, SQL okuma, ayar listeleme), biz calistirip
  ///  sonucu geri veririz, o da devam eder. Boylece "bu ozellik yok"
  ///  durumu kalkar — model uygulamanin tum verisini kesfedip kendi
  ///  cozumunu uretir. En fazla [maxSteps] tur; yazma islemleri yine
  ///  ```action onay kartlariyla yapilir.
  /// ══════════════════════════════════════════════════════════════════
  Future<String> askAgent({
    required List<Map<String, String>> history,
    required String question,
    int maxSteps = 4,
    void Function(String note)? onStep,
  }) async {
    final context = await buildLocalContext();
    var hist = List<Map<String, String>>.from(history);
    var q = question;
    var answer = '';
    var lastResults = ''; // son arac ciktilari (hata halinde yedek cevap)

    for (var step = 0; step < maxSteps; step++) {
      try {
        answer = await GeminiOcrService.instance.assistantAnswer(
          context: context,
          history: hist,
          question: q,
        );
      } catch (e) {
        // ILK adimda hata olursa cagirana bildir (anahtar/kota vb.).
        if (step == 0) rethrow;
        // SONRAKI adimlarda: elimizde arac sonuclari var; her seyi
        // cope atmak yerine ham veriyi kullaniciya goster.
        return 'Topladığım bilgiler:\n\n$lastResults\n\n'
            '(Yanıtı derlerken bağlantı sorunu oldu: $e)';
      }
      final parsed = AgentToolService.instance.parse(answer);
      if (parsed.calls.isEmpty) return answer; // arac yok -> nihai cevap

      // Model AYNI turda hem arac hem EYLEM (```action) urettiyse: eylem,
      // modelin "artik yapmaya hazirim" demesidir. Arac dongusunde
      // devam edersek bu eylem bloklari sessizce KAYBOLUR (asla onay
      // kartina donusmez). Bu yuzden eylem varsa donguyu kesip cevabi
      // oldugu gibi don — UI arac bloklarini temizleyip eylemi gosterir.
      if (answer.contains('```action')) return answer;

      // Kullaniciya "ne yapiyor" bilgisi (yazi baloncugu degil, ipucu).
      onStep?.call(parsed.calls.map((c) => c.name).join(', '));

      final results = await AgentToolService.instance.runAll(parsed.calls);
      lastResults = results;

      // Bu turu gecmise yaz, sonuclari yeni "soru" olarak besle.
      hist = [
        ...hist,
        {'role': 'user', 'text': q},
        {'role': 'model', 'text': answer},
      ];
      q = 'ARAÇ SONUÇLARI:\n$results\n\n'
          'Bu sonuçlara göre kullanıcının isteğini yerine getir. '
          'Gerekiyorsa yeni bir ```tool çağır; bilgi yeterliyse Türkçe '
          'cevabı yaz ve değişiklik gerekiyorsa ```action bloğu üret.';
    }
    // Adim siniri doldu: kalan arac bloklarini temizleyip dondur.
    final tail = AgentToolService.instance.parse(answer).cleanText;
    if (tail.trim().isNotEmpty) return tail;
    // Model hala arac cagiriyorduysa en azindan topladigimizi goster.
    return lastResults.isEmpty
        ? 'İsteğini tamamlayamadım; biraz daha açık yazar mısın?'
        : 'Topladığım bilgiler:\n\n$lastResults';
  }
}
