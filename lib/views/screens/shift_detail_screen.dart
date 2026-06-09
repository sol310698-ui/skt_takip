import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/shift_entry.dart';

/// Mesai detay sayfasi - foto, konum, sure.
class ShiftDetailScreen extends StatelessWidget {
  final ShiftEntry shift;
  const ShiftDetailScreen({super.key, required this.shift});

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openPhoto(BuildContext context, String path) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoView(path: path),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tf = DateFormat('HH:mm');
    final dateStr = DateFormat('dd.MM.yyyy').format(shift.clockIn);

    return Scaffold(
      appBar: AppBar(title: const Text('Mesai Detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ozet karti
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.bannerGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _summaryItem('Giriş', tf.format(shift.clockIn)),
                    _summaryItem(
                        'Çıkış',
                        shift.clockOut != null
                            ? tf.format(shift.clockOut!)
                            : '—'),
                    _summaryItem(
                        'Süre',
                        shift.clockOut != null
                            ? shift.durationLabel
                            : 'Devam'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Giris bilgileri
          _sectionTitle('Giriş'),
          _infoCard(
            context,
            time: tf.format(shift.clockIn),
            lat: shift.inLatitude,
            lng: shift.inLongitude,
            photo: shift.photoInPath,
          ),

          if (shift.clockOut != null) ...[
            const SizedBox(height: 16),
            _sectionTitle('Çıkış'),
            _infoCard(
              context,
              time: tf.format(shift.clockOut!),
              lat: shift.outLatitude,
              lng: shift.outLongitude,
              photo: shift.photoOutPath,
            ),
          ],

          if (shift.note != null && shift.note!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle('Not'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.card(),
              child: Text(shift.note!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppTheme.textSecondary)),
      );

  Widget _infoCard(
    BuildContext context, {
    required String time,
    double? lat,
    double? lng,
    String? photo,
  }) {
    return Container(
      decoration: AppTheme.card(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text('Saat: $time',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          // Konum
          if (lat != null && lng != null)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openMap(lat, lng),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.accent),
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded,
                        size: 16, color: AppTheme.accent),
                  ],
                ),
              ),
            )
          else
            Row(
              children: const [
                Icon(Icons.location_off,
                    color: AppTheme.textTertiary, size: 18),
                SizedBox(width: 8),
                Text('Konum kaydı yok',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 13)),
              ],
            ),
          const SizedBox(height: 12),
          // Foto
          if (photo != null && File(photo).existsSync())
            GestureDetector(
              onTap: () => _openPhoto(context, photo),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(photo),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _noPhoto(),
                ),
              ),
            )
          else
            _noPhoto(),
        ],
      ),
    );
  }

  Widget _noPhoto() => Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  color: AppTheme.textTertiary, size: 18),
              SizedBox(width: 8),
              Text('Fotoğraf yok',
                  style: TextStyle(color: AppTheme.textTertiary)),
            ],
          ),
        ),
      );
}

/// Tam ekran foto goruntuleyici.
class _PhotoView extends StatelessWidget {
  final String path;
  const _PhotoView({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
