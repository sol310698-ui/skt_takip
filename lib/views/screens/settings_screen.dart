import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/db_source_prefs.dart';
import '../../core/services/export_service.dart';
import '../../core/services/label_inspect_button_prefs.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/theme_prefs.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'history_screen.dart';
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

  // Kullanicinin secebilecegi ANA RENK paleti — canli, modern tonlar.
  static const List<Color> _palette = [
    Color(0xFF2563EB), // mavi (varsayilan)
    Color(0xFF7C3AED), // mor
    Color(0xFFDB2777), // pembe/magenta
    Color(0xFFDC2626), // kirmizi
    Color(0xFFEA580C), // turuncu
    Color(0xFFD97706), // amber
    Color(0xFF16A34A), // yesil
    Color(0xFF059669), // zumrut
    Color(0xFF0891B2), // camgobegi
    Color(0xFF4F46E5), // indigo
    Color(0xFF0D9488), // teal
    Color(0xFF475569), // kurumsal gri
  ];

  List<PendingNotificationRequest> _notifications = [];
  bool _loadingNotifs = true;
  bool _exporting = false;
  bool _deduping = false;

  // Bildirimler sekmesinde hangi urun grubu acik (genisletilmis).
  final Set<int> _expandedGroups = <int>{};

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

  /// Mukerrer (ayni barkod + ayni SKT) urunleri temizler. Once onay sorar.
  Future<void> _removeDuplicates() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tekrar Eden Ürünleri Temizle'),
        content: const Text(
            'Aynı barkoda VE aynı son kullanma tarihine sahip kayıtlardan '
            'her birinden yalnızca bir tane bırakılacak, fazlalıklar '
            'silinecek.\n\nFarklı tarihli aynı barkodlar (gerçek farklı '
            'partiler) korunur. Bu işlem geri alınamaz. Devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Temizle')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deduping = true);
    try {
      final removed =
          await ref.read(productRepositoryProvider).removeDuplicates();
      // Listeyi yenile ki ekranlar guncellensin.
      await ref.read(productListProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(removed > 0
                ? '$removed tekrar eden kayıt silindi'
                : 'Tekrar eden kayıt bulunamadı'),
            backgroundColor:
                removed > 0 ? AppTheme.statusSafe : AppTheme.surfaceHigh,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _deduping = false);
    }
  }

  Future<void> _fullBackup() async {
    // Fotograflar dahil oldugu icin biraz surebilir; kullaniciya durum goster.
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(
          duration: Duration(minutes: 5),
          content: Text('Yedek hazırlanıyor…')));
      await BackupService.instance.exportAll(
        onProgress: (s) {
          messenger.clearSnackBars();
          messenger.showSnackBar(SnackBar(
              duration: const Duration(minutes: 5), content: Text(s)));
        },
      );
      messenger.clearSnackBars();
    } catch (e) {
      messenger.clearSnackBars();
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('Yedek alınamadı: $e')));
      }
    }
  }

  Future<void> _restoreBackup() async {
    // Geri yukleme mevcut TUM veriyi siler — once onay al.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Geri Yükle'),
        content: const Text(
            'Seçeceğiniz yedek dosyası mevcut TÜM verilerin (barkod + SKT) '
            'üzerine yazılır ve şu anki veriler silinir. Devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Geri Yükle',
                  style: TextStyle(color: AppTheme.statusExpired))),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        messenger.showSnackBar(const SnackBar(
            duration: Duration(minutes: 5),
            content: Text('Geri yükleniyor…')));
        await BackupService.instance.restoreAll(
          result.files.single.path!,
          onProgress: (s) {
            messenger.clearSnackBars();
            messenger.showSnackBar(SnackBar(
                duration: const Duration(minutes: 5), content: Text(s)));
          },
        );
        messenger.clearSnackBars();
        if (mounted) {
          messenger.showSnackBar(const SnackBar(
              content:
                  Text('Geri yüklendi. Lütfen uygulamayı yeniden başlatın.')));
        }
      }
    } catch (e) {
      messenger.clearSnackBars();
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('Geri yükleme hatası: $e')));
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
                ? Icon(Icons.check_rounded, color: AppTheme.primary)
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
        AnimatedBuilder(
          animation: LabelInspectButtonPrefs.instance,
          builder: (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: AppTheme.card(),
            child: SwitchListTile(
              value: LabelInspectButtonPrefs.instance.animationEnabled,
              onChanged: (v) =>
                  LabelInspectButtonPrefs.instance.setAnimationEnabled(v),
              activeColor: AppTheme.accent,
              title: const Text('Etiket İncele Animasyonu',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Sol alttaki butonun nabız efektini aç/kapat',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ),
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
        const SectionLabel('İnternet Veri Tabanı'),
        const SizedBox(height: 8),
        const _DbSourceSection(),
        const SizedBox(height: 16),
        const SectionLabel('Güvenlik'),
        const SizedBox(height: 8),
        const _SecuritySection(),
        const SizedBox(height: 16),
        const SectionLabel('Veri'),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.backup_outlined,
          color: AppTheme.primary,
          title: 'Tam Yedek Al',
          subtitle: 'Tüm barkod ve SKT verilerini tek dosyada yedekle',
          onTap: _fullBackup,
        ),
        _tile(
          icon: Icons.table_chart_outlined,
          color: AppTheme.statusSafe,
          title: 'SKT Excel Yedek',
          subtitle: 'Sadece SKT verilerini Excel dosyası olarak dışa aktar',
          loading: _exporting,
          onTap: _exporting ? null : _export,
        ),
        _tile(
          icon: Icons.restore_outlined,
          color: AppTheme.accent,
          title: 'Geri Yükle',
          subtitle: 'Önceki tam yedek dosyasından tüm verileri geri yükle',
          onTap: _restoreBackup,
        ),
        _tile(
          icon: Icons.cleaning_services_outlined,
          color: AppTheme.amber,
          title: 'Tekrar Eden Ürünleri Temizle',
          subtitle: 'Aynı barkod ve aynı SKT\'li mükerrer kayıtlardan birini bırakır',
          loading: _deduping,
          onTap: _deduping ? null : _removeDuplicates,
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
  // Duz liste yerine URUNE GORE gruplanir: once urun adi (kac bildirim),
  // ustune basinca o urunun esik bildirimleri (30/15/7/3/1 gun) acilir.
  // Urune bagli olmayan "Bagimsiz bildirimler" ayri bir grupta toplanir.
  Widget _buildNotifications() {
    final groups = _groupedNotifications();
    final totalCount = _notifications.length;

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
                      : '$totalCount planlı bildirim · ${groups.length} grup',
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
        // Manuel bildirim ekle butonu (barkoddan/urunden bagimsiz).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _addStandaloneNotification,
              icon: const Icon(Icons.add_alert_rounded, size: 20),
              label: const Text('Manuel Bildirim Ekle'),
            ),
          ),
        ),
        Expanded(
          child: _loadingNotifs
              ? const LoadingState()
              : groups.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_off_rounded,
                      title: 'Bildirim yok',
                      subtitle:
                          'Planlanmış bildirim yok. Manuel ekleyebilirsiniz.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                      itemCount: groups.length,
                      itemBuilder: (_, i) => _groupTile(groups[i]),
                    ),
        ),
      ],
    );
  }

  /// Pending bildirimleri urune gore gruplar.
  /// Grup anahtari: standalone ise -1, degilse id ~/ 1000 (urun id).
  List<_NotifGroup> _groupedNotifications() {
    final svc = NotificationService.instance;
    final Map<int, _NotifGroup> map = {};
    for (final n in _notifications) {
      final isStd = svc.isStandalone(n.id);
      final key = isStd ? -1 : (n.id ~/ 1000);
      final group = map.putIfAbsent(
        key,
        () => _NotifGroup(
          key: key,
          title: isStd
              ? 'Bağımsız bildirimler'
              : _productNameFromTitle(n.title) ?? 'Ürün #$key',
          isStandalone: isStd,
          items: [],
        ),
      );
      group.items.add(n);
    }
    final list = map.values.toList();
    // Bagimsiz grubu en uste al, sonra urunler alfabetik.
    list.sort((a, b) {
      if (a.isStandalone != b.isStandalone) return a.isStandalone ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    // Her grubun bildirimlerini gun esigine gore (buyukten kucuge) sirala.
    for (final g in list) {
      g.items.sort((a, b) => (b.id % 1000).compareTo(a.id % 1000));
    }
    return list;
  }

  /// "SKT Yaklaşıyor: Koska helva" -> "Koska helva"
  String? _productNameFromTitle(String? title) {
    if (title == null) return null;
    final idx = title.indexOf(':');
    if (idx >= 0 && idx + 1 < title.length) {
      return title.substring(idx + 1).trim();
    }
    return title.trim();
  }

  Widget _groupTile(_NotifGroup g) {
    final expanded = _expandedGroups.contains(g.key);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppTheme.card(),
      child: Column(
        children: [
          // Ust satir: urun adi + bildirim sayisi, basinca acilir/kapanir.
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              if (expanded) {
                _expandedGroups.remove(g.key);
              } else {
                _expandedGroups.add(g.key);
              }
            }),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    g.isStandalone
                        ? Icons.campaign_rounded
                        : Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      g.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${g.items.length}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded,
                        color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          // Acilinca: o urunun esik bildirimleri.
          if (expanded) ...[
            const Divider(height: 1),
            ...g.items.map(_notifSubTile),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _notifSubTile(PendingNotificationRequest n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              color: AppTheme.primaryLight, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.body != null)
                  Text(n.body!,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
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

  /// Barkoddan/urunden bagimsiz, elle bildirim ekleme akisi:
  /// baslik + tarih + saat sor, sonra planla.
  Future<void> _addStandaloneNotification() async {
    final titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 18, 20, 18 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manuel Bildirim',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Bildirim metni',
                      hintText: 'Örn: Reyon temizliği yap',
                      prefixIcon: Icon(Icons.edit_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_rounded,
                              size: 18),
                          label: Text(
                            '${selectedDate.day.toString().padLeft(2, '0')}.'
                            '${selectedDate.month.toString().padLeft(2, '0')}.'
                            '${selectedDate.year}',
                          ),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 3650)),
                            );
                            if (d != null) setSheet(() => selectedDate = d);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.access_time_rounded,
                              size: 18),
                          label: Text(selectedTime.format(ctx)),
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: selectedTime,
                            );
                            if (t != null) setSheet(() => selectedTime = t);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Bildirimi Kur'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;
    final text = titleCtrl.text.trim();
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bildirim metni boş olamaz.')),
        );
      }
      return;
    }

    final when = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    final id = await NotificationService.instance.scheduleStandalone(
      title: text,
      body: '${selectedDate.day.toString().padLeft(2, '0')}.'
          '${selectedDate.month.toString().padLeft(2, '0')}.'
          '${selectedDate.year} ${selectedTime.format(context)}',
      when: when,
    );

    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bildirim kurulamadı (tarih geçmiş olabilir).')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim kuruldu.')),
      );
      _expandedGroups.add(-1); // bagimsiz grubu acik gelsin
      _loadNotifications();
    }
  }
}

