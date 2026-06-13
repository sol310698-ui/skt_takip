import 'package:flutter/material.dart';

import '../../core/services/schedule_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Haftalik calisma programi: her gun icin saat ekle, alarm kur, yonet.
class WorkScheduleScreen extends StatefulWidget {
  const WorkScheduleScreen({super.key});

  @override
  State<WorkScheduleScreen> createState() => _WorkScheduleScreenState();
}

class _WorkScheduleScreenState extends State<WorkScheduleScreen> {
  Map<int, List<ScheduleEntry>> _grouped = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await ScheduleService.instance.getGrouped();
    if (!mounted) return;
    setState(() {
      _grouped = g;
      _loading = false;
    });
  }

  int get _totalEntries =>
      _grouped.values.fold(0, (s, l) => s + l.length);
  int get _enabledEntries => _grouped.values
      .fold(0, (s, l) => s + l.where((e) => e.enabled).length);

  // ── Saat ekleme ────────────────────────────────────────────────────
  Future<void> _addEntry(int weekday) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '${ScheduleService.weekdayNames[weekday - 1]} için saat',
    );
    if (time == null) return;

    final labelCtrl = TextEditingController();
    final saveLabel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '${ScheduleService.weekdayNames[weekday - 1]} • ${time.format(context)}'),
        content: TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(
            labelText: 'Not (opsiyonel)',
            hintText: 'örn. Sabah vardiyası',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ekle')),
        ],
      ),
    );
    if (saveLabel != true) return;

    final entry = ScheduleEntry(
      weekday: weekday,
      hour: time.hour,
      minute: time.minute,
      label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
    );
    final newId = await ScheduleService.instance.add(entry);
    // Eklenince alarmı otomatik kur.
    final saved = ScheduleEntry(
      id: newId,
      weekday: entry.weekday,
      hour: entry.hour,
      minute: entry.minute,
      label: entry.label,
      enabled: true,
    );
    await ScheduleService.instance.setAlarm(saved);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${ScheduleService.weekdayNames[weekday - 1]} ${time.format(context)} alarmı kuruldu'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  Future<void> _editEntry(ScheduleEntry e) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: e.hour, minute: e.minute),
    );
    if (time == null) return;
    final updated = e.copyWith(hour: time.hour, minute: time.minute);
    await ScheduleService.instance.update(updated);
    // Saat değişti — alarmı yeniden kur.
    if (e.id != null && updated.enabled) {
      await ScheduleService.instance.cancelAlarm(e.id!);
      await ScheduleService.instance.setAlarm(updated);
    }
    await _load();
  }

  Future<void> _deleteEntry(ScheduleEntry e) async {
    if (e.id != null) await ScheduleService.instance.cancelAlarm(e.id!);
    await ScheduleService.instance.delete(e.id!);
    await _load();
  }

  Future<void> _toggleEntry(ScheduleEntry e) async {
    final updated = e.copyWith(enabled: !e.enabled);
    await ScheduleService.instance.update(updated);
    // Kapatıldıysa alarmı iptal et, açıldıysa kur.
    if (e.id != null) {
      if (updated.enabled) {
        await ScheduleService.instance.setAlarm(updated);
      } else {
        await ScheduleService.instance.cancelAlarm(e.id!);
      }
    }
    await _load();
  }

  Future<void> _testAlarm() async {
    await ScheduleService.instance.testAlarmIn10s();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Alarmı Kuruldu'),
        content: const Text(
          '10 saniye sonra alarm çalacak.\n\n'
          'Şimdi ekranı KİLİTLE ve bekle. Alarm tam ekran açılmalı.\n\n'
          'Çalmazsa: Ayarlar → Uygulamalar → SKT Takip → '
          '"Alarmlar ve hatırlatıcılar" iznini ve pil ayarından '
          '"Kısıtlanmamış" seçeneğini aç.',
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam')),
        ],
      ),
    );
  }

  // ── Alarm kurma ────────────────────────────────────────────────────
  Future<void> _setOneAlarm(ScheduleEntry e) async {
    try {
      await ScheduleService.instance.setAlarm(e);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarm uygulaması açılamadı')),
        );
      }
    }
  }

  Future<void> _setAllAlarms() async {
    final all = await ScheduleService.instance.getAll();
    final active = all.where((e) => e.enabled).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktif program kaydı yok')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm Alarmları Kur'),
        content: Text(
            '$_enabledEntries aktif saat için telefonun alarm uygulamasına '
            'tek tek alarm kurulacak. Her biri için onay isteyebilir. '
            'Devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kur')),
        ],
      ),
    );
    if (ok != true) return;
    await ScheduleService.instance.setAllAlarms(active);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Çalışma Programı'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const LoadingState()
          : Column(
              children: [
                // Ozet + Tum alarmlari kur
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.card(accentColor: AppTheme.primary),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm_rounded,
                          color: AppTheme.primary, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$_totalEntries saat • $_enabledEntries aktif',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            const Text(
                                'Alarmlar uygulama içinde, kilit ekranında çalar',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      // Test alarmı
                      IconButton(
                        icon: const Icon(Icons.bug_report_rounded),
                        color: AppTheme.amber,
                        tooltip: 'Test (10 sn)',
                        onPressed: _testAlarm,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _enabledEntries == 0 ? null : _setAllAlarms,
                      icon: const Icon(Icons.alarm_add_rounded),
                      label: const Text('Tüm Alarmları Kur'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                    itemCount: 7,
                    itemBuilder: (_, i) => _dayCard(i + 1),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dayCard(int weekday) {
    final entries = _grouped[weekday] ?? [];
    final dayName = ScheduleService.weekdayNames[weekday - 1];
    final isToday = DateTime.now().weekday == weekday;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
          accentColor: isToday ? AppTheme.accent : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isToday ? AppTheme.accent : AppTheme.primary)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ScheduleService.weekdayShort[weekday - 1],
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color:
                          isToday ? AppTheme.accent : AppTheme.primary),
                ),
              ),
              const SizedBox(width: 10),
              Text(dayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              if (isToday) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: const Text('Bugün',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.black)),
                ),
              ],
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded,
                    color: AppTheme.primary),
                tooltip: 'Saat Ekle',
                onPressed: () => _addEntry(weekday),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Program yok',
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textTertiary)),
            )
          else
            ...entries.map(_entryTile),
        ],
      ),
    );
  }

  Widget _entryTile(ScheduleEntry e) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Saat
          GestureDetector(
            onTap: () => _editEntry(e),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 16,
                    color: e.enabled
                        ? AppTheme.primary
                        : AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(e.timeStr,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: e.enabled
                            ? AppTheme.textPrimary
                            : AppTheme.textTertiary,
                        decoration: e.enabled
                            ? null
                            : TextDecoration.lineThrough)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: e.label != null
                ? Text(e.label!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)
                : const SizedBox(),
          ),
          // Alarm kur
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded, size: 20),
            color: AppTheme.statusSafe,
            tooltip: 'Alarm Kur',
            visualDensity: VisualDensity.compact,
            onPressed: e.enabled ? () => _setOneAlarm(e) : null,
          ),
          // Aç/kapat
          Switch(
            value: e.enabled,
            onChanged: (_) => _toggleEntry(e),
            activeColor: AppTheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          // Sil
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppTheme.statusExpired,
            tooltip: 'Sil',
            visualDensity: VisualDensity.compact,
            onPressed: () => _deleteEntry(e),
          ),
        ],
      ),
    );
  }
}
