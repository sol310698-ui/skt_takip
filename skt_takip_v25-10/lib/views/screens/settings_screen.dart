import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/backup_service.dart';
import '../../core/services/export_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'work_schedule_screen.dart';

/// Ayarlar ekranı: banner ikonlarını + bildirim yönetimini toplar.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<PendingNotificationRequest> _notifications = [];
  bool _loadingNotifs = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadNotifications();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _loadingNotifs = true);
    final list = await NotificationService.instance.getPending();
    if (!mounted) return;
    setState(() {
      _notifications = list;
      _loadingNotifs = false;
    });
  }

  Future<void> _cancelNotification(int id) async {
    await NotificationService.instance.cancelOne(id);
    _loadNotifications();
  }

  Future<void> _cancelAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm Bildirimleri Sil'),
        content: const Text(
            'Tüm planlanmış SKT bildirimleri iptal edilecek. '
            'Ürünleri yeniden açarak yeniden oluşturabilirsiniz.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Hepsini İptal Et'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NotificationService.instance.cancelAll();
      _loadNotifications();
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      // Urunleri provider'dan cek.
      final products = ref.read(productListProvider).valueOrNull ?? [];
      final active = products.where((p) => p.isActive).toList();
      final history = products.where((p) => !p.isActive).toList();
      await ExportService.instance
          .exportToExcel(activeProducts: active, historyProducts: history);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Excel dosyası paylaşıldı'),
              backgroundColor: AppTheme.statusSafe),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openBackupMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yedek İşlemleri'),
        content: const Text('Ne yapmak istersiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'backup'),
              child: const Text('Yedek Al')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'restore'),
              child: const Text('Geri Yükle')),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'backup') {
      await BackupService.instance.exportDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yedek alındı')));
      }
    } else {
      // Geri yükleme için dosya yolu gerekiyor — file picker ile al.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowedExtensions: null,
      );
      if (result != null && result.files.single.path != null) {
        await BackupService.instance.importDb(result.files.single.path!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Geri yüklendi, uygulama yeniden başlatın')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Ayarlar'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Araçlar', icon: Icon(Icons.build_rounded, size: 18)),
            Tab(
                text: 'Bildirimler',
                icon: Icon(Icons.notifications_rounded, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_buildTools(), _buildNotifications()],
      ),
    );
  }

  // ── Araçlar sekmesi ────────────────────────────────────────────────
  Widget _buildTools() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('Çalışma'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.calendar_month_rounded,
          color: AppTheme.primary,
          title: 'Çalışma Programı',
          subtitle: 'Haftalık program oluştur, günlük alarm kur',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkScheduleScreen())),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Veri'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.table_chart_outlined,
          color: AppTheme.statusSafe,
          title: 'Excel Export',
          subtitle: 'Tüm ürünleri Excel olarak dışa aktar',
          loading: _exporting,
          onTap: _exporting ? null : _export,
        ),
        _tile(
          icon: Icons.upload_file_outlined,
          color: AppTheme.accent,
          title: 'Barkod Import',
          subtitle: 'Excel\'den barkod dizinine aktar',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
        _tile(
          icon: Icons.cloud_download_outlined,
          color: AppTheme.primary,
          title: 'Yedek Al / Geri Yükle',
          subtitle: 'Veritabanını yedekle veya önceki yedeği yükle',
          onTap: _openBackupMenu,
        ),
        const SizedBox(height: 16),
        const SectionLabel('Geçmiş'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.history,
          color: AppTheme.amber,
          title: 'İmha & İade Geçmişi',
          subtitle: 'Geçmişteki imha ve iade kayıtları',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen())),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Hakkında'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.card(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SKT Takip',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(height: 4),
              Text(
                'Son kullanma tarihi takip, barkod dizini, '
                'depo yönetimi, fiyat değişim ve mesai modülleri.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        tileColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rLg)),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textTertiary),
      ),
    );
  }

  // ── Bildirimler sekmesi ────────────────────────────────────────────
  Widget _buildNotifications() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _loadingNotifs
                      ? 'Yükleniyor...'
                      : '${_notifications.length} planlı bildirim',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadNotifications,
                tooltip: 'Yenile',
              ),
              if (_notifications.isNotEmpty)
                TextButton.icon(
                  onPressed: _cancelAll,
                  icon: const Icon(Icons.delete_sweep_rounded,
                      size: 18, color: AppTheme.statusExpired),
                  label: const Text('Hepsini Sil',
                      style: TextStyle(color: AppTheme.statusExpired)),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingNotifs
              ? const LoadingState()
              : _notifications.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_off_rounded,
                      title: 'Bildirim yok',
                      subtitle:
                          'Planlanmış SKT bildirimi bulunmuyor.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) =>
                          _notifTile(_notifications[i]),
                    ),
        ),
      ],
    );
  }

  Widget _notifTile(PendingNotificationRequest n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title ?? '(başlık yok)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (n.body != null)
                  Text(n.body!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                Text('ID: ${n.id}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 20, color: AppTheme.statusExpired),
            tooltip: 'İptal Et',
            onPressed: () => _cancelNotification(n.id),
          ),
        ],
      ),
    );
  }
}
