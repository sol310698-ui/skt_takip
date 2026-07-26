/// ════════════════════════════════════════════════════════════════════
///  FUNCTION-CALLING AJAN ÇEKİRDEĞİ (v172)
/// ────────────────────────────────────────────────────────────────────
///  "Ajan" projesinin (sol310698-ui/ajan) temiz function-calling mimarisi
///  SKT Takip'e uyarlandı. Model artık ```tool/```action METİN blokları
///  yazmaz; Gemini'nin YAPISAL function-calling mekanizmasını kullanır.
///  Böylece "araç adı uydurma / blok bozuk" sorunları kökten biter.
///
///  Araçlar SKT Takip'in MEVCUT servislerini sarar (AgentToolService,
///  AssistantActionService, WarehouseAssistantService) — hiçbir yetenek
///  kaybolmaz, tüm sorgu ve eylemler korunur.
/// ════════════════════════════════════════════════════════════════════

enum AgentRole { user, assistant, tool }

/// Bir aracin cagrilma istegi (LLM uretir).
class AgentToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  AgentToolCall({required this.id, required this.name, required this.args});
}

/// Bir aracin calisma sonucu.
class AgentToolResult {
  final String callId;
  final String name;
  final bool ok;
  final String output;
  AgentToolResult({
    required this.callId,
    required this.name,
    required this.ok,
    required this.output,
  });
}

/// Sohbetteki tek bir mesaj (hem UI hem LLM geçmişi).
class AgentMsg {
  final AgentRole role;
  final String text;
  final List<AgentToolCall> toolCalls;
  final AgentToolResult? toolResult;
  final DateTime time;

  AgentMsg({
    required this.role,
    this.text = '',
    this.toolCalls = const [],
    this.toolResult,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Ajanin kullanabilecegi tek bir yetenek (arac).
/// Yeni yetenek = bu sinifi genislet + registry'e ekle.
abstract class AgentTool {
  /// LLM'in cagirirken kullanacagi ad (snake_case).
  String get name;

  /// Modelin ne zaman kullanacagini anlamasi icin net aciklama.
  String get description;

  /// Parametre semasi (Gemini "parameters" / JSON Schema).
  Map<String, dynamic> get parameters;

  /// Araci calistirir. Donen metin MODELE geri beslenir → kisa/ozet olmali.
  Future<String> run(Map<String, dynamic> args);

  /// Gemini functionDeclarations formatina cevirir.
  Map<String, dynamic> toDeclaration() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}
