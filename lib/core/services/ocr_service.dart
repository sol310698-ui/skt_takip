import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/date_utils.dart';

/// ML Kit ile metin tanıma (OCR) servisi.
/// Canlı kamera akışından gelen görüntüleri işler.
class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Bir [InputImage]'dan tarih ayıklamayı dener.
  /// Bulamazsa null döner.
  Future<DateTime?> extractDate(InputImage image) async {
    final RecognizedText result = await _recognizer.processImage(image);
    if (result.text.trim().isEmpty) return null;

    // Önce satır satır dene (daha temiz eşleşme).
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final date = DateUtils.parseFromOcr(line.text);
        if (date != null) return date;
      }
    }

    // Olmazsa tüm metni dene.
    return DateUtils.parseFromOcr(result.text);
  }

  void dispose() {
    _recognizer.close();
  }
}
