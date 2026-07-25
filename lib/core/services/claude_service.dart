import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'ai_provider_prefs.dart';
import 'gemini_ocr_service.dart' show GeminiOcrException;

/// ════════════════════════════════════════════════════════════════════
///  CLAUDE (ANTHROPIC) SERVİSİ
/// ────────────────────────────────────────────────────────────────────
///  Depo Asistanı sohbetini Anthropic Claude ile yanıtlar. Araç/eylem
///  protokolü Gemini ile AYNIDIR (metin içi ```tool / ```action blokları),
///  bu yüzden agent döngüsü ve ayrıştırıcılar hiç değişmeden çalışır.
///
///  API anahtarı cihazda şifreli saklanır (flutter_secure_storage).
///  Anahtar: console.anthropic.com → API Keys.
///
///  Not: A4/OCR (görsel) okuma Claude'a taşınMAZ; o akışlar Gemini'de
///  kalır. Bu servis yalnızca sohbet/agent içindir.
/// ════════════════════════════════════════════════════════════════════
class ClaudeService {
  ClaudeService._();
  static final ClaudeService instance = ClaudeService._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'claude_api_key';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<void> setApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());
  Future<void> clearApiKey() => _storage.delete(key: _keyName);
  Future<bool> hasApiKey() async {
    final k = await getApiKey();
    return k != null && k.isNotEmpty;
  }

  /// Depo Asistanı yanıtı. [system] ortak sistem yönergesi (preamble),
  /// [history] önceki mesajlar ({'role':'user'|'model','text':...}),
  /// [question] son kullanıcı sorusu. Döndürdüğü metin ```tool/```action
  /// bloklarını içerebilir (Gemini ile aynı sözleşme).
  Future<String> assistantAnswer({
    required String system,
    required List<Map<String, String>> history,
    required String question,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('Claude API anahtarı yok');
    }

    // Anthropic mesaj biçimi: roller 'user' | 'assistant'.
    final messages = <Map<String, dynamic>>[];
    for (final m in history) {
      final role = m['role'] == 'user' ? 'user' : 'assistant';
      final text = m['text'] ?? '';
      if (text.trim().isEmpty) continue;
      messages.add({'role': role, 'content': text});
    }
    messages.add({'role': 'user', 'content': question});
    // İlk mesaj 'user' olmalı; boş/model ile başlarsa düzelt.
    if (messages.isEmpty || messages.first['role'] != 'user') {
      messages.insert(0, {'role': 'user', 'content': '(başlangıç)'});
    }

    final body = jsonEncode({
      'model': AiProviderPrefs.instance.claudeModel,
      'max_tokens': 4096,
      'system': system,
      'messages': messages,
    });

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': _version,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw GeminiOcrException('Bağlantı hatası: $e');
    }

    if (res.statusCode == 200) {
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final text = _extractText(data);
      if (text.trim().isNotEmpty) return text;
      final stop = data['stop_reason'];
      if (stop == 'refusal') {
        return 'Bu isteği güvenlik nedeniyle yanıtlayamadım.';
      }
      throw GeminiOcrException('Claude boş yanıt döndü'
          '${stop == null ? '' : ' ($stop)'}');
    }

    // Hata: anlaşılır mesaj.
    if (res.statusCode == 401) {
      throw const GeminiOcrException(
          'Claude API anahtarı geçersiz (401). Ayarlar\'dan kontrol edin.');
    }
    throw GeminiOcrException(
        'Claude hatası (${res.statusCode}): ${_shortError(res.body)}');
  }

  /// Yanıttaki tüm 'text' bloklarını birleştirir (thinking/araç bloklarını
  /// atlar).
  static String _extractText(Map<String, dynamic> data) {
    final buf = StringBuffer();
    final content = data['content'];
    if (content is List) {
      for (final b in content) {
        if (b is Map && b['type'] == 'text') {
          final t = b['text'];
          if (t is String) buf.write(t);
        }
      }
    }
    return buf.toString();
  }

  static String _shortError(String body) {
    try {
      final m = jsonDecode(body);
      final msg = m['error']?['message'];
      if (msg is String) {
        return msg.length > 120 ? msg.substring(0, 120) : msg;
      }
    } catch (_) {}
    return body.length > 120 ? body.substring(0, 120) : body;
  }
}
