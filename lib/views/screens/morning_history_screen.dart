import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/morning_label_service.dart';
import '../../core/theme/app_theme.dart';
import 'image_zoom_screen.dart';

/// Son 30 günün sabah etiket kayıtlarını günlere bölünmüş şekilde listeler.
class MorningHistoryScreen extends StatefulWidget {
  const MorningHistoryScreen({super.key});

  @override
  State<MorningHistoryScreen> createState() => _MorningHistoryScreenState();
}

class _MorningHistoryScreenState extends State<MorningHistoryScreen> {
  // Her gün için kayıt listesi: key = "yyyy-MM-dd"
  Map<String, List<MorningLabel>> _grouped = {};
  List<String> _dayKeys = []; // sıralı gün listesi (en yeni önce)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await MorningLabelService.instance.getLast30Days();

    // Günlere grupla
    final Map<String, List<MorningLabel>> grouped = {};
    for (final label in all) {
      final key = DateFormat('yyyy-MM-dd').format(label.scannedAt);
      grouped.putIfAbsent(key, () => []).add(label);
    }

    // Anahtarları en yeniden eskiye sırala
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    if (mounted) {
      setState(() {
        _grouped = grouped;
        _dayKeys = keys;
        _loading = false;
      });
    }
  }

  String _formatDayHeader(String key) {
    final date = DateTime.parse(key);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Bugün';
    if (d == yesterday) return 'Dün';
    return DateFormat('d MMMM yyyy, EEEE', 'tr').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Etiket Kayıt Geçmişi'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Tüm Geçmişi Sil',
            onPressed: _confirmDeleteAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dayKeys.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }


  // ── Silme onay diyalogları ──────────────────────────────────────────────

  Future<void> _confirmDeleteAll() async {
    final ok = await _showConfirm(
      icon: Icons.delete_sweep_rounded,
      iconColor: AppTheme.statusExpired,
      title: 'Tüm Geçmişi Sil',
      message: 'Son 30 günün tüm etiket kayıtları kalıcı olarak silinecek. Bu işlem geri alınamaz.',
      confirmLabel: 'Tümünü Sil',
      confirmColor: AppTheme.statusExpired,
    );
    if (!ok) return;
    await MorningLabelService.instance.deleteAll();
    if (mounted) _load();
  }

  Future<void> _confirmDeleteDay(String key) async {
    final ok = await _showConfirm(
      icon: Icons.delete_outline_rounded,
      iconColor: AppTheme.statusWarning,
      title: '${_formatDayHeader(key)} Silinsin mi?',
      message: 'Bu güne ait tüm etiket kayıtları kalıcı olarak silinecek.',
      confirmLabel: 'Günü Sil',
      confirmColor: AppTheme.statusWarning,
    );
    if (!ok) return;
    await MorningLabelService.instance.deleteDay(DateTime.parse(key));
    if (mounted) _load();
  }

  Future<bool> _showConfirm({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rLg)),
        icon: Icon(icon, color: iconColor, size: 36),
        title: Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_off_rounded,
              size: 56, color: AppTheme.textTertiary),
          const SizedBox(height: 14),
          const Text('Son 30 günde kayıt yok',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Tüm günleri ve altlarındaki kayıtları düz liste olarak derle
    // (SliverList yerine basit ListView ile — daha az kod, aynı performans)
    final items = <_ListItem>[];
    for (final key in _dayKeys) {
      final labels = _grouped[key]!;
      // O günün ilk a4Photo'sunu al (hepsi aynı fotoğrafı taşır).
      final photo = labels.firstWhere(
        (l) => l.a4Photo != null,
        orElse: () => labels.first,
      ).a4Photo;
      items.add(_ListItem.header(key, labels.length, photo: photo));
      for (final label in labels) {
        items.add(_ListItem.label(label));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) return _buildDayHeader(item.dayKey!, item.count!, photo: item.photo);
        return _buildLabelCard(item.label!);
      },
    );
  }

  Widget _buildDayHeader(String key, int count, {String? photo}) {
    final hasPhoto = photo != null && File(photo).existsSync();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          // Tarih etiketi
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppTheme.primary.withOpacity(0.4), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 13, color: AppTheme.primaryLight),
                const SizedBox(width: 6),
                Text(
                  _formatDayHeader(key),
                  style: const TextStyle(
                    color: AppTheme.primaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Etiket sayısı
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count etiket',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // A4 fotoğraf butonu — sadece dosya mevcutsa göster
          if (hasPhoto)
            GestureDetector(
              onTap: () => openImageZoom(
                context,
                filePath: photo,
                heroTag: 'a4_$key',
                title: 'A4 Liste — ${_formatDayHeader(key)}',
              ),
              child: Hero(
                tag: 'a4_$key',
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.accent.withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withOpacity(0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.file(
                      File(photo!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_rounded,
                        color: AppTheme.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            // Fotoğraf yoksa ufak soluk ikon
            const Tooltip(
              message: 'Fotoğraf kaydedilmemiş',
              child: Icon(Icons.image_outlined,
                  size: 20, color: AppTheme.textTertiary),
            ),
          const SizedBox(width: 6),
          // Günü sil butonu
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.textTertiary, size: 20),
            tooltip: 'Bu günü sil',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _confirmDeleteDay(key),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelCard(MorningLabel m) {
    final fmtTime = DateFormat('HH:mm');
    final fmtDate = DateFormat('dd.MM.yyyy');

    return Dismissible(
      key: ValueKey(m.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          color: AppTheme.statusExpired.withOpacity(0.85),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        if (m.id == null) return false;
        await MorningLabelService.instance.deleteById(m.id!);
        // Listeyi yeniden yükle
        _load();
        return true;
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: AppTheme.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // İkon
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.label_rounded,
                color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 11),

          // Barkod + tarih detayları
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.barcode,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (m.labelExpiry != null || m.labelPrint != null) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 10,
                    children: [
                      if (m.labelExpiry != null)
                        _chip(Icons.event_busy_rounded,
                            'SKT: ${fmtDate.format(m.labelExpiry!)}',
                            AppTheme.statusWarning),
                      if (m.labelPrint != null)
                        _chip(Icons.print_rounded,
                            'Basım: ${fmtDate.format(m.labelPrint!)}',
                            AppTheme.textTertiary),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Sağ taraf: fiyat + saat
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (m.price != null)
                Text(
                  '${m.price!.toStringAsFixed(2)} ₺',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.statusSafe,
                    fontSize: 14,
                  ),
                ),
              Text(
                fmtTime.format(m.scannedAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
      ), // Dismissible child sonu
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Yardımcı veri yapısı ────────────────────────────────────────────────────

class _ListItem {
  final bool isHeader;
  final String? dayKey;
  final int? count;
  final String? photo;
  final MorningLabel? label;

  const _ListItem._({
    required this.isHeader,
    this.dayKey,
    this.count,
    this.photo,
    this.label,
  });

  factory _ListItem.header(String key, int count, {String? photo}) =>
      _ListItem._(isHeader: true, dayKey: key, count: count, photo: photo);

  factory _ListItem.label(MorningLabel label) =>
      _ListItem._(isHeader: false, label: label);
}
