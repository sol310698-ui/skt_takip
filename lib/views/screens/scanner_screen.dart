import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;

/// Fotograf cekerek OCR ile SKT okuyan ekran (guvenilir yontem).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  bool _processing = false;
  String? _rawText;
  DateTime? _detectedDate;

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    setState(() {
      _processing = true;
      _rawText = null;
      _detectedDate = null;
    });

    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (photo == null) {
        setState(() => _processing = false);
        return;
      }

      final inputImage = InputImage.fromFilePath(photo.path);
      final RecognizedText result =
          await _recognizer.processImage(inputImage);

      DateTime? found;
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final d = du.DateUtils.parseFromOcr(line.text);
          if (d != null) {
            found = d;
            break;
          }
        }
        if (found != null) break;
      }
      found ??= du.DateUtils.parseFromOcr(result.text);

      setState(() {
        _processing = false;
        _rawText = result.text;
        _detectedDate = found;
      });
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  void _confirm() {
    final date = _detectedDate;
    if (date == null) return;
    Navigator.of(context).pop(date);
  }

  void _manualEntry() {
    Navigator.of(context).pop(DateTime(1900));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SKT Tara')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.document_scanner_outlined,
                size: 72, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Ürünün son kullanma tarihini\nfotoğraflayın',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            if (_processing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Tarih okunuyor...',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              )
            else if (_detectedDate != null)
              _buildResult()
            else if (_rawText != null)
              _buildNotFound(),
            const Spacer(),
            FilledButton.icon(
              onPressed: _processing ? null : () => _capture(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Fotoğraf Çek'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _processing ? null : () => _capture(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galeriden Seç'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _processing ? null : _manualEntry,
              child: const Text('Elle gir'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final dateStr = DateFormat('dd.MM.yyyy').format(_detectedDate!);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCard(accent: Colors.greenAccent),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 44),
          const SizedBox(height: 10),
          const Text('Tarih bulundu',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(dateStr,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _confirm,
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassCard(accent: Colors.orangeAccent),
      child: Column(
        children: [
          const Icon(Icons.error_outline,
              color: Colors.orangeAccent, size: 40),
          const SizedBox(height: 10),
          const Text(
            'Tarih okunamadı. Tekrar deneyin ya da elle girin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _manualEntry,
            child: const Text('Elle Gir'),
          ),
        ],
      ),
    );
  }
}
