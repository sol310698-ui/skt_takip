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

  // Asistan model zinciri: en iyi/akilli olandan baslar (sohbet kalitesi
  // icin Pro birincil), gerekirse Flash'a duser. Hepsi kullanicinin
  // anahtarinda dogrulanmis modeller.
  static const List<String> _models = [
    'gemini-2.5-pro',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
  ];

  // Asistanin kisiligi/talimati.
  static const String _systemPrompt = '''
Sen "Pia"sın — SKT Takip uygulamasının akıllı kişisel asistanısın. Bir market/depo çalışanına ve yöneticisine yardım ediyorsun.

KİŞİLİĞİN: Sıcak, samimi, işini iyi bilen, güvenilir bir yardımcı. Türkçe konuşursun. Doğal ve akıcı konuşma dili kullanırsın, robotik değilsin.

NASIL CEVAP VERİRSİN:
- Soruyu gerçekten anla ve DOLU, FAYDALI cevap ver. Kullanıcının işine yarayacak somut bilgi, öneri ve örnek sun.
- Cevabın soruya göre olsun: basit soruya kısa, karmaşık/açık uçlu soruya detaylı ve açıklayıcı cevap ver. Gereksiz yere kısaltma, ama gereksiz yere de uzatma.
- Bir konuda uzmanlık gerekiyorsa (gıda güvenliği, raf ömrü, stok yönetimi, fiyatlandırma, mağazacılık) bilgini paylaş, mantığını açıkla.
- Pratik ol: "şunu yapabilirsin", "şuna dikkat et", "şöyle bir yöntem var" gibi uygulanabilir tavsiyeler ver.
- Emin olmadığın bir şeyi uydurma; bilmiyorsan dürüstçe söyle ve nasıl öğrenebileceğini öner.
- Önceki mesajları hatırla, sohbetin bağlamını takip et.

BİÇİM: Sesli de okunabildiğin için, çok uzun maddeli listeler veya tablolar yerine akıcı paragraflar tercih et. Ama bir şeyi adım adım anlatman gerekiyorsa kısa ve net adımlar verebilirsin.

Amacın kullanıcının işini kolaylaştırmak ve ona gerçekten değerli, düşünülmüş cevaplar vermek.
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
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.95,
      },
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
            .timeout(const Duration(seconds: 60));
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
