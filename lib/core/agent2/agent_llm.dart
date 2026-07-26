import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../services/ai_model_prefs.dart';
import '../services/gemini_ocr_service.dart' show GeminiOcrService;
import 'agent_core.dart';

/// Gemini function-calling istemcisi (otomatik yeniden deneme ile).
/// Anahtar ve model SKT Takip'in mevcut tercihlerinden gelir
/// (GeminiOcrService anahtarı + AiModelPrefs modeli).
class AgentLlm {
  final int maxRetries;
  AgentLlm({this.maxRetries = 3});

  /// Gemini function-calling'i güvenilir destekleyen modeller.
  static const List<String> _fallback = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
  ];

  List<String> get _models {
    final sel = AiModelPrefs.instance.selected;
    return [
      if (sel != null && sel.isNotEmpty) sel,
      ..._fallback.where((m) => m != sel),
    ];
  }

  Future<AgentMsg> send({
    required List<AgentMsg> history,
    required String systemPrompt,
    required List<Map<String, dynamic>> toolDeclarations,
  }) async {
    final key = await GeminiOcrService.instance.getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('Gemini API anahtarı yok');
    }

    final bodyMap = {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': _toContents(history),
      'tools': [
        {'functionDeclarations': toolDeclarations}
      ],
      // 2.5 ailesinde "dusunme" butcesi metinsiz yanit birakabilir → kapat.
      'generationConfig': {'temperature': 0.4},
    };

    Object? lastErr;
    for (final model in _models) {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:generateContent?key=$key');
      final tuned = Map<String, dynamic>.from(bodyMap);
      if (model.startsWith('gemini-2.5')) {
        tuned['generationConfig'] = {
          'temperature': 0.4,
          'thinkingConfig': {'thinkingBudget': 0},
          'maxOutputTokens': 8192,
        };
      }
      final body = jsonEncode(tuned);

      for (var attempt = 0; attempt < maxRetries; attempt++) {
        try {
          final res = await http
              .post(uri,
                  headers: {'Content-Type': 'application/json'}, body: body)
              .timeout(const Duration(seconds: 60));
          if (res.statusCode >= 500 || res.statusCode == 429) {
            lastErr = 'API ${res.statusCode}';
            await _backoff(attempt);
            continue;
          }
          // 404/400 → bu model reddetti, SONRAKI modeli dene.
          if (res.statusCode == 404 || res.statusCode == 400) {
            lastErr = 'Model reddetti ($model): ${_short(res.body)}';
            break;
          }
          if (res.statusCode != 200) {
            throw GeminiOcrException(
                'Gemini hatası (${res.statusCode}): ${_short(res.body)}');
          }
          final data =
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          return _parse(data);
        } on SocketException catch (e) {
          lastErr = e;
          await _backoff(attempt);
        } on HttpException catch (e) {
          lastErr = e;
          await _backoff(attempt);
        } on IOException catch (e) {
          lastErr = e;
          await _backoff(attempt);
        }
      }
    }
    throw GeminiOcrException('Bağlantı kurulamadı. [$lastErr]');
  }

  Future<void> _backoff(int attempt) async {
    final ms = (800 * (1 << attempt)).clamp(800, 6000);
    await Future.delayed(Duration(milliseconds: ms));
  }

  List<Map<String, dynamic>> _toContents(List<AgentMsg> history) {
    final out = <Map<String, dynamic>>[];
    for (final m in history) {
      switch (m.role) {
        case AgentRole.user:
          out.add({
            'role': 'user',
            'parts': [
              {'text': m.text}
            ]
          });
          break;
        case AgentRole.assistant:
          final parts = <Map<String, dynamic>>[];
          if (m.text.isNotEmpty) parts.add({'text': m.text});
          for (final c in m.toolCalls) {
            parts.add({
              'functionCall': {'name': c.name, 'args': c.args}
            });
          }
          if (parts.isNotEmpty) out.add({'role': 'model', 'parts': parts});
          break;
        case AgentRole.tool:
          final r = m.toolResult!;
          out.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': r.name,
                  'response': {'result': r.output},
                }
              }
            ]
          });
          break;
      }
    }
    return out;
  }

  AgentMsg _parse(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return AgentMsg(role: AgentRole.assistant, text: '(boş yanıt)');
    }
    final parts =
        (candidates.first['content']?['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    final calls = <AgentToolCall>[];
    var i = 0;
    for (final p in parts) {
      if (p is! Map) continue;
      if (p['thought'] == true) continue;
      if (p['text'] != null) buffer.write(p['text']);
      if (p['functionCall'] != null) {
        final fc = p['functionCall'] as Map;
        calls.add(AgentToolCall(
          id: 'call_${i++}',
          name: (fc['name'] ?? '').toString(),
          args: (fc['args'] is Map)
              ? Map<String, dynamic>.from(fc['args'] as Map)
              : <String, dynamic>{},
        ));
      }
    }
    return AgentMsg(
      role: AgentRole.assistant,
      text: buffer.toString().trim(),
      toolCalls: calls,
    );
  }

  static String _short(String body) {
    try {
      final m = jsonDecode(body);
      final msg = m['error']?['message'];
      if (msg is String) {
        return msg.length > 100 ? msg.substring(0, 100) : msg;
      }
    } catch (_) {}
    return body.length > 100 ? body.substring(0, 100) : body;
  }
}
