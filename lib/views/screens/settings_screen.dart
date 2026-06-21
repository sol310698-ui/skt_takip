import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/export_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/theme_prefs.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'log_viewer_screen.dart';
import 'work_location_picker_screen.dart';
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
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
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

  String _themeModeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Aydınlık',
        ThemeMode.dark => 'Koyu',
        ThemeMode.system => 'Sistem (otomatik)',
      };

  void _openThemeMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget option(ThemeMode mode, IconData icon, String label) {
          final selected = ThemePrefs.instance.mode == mode;
          return ListTile(
            leading: Icon(icon,
                color: selected ? AppTheme.primary : AppTheme.textSecondary),
            title: Text(label,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500)),
            trailing: selected
                ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                : null,
            onTap: () async {
              await ThemePrefs.instance.setMode(mode);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tema',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              option(ThemeMode.system, Icons.brightness_auto_rounded,
                  'Sistem (otomatik)'),
              option(ThemeMode.light, Icons.light_mode_rounded, 'Aydınlık'),
              option(ThemeMode.dark, Icons.dark_mode_rounded, 'Koyu'),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // ── Araçlar sekmesi ────────────────────────────────────────────────
  Widget _buildTools() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('Görünüm'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.brightness_6_rounded,
          color: AppTheme.primary,
          title: 'Tema',
          subtitle: _themeModeLabel(ThemePrefs.instance.mode),
          onTap: _openThemeMenu,
        ),
        const SizedBox(height: 16),
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
        const SectionLabel('Güvenlik'),
        const SizedBox(height: 8),
        const _SecuritySection(),
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
        const SectionLabel('Tanılama'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.bug_report_outlined,
          color: AppTheme.accent,
          title: 'Alarm Kayıtları (Log)',
          subtitle: 'Alarm sorununu tespit için kayıtları görüntüle/paylaş',
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogViewerScreen())),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Hakkında'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.card(),
          child: Column(
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
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary))
            : null,
        trailing: Icon(Icons.chevron_right_rounded,
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
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                Text('ID: ${n.id}',
                    style: TextStyle(
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

/// Ayarlar — Güvenlik bölümü: kilit aç/kapa, PIN değiştir, biyometri,
/// iş yeri konumu (haritadan otomatik tespit için).
class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool _loading = true;
  bool _lockEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _hasWorkLocation = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lockEnabled = await AppLockService.instance.isLockEnabled();
    final bioAvailable = await AppLockService.instance.isBiometricAvailable();
    final bioEnabled = await AppLockService.instance.isBiometricEnabled();
    final hasWork = await AppLockService.instance.hasWorkLocation();
    if (!mounted) return;
    setState(() {
      _lockEnabled = lockEnabled;
      _biometricAvailable = bioAvailable;
      _biometricEnabled = bioEnabled;
      _hasWorkLocation = hasWork;
      _loading = false;
    });
  }

  Future<void> _toggleLock(bool value) async {
    if (!value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kilidi kapat'),
          content: const Text(
              'Uygulama açılışında artık PIN/parmak izi sorulmayacak. Emin misiniz?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await AppLockService.instance.setLockEnabled(value);
    setState(() => _lockEnabled = value);
  }

  Future<void> _changePin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _ChangePinScreen()),
    );
    if (result == true) _load();
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Acmadan once bir kez dogrulama iste (gercekten calistigindan emin ol).
      final ok = await AppLockService.instance.authenticateWithBiometrics();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Doğrulama başarısız, biyometri açılamadı.')),
          );
        }
        return;
      }
    }
    await AppLockService.instance.setBiometricEnabled(value);
    setState(() => _biometricEnabled = value);
  }

  Future<void> _openWorkLocationPicker() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => const WorkLocationPickerScreen()),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.card(),
          child: SwitchListTile(
            value: _lockEnabled,
            onChanged: _toggleLock,
            activeColor: AppTheme.accent,
            title: const Text('Uygulama Kilidi',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Açılışta PIN/parmak izi sor',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ),
        if (_lockEnabled) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: _changePin,
              tileColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rLg)),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.password_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              title: const Text('PIN Değiştir',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary),
            ),
          ),
          if (_biometricAvailable)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: AppTheme.card(),
              child: SwitchListTile(
                value: _biometricEnabled,
                onChanged: _toggleBiometric,
                activeColor: AppTheme.accent,
                title: const Text('Parmak İzi / Yüz ile Aç',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('PIN yerine hızlı biyometrik giriş',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: _openWorkLocationPicker,
              tileColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.rLg)),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.statusSafe.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: AppTheme.statusSafe, size: 22),
              ),
              title: const Text('İş Yeri Konumu',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                _hasWorkLocation
                    ? 'Tanımlı — konumdaysanız bilgi notu gösterilir'
                    : 'Tanımlı değil — haritadan işaretleyin',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

/// PIN değiştirme ekranı: önce mevcut PIN doğrulanır, sonra yeni PIN
/// iki kez girilir.
class _ChangePinScreen extends StatefulWidget {
  const _ChangePinScreen();

  @override
  State<_ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<_ChangePinScreen> {
  static const int _pinLength = 6;
  final List<String> _entered = [];
  String? _newFirstPin;
  String? _errorText;
  bool _verifiedOld = false;

  void _onDigit(String d) {
    if (_entered.length >= _pinLength) return;
    setState(() {
      _entered.add(d);
      _errorText = null;
    });
    if (_entered.length == _pinLength) _onComplete();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered.removeLast());
  }

  Future<void> _onComplete() async {
    final pin = _entered.join();

    if (!_verifiedOld) {
      final ok = await AppLockService.instance.verifyPin(pin);
      if (ok) {
        setState(() {
          _verifiedOld = true;
          _entered.clear();
        });
      } else {
        setState(() {
          _errorText = 'Mevcut PIN yanlış';
          _entered.clear();
        });
      }
      return;
    }

    if (_newFirstPin == null) {
      setState(() {
        _newFirstPin = pin;
        _entered.clear();
      });
      return;
    }

    if (pin == _newFirstPin) {
      await AppLockService.instance.setPin(pin);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorText = 'Yeni PIN’ler eşleşmedi';
        _newFirstPin = null;
        _entered.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = !_verifiedOld
        ? 'Mevcut PIN'
        : (_newFirstPin == null ? 'Yeni PIN belirleyin' : 'Yeni PIN’i onaylayın');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('PIN Değiştir'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength, (i) {
                final filled = i < _entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppTheme.primary : AppTheme.surfaceHigh,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 18,
              child: _errorText != null
                  ? Text(_errorText!,
                      style: const TextStyle(
                          color: AppTheme.statusExpired, fontSize: 12))
                  : null,
            ),
            const Spacer(),
            _buildKeypad(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _key(d)],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 64, height: 64),
              _key('0'),
              SizedBox(
                width: 64,
                height: 64,
                child: IconButton(
                  onPressed: _onBackspace,
                  icon: Icon(Icons.backspace_outlined,
                      color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _key(String digit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: () => _onDigit(digit),
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surface,
          ),
          child: Text(digit,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
        ),
      ),
    );
  }
}
