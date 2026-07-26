import '../services/agent_mode_prefs.dart';
import '../services/warehouse_assistant_service.dart';
import 'agent_core.dart';
import 'agent_llm.dart';
import 'agent_loop.dart';
import 'skt_tools.dart';

/// ════════════════════════════════════════════════════════════════════
///  DEPO AJANI (function-calling orkestratörü) — v172
/// ────────────────────────────────────────────────────────────────────
///  Sohbet ekranını "Ajan" mimarisine bağlar: model artık ```tool/```action
///  METİN blokları yazmaz; Gemini'nin YAPISAL function-calling'ini kullanır.
///  Böylece "araç tanımlı değil / blok bozuk / yarım cevap" sorunları biter.
///
///  SKT Takip'in TÜM sorgu yetenekleri korunur: güncel depo verisi sistem
///  istemine gömülür (anlık "nerede/SKT/stok" cevabı) + derin keşif için
///  db_query/db_schema/warehouse_data araçları hazır. Değişiklikler tek kapı
///  olan app_action aracından geçer; okuma araçları AgentToolService'e gider.
/// ════════════════════════════════════════════════════════════════════
class WarehouseAgent {
  WarehouseAgent._();
  static final WarehouseAgent instance = WarehouseAgent._();

  final AgentLlm _llm = AgentLlm();
  final Map<String, AgentTool> _tools = buildSktTools();

  /// Sohbet ekranının çağırdığı ana giriş. [history] eleman biçimi:
  /// {'role':'user'|'model','text':...}. Nihai Türkçe metni döndürür
  /// (içinde [[urun:BARKOD|AD]] atıfları olabilir — UI kartlara çevirir).
  Future<String> ask({
    required List<Map<String, String>> history,
    required String question,
    int maxSteps = 12,
    void Function(String note)? onStep,
  }) async {
    final context = await WarehouseAssistantService.instance.buildLocalContext();
    final loop = AgentLoop(
      llm: _llm,
      tools: _tools,
      systemPrompt: _systemPrompt(context),
      maxSteps: maxSteps,
    );

    final msgs = <AgentMsg>[
      for (final m in history)
        AgentMsg(
          role: (m['role'] == 'user') ? AgentRole.user : AgentRole.assistant,
          text: m['text'] ?? '',
        ),
      AgentMsg(role: AgentRole.user, text: question),
    ];

    return loop.run(msgs, onStep: onStep);
  }

  String _systemPrompt(String context) {
    final free = AgentModePrefs.instance.freeMode;
    return 'Sen SKT Takip uygulamasının içinde çalışan, uygulamaya TAM HÂKİM '
        'bir Türkçe asistanısın (agent). SKT/son kullanma takibi, barkod '
        'dizini, depo-palet-raf yönetimi, reyon dizilimi, teşhir, reyona '
        'açılacaklar, yedekleme, fiyat akışları, etiket kuyruğu, sayım, '
        'vardiya, alarmlar/çalışma programı ve tüm uygulama ayarları senin '
        'yetki alanındadır. ASLA "bu özelliğim yok / yapamam" DEME; gerekeni '
        'ARAÇLARLA yap.\n\n'
        'ARAÇLAR (yapısal function-calling): Bilgi için warehouse_data / '
        'db_query / db_schema; telefon için run_shell / list_apps / '
        'read_screen; her türlü DEĞİŞİKLİK için app_action (tek kapı — ürün '
        'ekle/güncelle/imha, palet, rafa yerleştir, yedek, alarm, tema/kilit, '
        'uygulama aç, terminal komutu...). Riskli/geri alınamaz işlemden önce '
        'confirm çağır. Tablo/kolon adını TAHMİN ETME; önce db_schema. Bir '
        'şey yapacaksan konuşmadan O ANDA aracı çağır; "bakıyorum/birazdan" '
        'deyip durma.\n\n'
        '${free ? 'SERBEST MOD AÇIK: kısıt yok, onay isteme, kullanıcı ne '
            'isterse doğrudan yap (confirm otomatik onaylanır).\n\n' : ''}'
        'YAZIM: Kullanıcı çoğu kez sesli yazdırır; harf hatalarına takılma, '
        'NİYETİ anla. Kısa, net, Türkçe yanıt ver; uydurma.\n\n'
        'ÜRÜN ATIFI: Sistemde kayıtlı bir üründen bahsederken cevabının '
        'içine AYRI BİR SATIR olarak [[urun:BARKOD|GÖRÜNEN AD]] yaz '
        '(örn. [[urun:8691573091087|Burcu Domates Rendesi 685g]]). Uygulama '
        'bunu FOTOĞRAFLI, tıklanabilir ürün kartına çevirir. Yer/SKT/stok '
        'cevaplarında ilgili ürün(ler) için MUTLAKA ekle; barkodu aşağıdaki '
        'listelerdeki köşeli parantezden al, UYDURMA.\n\n'
        '=== DEPONUN GÜNCEL VERİSİ (anlık cevap için) ===\n'
        '$context\n'
        '=== VERİ SONU ===\n'
        'Yukarıdaki veri yeterliyse doğrudan cevapla; daha derin sayım/'
        'filtre/geçmiş gerekiyorsa db_query/warehouse_data çağır.';
  }
}
