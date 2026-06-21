import 'dart:convert';

import 'package:http/http.dart' as http;

import 'assistant_data_context.dart';
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
Sen "Pia"sın — kullanıcının kişisel yapay zeka asistanısın. Genel amaçlısın: HER konuda yardım edebilirsin.

NE YAPABİLİRSİN:
- Her türlü soruyu cevaplarsın: genel bilgi, açıklama, fikir, hesap, çeviri, metin yazma, özet, planlama, tavsiye — sınır yok.
- KOD yazabilirsin (her dilde), kod açıklar, hata ayıklar, örnek verirsin. Kodları net biçimde, gerektiğinde kod bloğu olarak yazarsın.
- Aynı zamanda kullanıcının SKT Takip uygulamasının verilerine de erişimin var (ürünler, son kullanma tarihleri, mesai durumu). Uygulamayla ilgili soru gelirse bu veriyi kullanırsın.

KONUŞMA TARZI — ÖNEMLİ:
- NET ve DOĞRUDAN konuş. Boş laf, gereksiz dolgu, "tabii ki yardımcı olabilirim" gibi girişler YOK. Soruyu cevapla, geç.
- Cevabın uzunluğu soruya göre olsun: basit soruya kısa, karmaşık/teknik soruya (örn. kod) gereken kadar detaylı.
- Somut ol; uydurma. Bilmiyorsan dürüstçe söyle.
- Türkçe konuşursun (kullanıcı başka dil isterse o dilde).

VERİ ERİŞİMİ:
- Uygulamayla ilgili sorularda, sana her mesajda "GÜNCEL DURUM" başlığıyla verilen güncel uygulama verisini kullan (ürün sayıları, SKT durumu, mesai). Genel sorularda bu veriyi görmezden gel.
- İnternette canlı arama YAPAMAZSIN; bilgin belli bir tarihe kadar. Çok güncel (bugünün haberi/dövizi gibi) bir şey sorulursa bunu söyle.

KESİN KURAL — UYGULAMA VERİSİ SADECE OKUMA:
- Uygulama verisini sadece GÖRÜRSÜN. Hiçbir ürünü/kaydı ekleyemez, silemez, değiştiremezsin.
- Kullanıcı "şu ürünü sil / tarihi değiştir / ekle" derse: bunu senin yapamayacağını, ilgili ekrandan kendisinin yapması gerektiğini kısaca söyle. Yaptığını İDDİA ETME.
(Bu kural sadece UYGULAMA VERİSİ içindir; kod yazmak, metin üretmek gibi normal asistan işlerinde böyle bir kısıt yoktur.)
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

    // Guncel veri ozetini al (SALT OKUNUR — AssistantDataContext sadece
    // okuma metodlarini cagirir, veriyi degistiremez).
    String dataSummary = '';
    try {
      dataSummary = await AssistantDataContext.instance.buildSummary();
    } catch (_) {
      dataSummary = '';
    }

    // Gemini icerik dizisi: sistem talimati + guncel veri + tum gecmis.
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
          {'text': 'Anladım. Her konuda yardımcı olurum, net konuşurum. Uygulama verisini sadece okurum.'}
        ]
      },
      if (dataSummary.isNotEmpty)
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  '=== GÜNCEL DURUM (uygulamadan, salt okunur) ===\n$dataSummary'
            }
          ]
        },
      if (dataSummary.isNotEmpty)
        {
          'role': 'model',
          'parts': [
            {'text': 'Güncel durumu gördüm.'}
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
