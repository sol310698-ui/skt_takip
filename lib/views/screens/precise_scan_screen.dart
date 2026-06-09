import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/image_preprocess_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;

/// Hassas SKT tarama - foto cek, coklu on isleme, akilli parser.
/// Zor okunan etiketler (kirmizi zemin, soluk baski) icin.
/// pop ile DateTime dondurur.
class PreciseScanScreen extends StatefulWidget {
  const PreciseScanScreen({super.key});

  @override
  State<PreciseScanScreen> createState() => _PreciseScanScreenState();
}

class _PreciseScanScreenState extends State<PreciseScanScreen> {
  bool _processing = false;
  String _status = '';
  List<du.DateCandidate> _candidates = [];

  Future<void> _capture(ImageSource source) async {
    setState(() {
      _processing = true;
      _status = 'Fotoğraf alınıyor...';
      _candidates = [];
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    List<String> variants = [];
    String? originalPath;

    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 100,
      );
      if (photo == null) {
        setState(() => _processing = false);
        return;
      }
      originalPath = photo.path;

      // Coklu on isleme versiyonlari uret
      setState(() => _status = 'Görüntü işleniyor...');
      variants =
          await ImagePreprocessService.instance.generateVariants(photo.path);

      // Her versiyonu ML Kit'e ver, metinleri topla
      setState(() => _status = 'Tarih okunuyor...');
      final texts = <String>[];
      for (final path in variants) {
        try {
          final input = InputImage.fromFilePath(path);
          final result = await recognizer.processImage(input);
          if (result.text.isNotEmpty) texts.add(result.text);
        } catch (_) {}
      }

      // Tum metinlerden adaylari topla + oylama (merkezi mantik).
      final list = du.DateUtils.rankedCandidatesFromMultiple(texts);

      setState(() {
        _candidates = list;
        _processing = false;
        _status = list.isEmpty ? 'Tarih bulunamadı' : '';
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _status = 'Hata: $e';
      });
    } finally {
      recognizer.close();
      if (originalPath != null) {
        await ImagePreprocessService.instance.cleanup(variants, originalPath);
      }
    }
  }

  void _confirm(DateTime date) => Navigator.of(context).pop(date);
  void _manual() => Navigator.of(context).pop(DateTime(1900));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hassas SKT Tarama')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Bilgi karti
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.card(accentColor: AppTheme.accent),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      color: AppTheme.accent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Zor okunan etiketler (kırmızı zemin, soluk baskı) için. '
                      'Tarihi net çerçeveleyip fotoğraflayın.',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_processing) ...[
              const Spacer(),
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(_status,
                  style: const TextStyle(color: AppTheme.textSecondary)),
              const Spacer(),
            ] else if (_candidates.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _candidates.length == 1
                      ? 'Bulunan tarih:'
                      : 'Bulunan tarihler (en olası üstte):',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _candidates.length,
                  itemBuilder: (_, i) => _candidateCard(_candidates[i], i == 0),
                ),
              ),
            ] else ...[
              const Spacer(),
              if (_status.isNotEmpty)
                Text(_status,
                    style: const TextStyle(color: AppTheme.textSecondary)),
              const Spacer(),
            ],

            // Alt butonlar
            if (!_processing) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _capture(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(_candidates.isEmpty
                      ? 'Fotoğraf Çek'
                      : 'Tekrar Çek'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _manual,
                child: const Text('Elle Gir'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _candidateCard(du.DateCandidate c, bool isBest) {
    final dateStr = DateFormat('dd.MM.yyyy').format(c.date);
    final conf = c.confidenceLabel;
    final Color confColor = conf == 'yuksek'
        ? AppTheme.statusSafe
        : (conf == 'orta' ? AppTheme.statusWarning : AppTheme.statusExpired);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _confirm(c.date),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.card(
                accentColor: isBest ? AppTheme.statusSafe : null,
                elevated: isBest),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateStr,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: isBest
                                ? AppTheme.statusSafe
                                : AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: confColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('Güven: $conf',
                            style: TextStyle(
                                fontSize: 12, color: confColor)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                if (isBest)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSafe.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('En olası',
                        style: TextStyle(
                            color: AppTheme.statusSafe,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: AppTheme.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
