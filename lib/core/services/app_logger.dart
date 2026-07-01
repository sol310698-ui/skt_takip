import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Basit, kalici dosya tabanli log servisi.
///
/// Amac: Alarm gibi olaylari (uygulama kapaliyken/arka plandayken bile)
/// cihazda bir dosyaya yazmak, sonra ayarlardan goruntuleyip paylasabilmek.
/// adb gerekmez. Her log satiri zaman damgalidir.
///
/// Dosya: <app_documents>/skt_logs.txt  (kalici, uygulama silinene kadar durur)
/// Maksimum boyut asilirsa eski yarisi atilir (sinirsiz buyumesin).
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const String _fileName = 'skt_logs.txt';
  static const int _maxBytes = 1024 * 1024; // 1 MB (tum uygulama loglari)

  File? _cachedFile;
  bool _initializing = false;

  Future<File> _file() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/$_fileName');
    return _cachedFile!;
  }

  /// Bir olayi loga ekle. [tag] kisa kategori (orn 'ALARM'), [message] detay.
  Future<void> log(String tag, String message) async {
    try {
      final f = await _file();
      final ts = DateTime.now().toIso8601String();
      final line = '[$ts] [$tag] $message\n';
      // Append modunda yaz (uygulama kapaliyken acilan isolate'lerde de calisir).
      await f.writeAsString(line, mode: FileMode.append, flush: true);
      await _trimIfNeeded(f);
    } catch (_) {
      // Log yazimi asla uygulamayi bloke etmesin / cokmesine yol acmasin.
    }
  }

  /// Dosya cok buyukse eski yarisini at.
  Future<void> _trimIfNeeded(File f) async {
    if (_initializing) return;
    try {
      if (!await f.exists()) return;
      final len = await f.length();
      if (len <= _maxBytes) return;
      _initializing = true;
      final content = await f.readAsString();
      // Son yarisini tut.
      final keep = content.substring(content.length ~/ 2);
      // Ilk satir parcasini at (yarim satirla baslamasin).
      final firstNl = keep.indexOf('\n');
      final trimmed = firstNl >= 0 ? keep.substring(firstNl + 1) : keep;
      await f.writeAsString(
        '[--- eski kayitlar kirpildi ---]\n$trimmed',
        flush: true,
      );
    } catch (_) {
    } finally {
      _initializing = false;
    }
  }

  /// Tum log icerigini oku (goruntuleme/paylasim icin).
  Future<String> readAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return '(Henüz log kaydı yok)';
      final s = await f.readAsString();
      return s.isEmpty ? '(Log dosyası boş)' : s;
    } catch (e) {
      return 'Log okunamadı: $e';
    }
  }

  /// Log dosyasinin yolu (paylasim icin).
  Future<String> filePath() async => (await _file()).path;

  /// Tum loglari temizle.
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.writeAsString('', flush: true);
    } catch (_) {}
  }
}
