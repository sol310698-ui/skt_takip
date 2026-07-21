import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'gemini_ocr_service.dart';

/// Kullanicinin KENDI Gemini API anahtarinda desteklenen modelleri tarar,
/// listeler ve tercih edilen modeli kalici saklar.
///
/// Secim yapilmadiginda (ya da secili model bir gun kullanilamaz olursa)
/// GeminiOcrService kendi otomatik yedek listesini kullanmaya devam eder.
/// Secim yapildiginda o model TUM Gemini cagrilarinda ILK sirada denenir;
/// yine de hata olursa otomatik yedeklere dusulur (dayaniklilik korunur).
class AiModelPrefs extends ChangeNotifier {
  AiModelPrefs._();
  static final AiModelPrefs instance = AiModelPrefs._();

  static const _key = 'ai_selected_model';
  final _storage = const FlutterSecureStorage();

  /// Secili model (ornek: 'gemini-2.5-flash'); null = otomatik.
  String? _selected;
  String? get selected => _selected;

  /// Son taramada bulunan, generateContent destekleyen modeller.
  List<AiModelInfo> _available = const [];
  List<AiModelInfo> get available => _available;

  bool _loading = false;
  bool get loading => _loading;
  String? _error;
  String? get error => _error;

  Future<void> load() async {
    try {
      _selected = await _storage.read(key: _key);
      if (_selected != null && _selected!.trim().isEmpty) _selected = null;
    } catch (_) {
      _selected = null;
    }
  }

  Future<void> setSelected(String? model) async {
    _selected = (model == null || model.trim().isEmpty) ? null : model.trim();
    notifyListeners();
    try {
      if (_selected == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: _selected);
      }
    } catch (_) {}
  }

  /// Kullanicinin anahtariyla /models cagrisini yapar; generateContent
  /// destekleyen (yani gorsel/metin uretebilen) TUM modelleri toplar.
  /// Sayfalama (nextPageToken) takip edilir; hepsi taranir.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final key = await GeminiOcrService.instance.getApiKey();
      if (key == null || key.isEmpty) {
        _error = 'Önce Gemini API anahtarınızı girin.';
        _available = const [];
        return;
      }

      final models = <AiModelInfo>[];
      String? pageToken;
      int guard = 0;
      do {
        final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models'
            '?key=$key&pageSize=200'
            '${pageToken != null ? '&pageToken=$pageToken' : ''}');
        final res = await http
            .get(uri, headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          _error = 'Model listesi alınamadı (${res.statusCode}).';
          break;
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['models'] as List?) ?? const [];
        for (final m in list) {
          final map = m as Map<String, dynamic>;
          final methods =
              (map['supportedGenerationMethods'] as List?)?.cast<String>() ??
                  const [];
          // Sadece icerik uretebilen (sohbet/OCR) modelleri al.
          if (!methods.contains('generateContent')) continue;
          final rawName = (map['name'] ?? '').toString(); // "models/gemini-..."
          final id = rawName.startsWith('models/')
              ? rawName.substring(7)
              : rawName;
          if (id.isEmpty) continue;
          models.add(AiModelInfo(
            id: id,
            displayName: (map['displayName'] ?? id).toString(),
            description: (map['description'] ?? '').toString(),
            inputTokenLimit: (map['inputTokenLimit'] as num?)?.toInt(),
          ));
        }
        pageToken = data['nextPageToken'] as String?;
      } while (pageToken != null && ++guard < 10);

      // Isimlendirmeye gore mantikli sirala: once flash/pro guncel surumler.
      models.sort((a, b) => _rank(a.id).compareTo(_rank(b.id)));
      _available = models;
      if (models.isEmpty && _error == null) {
        _error = 'Bu anahtarda içerik üreten model bulunamadı.';
      }
    } catch (e) {
      _error = 'Tarama hatası: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Siralama onceligi: guncel + hafif modeller uste gelsin.
  int _rank(String id) {
    final s = id.toLowerCase();
    var r = 500;
    if (s.contains('2.5')) r -= 200;
    else if (s.contains('2.0')) r -= 150;
    else if (s.contains('1.5')) r -= 100;
    if (s.contains('flash')) r -= 40;
    if (s.contains('pro')) r -= 20;
    if (s.contains('lite')) r -= 10;
    if (s.contains('exp') || s.contains('preview')) r += 30; // deneysel alta
    return r;
  }
}

class AiModelInfo {
  final String id;
  final String displayName;
  final String description;
  final int? inputTokenLimit;
  const AiModelInfo({
    required this.id,
    required this.displayName,
    this.description = '',
    this.inputTokenLimit,
  });
}
