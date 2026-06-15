import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/services/alarm_service.dart';
import '../../core/services/database_service.dart';
import '../../core/services/schedule_service.dart';
import '../../core/services/skt_alarm_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/datasources/product_local_datasource.dart';
import '../../data/models/product.dart';

/// ════════════════════════════════════════════════════════════════════
///  SKT İMHA ALARMI — aksam tetiklenir.
///  Suresi gecmis ama hala raftaki (active) urunleri gosterir.
///  Tek urun -> buyuk kart; cok urun -> liste.
///  "Kapat" -> alarmi durdur + ertesi gune kur + SKT listesine yonlendir.
/// ════════════════════════════════════════════════════════════════════
class SktDisposalAlarmScreen extends StatefulWidget {
  final int alarmId;

  /// Alarm kapatilinca cagrilir (SKT listesine yonlendirme icin).
  final VoidCallback? onGoToList;

  const SktDisposalAlarmScreen({
    super.key,
    required this.alarmId,
    this.onGoToList,
  });

  @override
  State<SktDisposalAlarmScreen> createState() => _SktDisposalAlarmScreenState();
}

class _SktDisposalAlarmScreenState extends State<SktDisposalAlarmScreen> {
  List<Product> _expired = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExpired();
  }

  Future<void> _loadExpired() async {
    try {
      final ds = ProductLocalDataSource(DatabaseService.instance);
      final active = await ds.getActive();
      // Suresi gecmis (expired) olanlar.
      final expired = active
          .where((p) => p.status == du.ExpiryStatus.expired)
          .toList()
        ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      if (!mounted) return;
      setState(() {
        _expired = expired;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismissAndGoList() async {
    await AlarmService.stop(widget.alarmId);
    // Ertesi gune yeniden kur (gunluk tekrar).
    final h = await SktAlarmSettings.instance.getHour();
    final m = await SktAlarmSettings.instance.getMinute();
    await ScheduleService.instance.rescheduleSktDisposal(hour: h, minute: m);
    if (!mounted) return;
    // Alarm ekranini kapat, sonra SKT listesine yonlendir.
    Navigator.of(context).pop();
    widget.onGoToList?.call();
  }

  Future<void> _justDismiss() async {
    await AlarmService.stop(widget.alarmId);
    final h = await SktAlarmSettings.instance.getHour();
    final m = await SktAlarmSettings.instance.getMinute();
    await ScheduleService.instance.rescheduleSktDisposal(hour: h, minute: m);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    _header(),
                    Expanded(
                      child: _expired.isEmpty
                          ? _emptyState()
                          : (_expired.length == 1
                              ? _singleProduct(_expired.first)
                              : _productList()),
                    ),
                    _bottomButtons(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header() {
    final count = _expired.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE5484D), Color(0xFFB3261E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.alarm_rounded, color: Colors.white, size: 44),
          const SizedBox(height: 12),
          const Text(
            'SKT Kontrolü',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            count == 0
                ? 'Süresi geçen ürün yok'
                : (count == 1
                    ? 'Süresi geçen 1 ürün imha/iadeye alınmalı'
                    : 'Süresi geçen $count ürün imha/iadeye alınmalı'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppTheme.statusSafe, size: 72),
          SizedBox(height: 16),
          Text('Süresi geçen ürün yok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Tüm ürünler güncel. Tebrikler!',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // Tek urun: buyuk kart.
  Widget _singleProduct(Product p) {
    final daysOver = -p.daysUntilExpiry;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.statusExpired.withOpacity(0.4), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.statusExpired.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: AppTheme.statusExpired, size: 36),
              ),
              const SizedBox(height: 18),
              Text(
                p.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              _infoRow(Icons.event_busy_rounded, 'SKT',
                  DateFormat('d MMMM yyyy', 'tr').format(p.expiryDate)),
              const SizedBox(height: 10),
              _infoRow(Icons.timelapse_rounded, 'Gecikme',
                  '$daysOver gün geçmiş',
                  valueColor: AppTheme.statusExpired),
              const SizedBox(height: 10),
              _infoRow(Icons.numbers_rounded, 'Adet', '${p.quantity}'),
              if (p.location != null && p.location!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _infoRow(Icons.place_rounded, 'Konum', p.location!),
              ],
              if (p.barcode != null && p.barcode!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _infoRow(Icons.qr_code_rounded, 'Barkod', p.barcode!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Text('$label:',
            style: const TextStyle(
                fontSize: 15, color: AppTheme.textSecondary)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor),
          ),
        ),
      ],
    );
  }

  // Cok urun: liste.
  Widget _productList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _expired.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = _expired[i];
        final daysOver = -p.daysUntilExpiry;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.statusExpired.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.statusExpired.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: AppTheme.statusExpired, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          DateFormat('d MMM yyyy', 'tr').format(p.expiryDate),
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.statusExpired.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$daysOver gün geçti',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.statusExpired),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (p.quantity > 1)
                Text('×${p.quantity}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomButtons() {
    final hasItems = _expired.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (hasItems)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _dismissAndGoList,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 20),
                label: const Text('Ürünleri Gör ve İşle',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _justDismiss,
              child: Text(
                hasItems ? 'Şimdi değil, kapat' : 'Kapat',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
