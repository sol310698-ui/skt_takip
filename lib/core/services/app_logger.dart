import 'dart:async';
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

  // ── TAMPON (BUFFER) ──
  // Her log satirini AYRI AYRI diske flush etmek (ozellikle debugPrint
  // saganaginda) UI'i kasiyordu. Cozum: satirlari bellekte biriktir,
  // periyodik olarak (veya tampon dolunca) TEK seferde diske yaz.
  final StringBuffer _buffer = StringBuffer();
  int _bufferLines = 0;
  Timer? _flushTimer;
  static const int _flushEveryLines = 20; // 20 satirda bir yaz
  static const Duration _flushInterval = Duration(seconds: 3);

  Future<File> _file() async {
    if (_cachedFile != null) return _cachedFile!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedFile = File('${dir.path}/$_fileName');
    return _cachedFile!;
  }

  /// Bir olayi loga ekle. [tag] kisa kategori (orn 'ALARM'), [message] detay.
  /// Satir once BELLEK tamponuna eklenir; diske yazma periyodik/toplu yapilir
  /// (UI kasmasini onlemek icin). Uygulama kapanirken de flush edilir.
  Future<void> log(String tag, String message) async {
    try {
      final ts = DateTime.now().toIso8601String();
      _buffer.write('[$ts] [$tag] $message\n');
      _bufferLines++;
      // Tampon doldu -> hemen yaz. Dolmadi -> zamanlayici ile yaz.
      if (_bufferLines >= _flushEveryLines) {
        await _flush();
      } else {
        _scheduleFlush();
      }
    } catch (_) {
      // Log yazimi asla uygulamayi bloke etmesin.
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(_flushInterval, () {
      _flush();
    });
  }

  /// Tamponu diske yaz (tek I/O islemi).
  Future<void> _flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final data = _buffer.toString();
    _buffer.clear();
    _bufferLines = 0;
    try {
      final f = await _file();
      await f.writeAsString(data, mode: FileMode.append, flush: false);
      await _trimIfNeeded(f);
    } catch (_) {}
  }

  /// Bekleyen tamponu hemen diske yaz (ornegin log ekrani acilmadan once).
  Future<void> flushNow() => _flush();

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
    await _flush(); // bekleyen tamponu once diske yaz ki son loglar gorunsun
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
