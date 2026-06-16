import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/alarm_service.dart';
import '../../core/services/schedule_service.dart';
import '../../core/services/skt_alarm_settings.dart';
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
  bool _batteryOptimized = false; // true: pil optimizasyonu ACIK (sorun)
  bool _sktAlarmOn = false;
  int _sktHour = 19;
  int _sktMinute = 0;
  String? _soundName; // genel alarm sesi adi (null = varsayilan)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await ScheduleService.instance.getGrouped();
    final batteryOk = await AlarmService.isBatteryOptimizationDisabled();
    final sktOn = await SktAlarmSettings.instance.isEnabled();
    final sktH = await SktAlarmSettings.instance.getHour();
    final sktM = await SktAlarmSettings.instance.getMinute();
    final soundName = await SktAlarmSettings.instance.getSoundName();
    if (!mounted) return;
    setState(() {
      _grouped = g;
      _batteryOptimized = !batteryOk;
      _sktAlarmOn = sktOn;
      _sktHour = sktH;
      _sktMinute = sktM;
      _soundName = soundName;
      _loading = false;
    });
  }

  /// Genel alarm sesini sec (TUM alarmlar bu sesi kullanir).
  Future<void> _pickGlobalSound() async {
    final picked = await _pickSound();
    if (picked == null) return;
    await SktAlarmSettings.instance.setSound(picked.$1, picked.$2);
    // Mevcut tum alarmlari yeni sesle yeniden kur.
    await ScheduleService.instance.refreshAllAlarms();
    if (_sktAlarmOn) {
      await ScheduleService.instance
          .setSktDisposalAlarm(hour: _sktHour, minute: _sktMinute);
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm sesi ayarlandı: ${picked.$2}'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  /// Alarm sesini varsayilana dondur.
  Future<void> _resetGlobalSound() async {
    await SktAlarmSettings.instance.clearSound();
    await ScheduleService.instance.refreshAllAlarms();
    if (_sktAlarmOn) {
      await ScheduleService.instance
          .setSktDisposalAlarm(hour: _sktHour, minute: _sktMinute);
    }
    await _load();
  }

  Future<void> _toggleSktAlarm(bool on) async {
    await SktAlarmSettings.instance.setEnabled(on);
    if (on) {
      await ScheduleService.instance
          .setSktDisposalAlarm(hour: _sktHour, minute: _sktMinute);
    } else {
      await ScheduleService.instance.cancelSktDisposalAlarm();
    }
    await _load();
  }

  Future<void> _pickSktTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _sktHour, minute: _sktMinute),
    );
    if (picked == null) return;
    await SktAlarmSettings.instance.setTime(picked.hour, picked.minute);
    // Acik ise yeni saate gore yeniden kur.
    if (_sktAlarmOn) {
      await ScheduleService.instance
          .setSktDisposalAlarm(hour: picked.hour, minute: picked.minute);
    }
    await _load();
  }

  Future<void> _fixBattery() async {
    await AlarmService.requestDisableBatteryOptimization();
    await _load();
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
    if (!mounted) return;

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
    // Eklenince alarmı otomatik kur (genel alarm sesiyle).
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

  /// Telefondan ses dosyasi sec. (yol, gosterim_adi) doner; iptalde null.
  /// KRITIK: Secilen dosya uygulamanin KALICI klasorune kopyalanir. Cunku
  /// file_picker'in verdigi gecici yol, alarm gunler sonra caldiginda
  /// sistem tarafindan silinmis olabilir -> ses calmaz. Kopya kalici kalir.
  Future<(String, String)?> _pickSound() async {
    try {
      // Android 13+ icin ses okuma izni.
      if (await Permission.audio.isDenied) {
        await Permission.audio.request();
      }
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.first;
      if (f.path == null) return null;

      // Uygulamanin kalici klasorune kopyala.
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/alarm_sounds');
      if (!soundsDir.existsSync()) soundsDir.createSync(recursive: true);
      // Dosya adini koru ama benzersiz yap.
      final ext = f.name.contains('.') ? f.name.split('.').last : 'mp3';
      final dst =
          '${soundsDir.path}/snd_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(f.path!).copy(dst);

      return (dst, f.name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ses dosyası seçilemedi')),
        );
      }
      return null;
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

  Future<void> _openFullScreenIntentSettings() async {
    // Native kanal (Android 14+ icin dogru ayar sayfasi).
    await AlarmService.openFullScreenIntentSettings();
  }

  Future<void> _testAlarm() async {
    // Once tam ekran izni var mi kontrol et.
    final canFsi = await AlarmService.canUseFullScreenIntent();
    if (!mounted) return;

    if (!canFsi) {
      // Izin yok — kullaniciyi uyar ve ayara yonlendir.
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tam Ekran İzni Gerekli'),
          content: const Text(
            'Alarmın kilit ekranının üzerinde tam ekran açılması için '
            '"Tam ekran bildirimler" iznini vermen gerekiyor.\n\n'
            'Açılan ayarda SKT Takip için bu izni AÇIK yap, sonra '
            'tekrar test et.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openFullScreenIntentSettings();
              },
              child: const Text('İzni Aç'),
            ),
          ],
        ),
      );
      return;
    }

    // Izin var — test alarmini kur.
    await ScheduleService.instance.testAlarmIn10s();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test Alarmı Kuruldu'),
        content: const Text(
          '10 saniye sonra alarm çalacak.\n\n'
          'Şimdi ekranı KİLİTLE ve bekle. Alarm kilit ekranının '
          'üzerine tam ekran gelmeli.\n\n'
          'Açılmazsa pil ayarından "Kısıtlanmamış" seç ve Samsung '
          'cihazlarda "Otomatik başlatma"yı aç.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openFullScreenIntentSettings();
            },
            child: const Text('Tam Ekran İzni'),
          ),
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

                // ── Pil optimizasyonu uyarisi (alarm susmasini onler) ──
                if (_batteryOptimized)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.statusExpired.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.statusExpired.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.battery_alert_rounded,
                                color: AppTheme.statusExpired, size: 24),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Alarm susabilir!',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.statusExpired),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Pil optimizasyonu açık. Telefon uykudayken alarm '
                          '1-2 saniye çalıp susabilir. Güvenilir alarm için '
                          'pil optimizasyonunu KAPAT.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSecondary,
                              height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _fixBattery,
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: const Text('Pil Optimizasyonunu Kapat'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.statusExpired,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11)),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Genel Alarm Sesi (TUM alarmlar icin tek ses) ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.card(accentColor: AppTheme.primary),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _soundName == null
                              ? Icons.music_note_outlined
                              : Icons.music_note_rounded,
                          color: AppTheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Alarm Sesi',
                                style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                              _soundName ?? 'Varsayılan alarm sesi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (_soundName != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: 'Varsayılana dön',
                          color: AppTheme.textSecondary,
                          onPressed: _resetGlobalSound,
                        ),
                      FilledButton(
                        onPressed: _pickGlobalSound,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        child: const Text('Seç',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),

                // ── SKT İmha Alarmı (her gun aksam) ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.card(accentColor: AppTheme.statusExpired),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.statusExpired.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.delete_sweep_rounded,
                                color: AppTheme.statusExpired, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('SKT İmha Alarmı',
                                    style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800)),
                                SizedBox(height: 2),
                                Text(
                                    'Her gün, süresi geçen ürünleri hatırlatır',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _sktAlarmOn,
                            activeColor: AppTheme.statusExpired,
                            onChanged: _toggleSktAlarm,
                          ),
                        ],
                      ),
                      if (_sktAlarmOn) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: _pickSktTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceAlt,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule_rounded,
                                    size: 20, color: AppTheme.textSecondary),
                                const SizedBox(width: 12),
                                const Text('Alarm saati',
                                    style: TextStyle(fontSize: 14)),
                                const Spacer(),
                                Text(
                                  '${_sktHour.toString().padLeft(2, '0')}:'
                                  '${_sktMinute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primary),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.edit_rounded,
                                    size: 15, color: AppTheme.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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
