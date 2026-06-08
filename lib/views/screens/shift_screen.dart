import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/shift_entry.dart';
import '../../viewmodels/providers.dart';

/// Mesai takip ekrani - tek dokunus giris/cikis, konum + foto.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  bool _busy = false;

  Future<Position?> _getLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _takePhoto() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      return x?.path;
    } catch (_) {
      return null;
    }
  }

  /// Giris yap - foto sor, konum al, kaydet.
  Future<void> _clockIn() async {
    setState(() => _busy = true);
    try {
      final photo = await _takePhoto();
      final pos = await _getLocation();
      final entry = ShiftEntry(
        clockIn: DateTime.now(),
        inLatitude: pos?.latitude,
        inLongitude: pos?.longitude,
        photoInPath: photo,
      );
      await ref.read(shiftListProvider.notifier).add(entry);
      ref.invalidate(openShiftProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cikis yap - acik vardiyayi guncelle.
  Future<void> _clockOut(ShiftEntry open) async {
    setState(() => _busy = true);
    try {
      final photo = await _takePhoto();
      final pos = await _getLocation();
      final updated = open.copyWith(
        clockOut: DateTime.now(),
        outLatitude: pos?.latitude,
        outLongitude: pos?.longitude,
        photoOutPath: photo,
      );
      await ref.read(shiftListProvider.notifier).updateShift(updated);
      ref.invalidate(openShiftProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openAsync = ref.watch(openShiftProvider);
    final shiftsAsync = ref.watch(shiftListProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(openAsync.valueOrNull),
            Expanded(
              child: shiftsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
                data: (list) {
                  if (list.isEmpty) return _buildEmpty();
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 90),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _shiftCard(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ShiftEntry? open) {
    final isWorking = open != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        gradient: isWorking
            ? const LinearGradient(
                colors: [Color(0xFF00B894), Color(0xFF00D9A3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : AppTheme.bannerGradient,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mesai Takip',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (isWorking) ...[
            Row(
              children: [
                const Icon(Icons.circle, color: Colors.white, size: 12),
                const SizedBox(width: 8),
                Text(
                  'Mesaidesiniz · ${DateFormat('HH:mm').format(open.clockIn)}\'den beri',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Süre: ${open.durationLabel}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 13)),
            const SizedBox(height: 16),
          ],
          // Buyuk giris/cikis butonu
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : (isWorking ? () => _clockOut(open) : _clockIn),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor:
                    isWorking ? const Color(0xFF00B894) : AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(isWorking
                      ? Icons.logout_rounded
                      : Icons.login_rounded),
              label: Text(
                _busy
                    ? 'İşleniyor...'
                    : (isWorking ? 'Çıkış Yap' : 'Giriş Yap'),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.access_time_rounded,
              size: 64, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text('Henüz mesai kaydı yok',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          SizedBox(height: 4),
          Text('Giriş Yap butonuyla başlayın',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _shiftCard(ShiftEntry s) {
    final dateStr = DateFormat('dd.MM.yyyy').format(s.clockIn);
    final inStr = DateFormat('HH:mm').format(s.clockIn);
    final outStr =
        s.clockOut != null ? DateFormat('HH:mm').format(s.clockOut!) : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: AppTheme.card(
            accentColor: s.isOpen ? AppTheme.statusSafe : null),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(dateStr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                if (s.isOpen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSafe.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Devam ediyor',
                        style: TextStyle(
                            color: AppTheme.statusSafe,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  )
                else
                  Text(s.durationLabel,
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _timeBox('Giriş', inStr, Icons.login_rounded,
                    s.inLatitude != null, s.photoInPath != null),
                const SizedBox(width: 12),
                _timeBox('Çıkış', outStr, Icons.logout_rounded,
                    s.outLatitude != null, s.photoOutPath != null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeBox(
      String label, String time, IconData icon, bool hasLoc, bool hasPhoto) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(time,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on,
                    size: 13,
                    color: hasLoc
                        ? AppTheme.accent
                        : AppTheme.textTertiary),
                const SizedBox(width: 4),
                Icon(Icons.photo_camera,
                    size: 13,
                    color: hasPhoto
                        ? AppTheme.accent
                        : AppTheme.textTertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
