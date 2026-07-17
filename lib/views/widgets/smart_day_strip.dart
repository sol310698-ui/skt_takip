import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/services/database_service.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/product_local_datasource.dart';
import '../../data/datasources/shift_local_datasource.dart';
import '../screens/label_print_screen.dart';
import '../screens/shift_screen.dart';
import '../screens/warehouse_chat_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  AKILLI GÜN — "bugün ne yapmam lazım?"
/// ────────────────────────────────────────────────────────────────────
///  Ana ekranın üstünde, günün durumunu tek bakışta veren yatay kart
///  şeridi. Uygulama sana ne yapman gerektigini SOYLER; sen aramazsin:
///    - SKT: bugun/3 gun icinde dolacak urun sayisi  → dokun: ana liste
///      zaten altta (bilgi karti)
///    - Etiket: basim kuyrugunda bekleyen sayisi     → dokun: Etiket Basim
///    - Vardiya: acik vardiya suresi / "girilmedi"   → dokun: Vardiya
///    - Asistan: hizli soru kisayolu                  → dokun: Depo Asistani
///  Hicbir acil is yoksa serit kucuk bir "her sey yolunda" satirina iner.
/// ════════════════════════════════════════════════════════════════════
class SmartDayStrip extends StatefulWidget {
  const SmartDayStrip({super.key});

  @override
  State<SmartDayStrip> createState() => _SmartDayStripState();
}

class _DayInfo {
  final int sktToday; // bugun (veya gecmis) dolan aktif urun
  final int sktSoon; // 3 gun icinde dolacak
  final int labelPending; // etiket kuyrugu
  final Duration? shiftOpen; // acik vardiya suresi (null = yok)
  final int reyonProducts; // reyonlarda kayitli urun
  const _DayInfo({
    required this.sktToday,
    required this.sktSoon,
    required this.labelPending,
    required this.shiftOpen,
    required this.reyonProducts,
  });

  bool get allClear => sktToday == 0 && sktSoon == 0 && labelPending == 0;
}

class _SmartDayStripState extends State<SmartDayStrip>
    with WidgetsBindingObserver {
  _DayInfo? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulamaya geri donuste guncel kalsin.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseService.instance;
      final products = await ProductLocalDataSource(db).getActive();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      int sktToday = 0, sktSoon = 0;
      for (final p in products) {
        final d = DateTime(
            p.expiryDate.year, p.expiryDate.month, p.expiryDate.day);
        final diff = d.difference(today).inDays;
        if (diff <= 0) {
          sktToday++;
        } else if (diff <= 3) {
          sktSoon++;
        }
      }

      final labelPending =
          await LabelPendingQueueService.instance.pendingCount();

      Duration? shiftOpen;
      try {
        final open = await ShiftLocalDataSource(db).getOpenShift();
        if (open != null) shiftOpen = now.difference(open.clockIn);
      } catch (_) {}

      int reyonProducts = 0;
      try {
        final sums = await ShelfLayoutService.instance.getUnitSummaries();
        for (final s in sums) {
          reyonProducts += s.itemCount;
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _info = _DayInfo(
              sktToday: sktToday,
              sktSoon: sktSoon,
              labelPending: labelPending,
              shiftOpen: shiftOpen,
              reyonProducts: reyonProducts,
            ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox(height: 4);

    // Her sey yolundaysa tek satirlik sakin bir ozet.
    if (info.allClear) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.statusSafe, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bugün acil iş yok — SKT ve etiketler temiz'
                '${info.shiftOpen != null ? '  •  Vardiya: ${_fmtDur(info.shiftOpen!)}' : ''}',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 350.ms);
    }

    // Aksiyon kartlari (yalnizca gerekli olanlar gorunur).
    final cards = <Widget>[];

    if (info.sktToday > 0) {
      cards.add(_card(
        icon: Icons.warning_amber_rounded,
        color: AppTheme.statusExpired,
        title: '${info.sktToday} ürün',
        subtitle: 'SKT doldu/bugün',
        onTap: null, // ana listedeki filtreler hemen altta
      ));
    }
    if (info.sktSoon > 0) {
      cards.add(_card(
        icon: Icons.hourglass_bottom_rounded,
        color: AppTheme.statusWarning,
        title: '${info.sktSoon} ürün',
        subtitle: '3 gün içinde',
        onTap: null,
      ));
    }
    if (info.labelPending > 0) {
      cards.add(_card(
        icon: Icons.local_printshop_rounded,
        color: AppTheme.primary,
        title: '${info.labelPending} etiket',
        subtitle: 'Basım bekliyor',
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LabelPrintScreen()))
            .then((_) => _load()),
      ));
    }
    cards.add(_card(
      icon: info.shiftOpen != null
          ? Icons.timer_rounded
          : Icons.badge_rounded,
      color: AppTheme.accent,
      title: info.shiftOpen != null ? _fmtDur(info.shiftOpen!) : 'Vardiya',
      subtitle: info.shiftOpen != null ? 'Vardiya açık' : 'Giriş yapılmadı',
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ShiftScreen()))
          .then((_) => _load()),
    ));
    cards.add(_card(
      icon: Icons.assistant_rounded,
      color: AppTheme.primaryLight,
      title: 'Asistan',
      subtitle: 'Ürün nerede? Sor',
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WarehouseChatScreen())),
    ));

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => cards[i]
            .animate()
            .fadeIn(delay: (i * 60).ms, duration: 300.ms)
            .slideX(begin: 0.15, delay: (i * 60).ms, duration: 300.ms),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 128,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}s ${m}dk' : '${m}dk';
  }
}
