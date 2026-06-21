import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini_ocr_service.dart';

/// Sohbet mesaji.
class ChatMessage {
  final String role; // 'user' veya 'model'
  final String text;
  ChatMessage(this.role, this.text);

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(j['role'] as String, j['text'] as String);
}

/// ════════════════════════════════════════════════════════════════════
///  ASISTAN — "Pia" (SKT Takip kisisel asistani).
///
///  Gemini ile yazili/sesli sohbet eder. API anahtarini GeminiOcrService
///  ile PAYLASIR (kullanici bir kez girer, hem OCR hem asistan kullanir).
///  Sohbet gecmisini bellekte tutar; her istekte tum gecmisi gonderir ki
///  asistan baglami hatirlasin.
/// ════════════════════════════════════════════════════════════════════
class AssistantService {
  AssistantService._();
  static final AssistantService instance = AssistantService._();

  // Asistanin model fallback zinciri (OCR ile ayni, dogrulanmis modeller).
  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
    'gemini-2.0-flash-lite',
  ];

  // Asistanin kisiligi/talimati.
  static const String _systemPrompt = '''
Sen "Pia"sın — SKT Takip uygulamasının kişisel asistanısın. Bir market/depo çalışanına yardım ediyorsun.
Kişiliğin: samimi, kısa ve net konuşan, işini bilen bir yardımcı. Gereksiz uzatmazsın, lafı dolandırmazsın.
Türkçe konuşursun. Cevapların kısa ve pratiktir (genelde 1-3 cümle), çünkü kullanıcı çoğu zaman meşgul ve ayaktadır.
Son kullanma tarihi takibi, raf düzeni, fiyat değişimi, stok, mağaza işleri konularında pratik tavsiyeler verebilirsin.
Emin olmadığın bir şeyde uydurmaz, dürüstçe bilmediğini söylersin.
Sesli okunabileceği için cevaplarında madde işareti, tablo veya uzun liste kullanma; akıcı konuşma dilinde yaz.
''';

  /// Sohbet gecmisi (bellekte; oturum boyunca tutulur).
  final List<ChatMessage> history = [];

  /// Asistana mesaj gonderir, cevabini doner. Tum gecmis baglam olarak gider.
  Future<String> send(String userText) async {
    final key = await GeminiOcrService.instance.getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException(
          'Asistan için Gemini API anahtarı gerekli. Fiyat Değişim ekranındaki '
          'AI ayarından anahtarınızı girin.');
    }

    history.add(ChatMessage('user', userText));

    // Gemini icerik dizisi: sistem talimati + tum gecmis.
    final contents = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      {
        'role': 'model',
        'parts': [
          {'text': 'Anladım, hazırım. Nasıl yardımcı olabilirim?'}
        ]
      },
      ...history.map((m) => {
            'role': m.role,
            'parts': [
              {'text': m.text}
            ]
          }),
    ];

    final body = jsonEncode({
      'contents': contents,
      'generationConfig': {'temperature': 0.7},
    });

    GeminiOcrException? lastError;
    for (final model in _models) {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key');
      http.Response res;
      try {
        res = await http
            .post(uri,
                headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        lastError = GeminiOcrException('Bağlantı hatası: $e');
        continue;
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String?;
        final reply = (text ?? '').trim();
        if (reply.isEmpty) {
          throw const GeminiOcrException('Asistan boş yanıt döndü');
        }
        history.add(ChatMessage('model', reply));
        return reply;
      }

      if (res.statusCode == 404) {
        lastError = GeminiOcrException('Model bulunamadı ($model)');
        continue;
      }
      // Diger hatalar: model degisimi cozmez.
      // user mesajini geri al (basarisiz oldu).
      if (history.isNotEmpty && history.last.role == 'user') {
        history.removeLast();
      }
      throw GeminiOcrException(
          'Asistan hatası (${res.statusCode})');
    }

    if (history.isNotEmpty && history.last.role == 'user') {
      history.removeLast();
    }
    throw lastError ??
        const GeminiOcrException('Asistan yanıt vermedi');
  }

  /// Sohbeti temizler.
  void clear() => history.clear();
}
