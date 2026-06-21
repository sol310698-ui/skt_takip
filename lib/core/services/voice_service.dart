import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Asistan icin ses servisi: konusmayi metne cevirme (STT) ve metni
/// sesli okuma (TTS). Turkce odakli.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _ttsReady = false;
  bool get isListening => _stt.isListening;

  Future<bool> initStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  Future<void> _initTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('tr-TR');
      await _tts.setSpeechRate(0.5); // dogal hiz
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
  }

  /// Dinlemeye basla. Her kismi sonuc [onResult]'a gelir (final flag ile).
  Future<bool> listen({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    final ok = await initStt();
    if (!ok) return false;
    await _stt.listen(
      localeId: 'tr_TR',
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopListening() async {
    if (_stt.isListening) await _stt.stop();
  }

  /// Metni sesli oku.
  Future<void> speak(String text) async {
    await _initTts();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }
}