/// Bildirimler sekmesinde bir urun (veya "bagimsiz") grubu.
class _NotifGroup {
  final int key;
  final String title;
  final bool isStandalone;
  final List<PendingNotificationRequest> items;
  _NotifGroup({
    required this.key,
    required this.title,
    required this.isStandalone,
    required this.items,
  });
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

/// Internet barkod sorgularinda hangi acik veri tabanlarinin kullanilacagi
/// (OFF/OBF). Ikisi de acik/biri acik/ikisi kapali olabilir. Tercih
/// DbSourcePrefs'te kalici saklanir ve tum uygulamayi (merkezi sorgu
/// noktasi BarcodeLookupService uzerinden) etkiler.
class _DbSourceSection extends StatefulWidget {
  const _DbSourceSection();

  @override
  State<_DbSourceSection> createState() => _DbSourceSectionState();
}

class _DbSourceSectionState extends State<_DbSourceSection> {
  bool _off = DbSourcePrefs.instance.offEnabled;
  bool _obf = DbSourcePrefs.instance.obfEnabled;

  Future<void> _setOff(bool v) async {
    await DbSourcePrefs.instance.setOff(v);
    setState(() => _off = v);
  }

  Future<void> _setObf(bool v) async {
    await DbSourcePrefs.instance.setObf(v);
    setState(() => _obf = v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.card(),
          child: SwitchListTile(
            value: _off,
            onChanged: _setOff,
            activeColor: AppTheme.primary,
            secondary: const Icon(Icons.restaurant_rounded,
                color: AppTheme.primary),
            title: const Text('Open Food Facts',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Gıda / market ürünleri',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: AppTheme.card(),
          child: SwitchListTile(
            value: _obf,
            onChanged: _setObf,
            activeColor: AppTheme.accent,
            secondary: const Icon(Icons.spa_rounded, color: AppTheme.accent),
            title: const Text('Open Beauty Facts',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Kozmetik / kişisel bakım ürünleri',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ),
        if (!_off && !_obf)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Her ikisi de kapalı: barkodlar internette aranmayacak (sadece yerel kayıtlar).',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
