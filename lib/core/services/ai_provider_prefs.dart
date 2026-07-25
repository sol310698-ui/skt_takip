import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ════════════════════════════════════════════════════════════════════
///  YAPAY ZEKA SAĞLAYICI TERCİHİ
/// ────────────────────────────────────────────────────────────────────
///  Asistan iki sağlayıcıdan biriyle çalışabilir:
///    • gemini : Google Gemini (varsayılan; A4/OCR okuma hep Gemini'dir)
///    • claude : Anthropic Claude (sohbet/agent için; araç kullanımında
///               daha güvenilir)
///
///  Bu tercih SADECE Depo Asistanı sohbetini (metin/agent) etkiler.
///  OCR (A4 tablo, SKT, etiket okuma) her zaman Gemini ile yapılır çünkü
///  o akışlar Gemini'nin görsel modeline bağlıdır.
/// ════════════════════════════════════════════════════════════════════
enum AiProvider { gemini, claude }

class AiProviderPrefs extends ChangeNotifier {
  AiProviderPrefs._();
  static final AiProviderPrefs instance = AiProviderPrefs._();

  static const _providerKey = 'ai_provider';
  static const _claudeModelKey = 'claude_model';
  final _storage = const FlutterSecureStorage();

  AiProvider _provider = AiProvider.gemini;
  AiProvider get provider => _provider;
  bool get isClaude => _provider == AiProvider.claude;

  /// Seçili Claude modeli (varsayılan: dengeli Sonnet).
  String _claudeModel = 'claude-sonnet-5';
  String get claudeModel => _claudeModel;

  /// Uygulama açılışında bir kez çağrılır.
  Future<void> load() async {
    try {
      final p = await _storage.read(key: _providerKey);
      _provider = p == 'claude' ? AiProvider.claude : AiProvider.gemini;
    } catch (_) {
      _provider = AiProvider.gemini;
    }
    try {
      final m = await _storage.read(key: _claudeModelKey);
      if (m != null && m.trim().isNotEmpty) _claudeModel = m.trim();
    } catch (_) {}
  }

  Future<void> setProvider(AiProvider p) async {
    _provider = p;
    notifyListeners();
    try {
      await _storage.write(
          key: _providerKey, value: p == AiProvider.claude ? 'claude' : 'gemini');
    } catch (_) {}
  }

  Future<void> setClaudeModel(String model) async {
    final m = model.trim();
    if (m.isEmpty) return;
    _claudeModel = m;
    notifyListeners();
    try {
      await _storage.write(key: _claudeModelKey, value: m);
    } catch (_) {}
  }
}

/// Kullanıcının seçebileceği Claude modelleri (etiket + kimlik + kısa not).
class ClaudeModelOption {
  final String id;
  final String label;
  final String note;
  const ClaudeModelOption(this.id, this.label, this.note);
}

const List<ClaudeModelOption> kClaudeModels = [
  ClaudeModelOption(
      'claude-haiku-4-5', 'Haiku 4.5', 'En ucuz ve hızlı — araç kullanımı iyi'),
  ClaudeModelOption(
      'claude-sonnet-5', 'Sonnet 5', 'Denge — depo asistanı için ideal'),
  ClaudeModelOption(
      'claude-opus-5', 'Opus 5', 'En akıllı — en pahalı'),
];
