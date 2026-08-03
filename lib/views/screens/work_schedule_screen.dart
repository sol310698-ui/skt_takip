import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../widgets/scan_error_retry.dart';
import '../../core/camera_lifecycle_mixin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/alarm_service.dart';
import '../../core/services/checklist_service.dart';
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
  bool _keepAliveOn = false; // kalici servis (swipe-kill korumasi)
  bool _qrLockOn = false; // QR ile alarm kapatma kilidi
  String? _qrValue; // tanimli QR degeri
  // Acik gunler: uzun listelerde kaydirmayi azaltmak icin gunler katlanir.
  // Ilk acilista SADECE bugun acik gelir (initState'te doldurulur).
  final Set<int> _openDays = {};

  @override
  void initState() {
    super.initState();
    _openDays.add(DateTime.now().weekday); // bugun acik baslasin
    _load();
  }

  Future<void> _load() async {
    final g = await ScheduleService.instance.getGrouped();
    final batteryOk = await AlarmService.isBatteryOptimizationDisabled();
    final sktOn = await SktAlarmSettings.instance.isEnabled();
    final sktH = await SktAlarmSettings.instance.getHour();
    final sktM = await SktAlarmSettings.instance.getMinute();
    final soundName = await SktAlarmSettings.instance.getSoundName();
    final keepAlive = await SktAlarmSettings.instance.isKeepAliveOn();
    final qrOn = await SktAlarmSettings.instance.isQrLockOn();
    final qrVal = await SktAlarmSettings.instance.getQrValue();
    if (!mounted) return;
    setState(() {
      _grouped = g;
      _batteryOptimized = !batteryOk;
      _sktAlarmOn = sktOn;
      _sktHour = sktH;
      _sktMinute = sktM;
      _soundName = soundName;
      _keepAliveOn = keepAlive;
      _qrLockOn = qrOn;
      _qrValue = qrVal;
      _loading = false;
    });
  }

  /// Kalici servis (swipe-kill korumasi) ac/kapat.
  Future<void> _toggleKeepAlive(bool value) async {
    await SktAlarmSettings.instance.setKeepAlive(value);
    if (value) {
      await AlarmService.startKeepAlive();
    } else {
      await AlarmService.stopKeepAlive();
    }
    await _load();
  }

  /// Genel alarm sesini sec (TUM alarmlar bu sesi kullanir).
  Future<void> _pickGlobalSound() async {
    final picked = await _pickSound();
    if (picked == null) return;
    await SktAlarmSettings.instance.setSound(picked.$1, picked.$2);
    // Ses degisti: tum alarmlari yeni sesle ZORLA yeniden kur.
    await ScheduleService.instance.forceResetAllAlarms();
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
    // Ses degisti: tum alarmlari yeni sesle ZORLA yeniden kur.
    await ScheduleService.instance.forceResetAllAlarms();
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

  // ── Bir gunun alarmlarini tum haftaya kopyala ──────────────────────
  Future<void> _copyDayToWeek(int sourceWeekday) async {
    final source = _grouped[sourceWeekday] ?? [];
    if (source.isEmpty) return;
    final dayName = ScheduleService.weekdayNames[sourceWeekday - 1];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tüm haftaya kopyala?'),
        content: Text(
            '$dayName günündeki ${source.length} alarm, haftanın diğer 6 gününe de eklenecek. '
            '(Mevcut alarmlar silinmez, üzerine eklenir.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kopyala')),
        ],
      ),
    );
    if (ok != true) return;

    int added = 0;
    for (int wd = 1; wd <= 7; wd++) {
      if (wd == sourceWeekday) continue;
      final existing = _grouped[wd] ?? [];
      for (final e in source) {
        // Ayni saat zaten varsa tekrar ekleme.
        final dup = existing.any((x) => x.hour == e.hour && x.minute == e.minute);
        if (dup) continue;
        final entry = ScheduleEntry(
          weekday: wd,
          hour: e.hour,
          minute: e.minute,
          label: e.label,
          enabled: true,
        );
        final newId = await ScheduleService.instance.add(entry);
        await ScheduleService.instance.setAlarm(ScheduleEntry(
          id: newId,
          weekday: wd,
          hour: e.hour,
          minute: e.minute,
          label: e.label,
          enabled: true,
        ));
        added++;
      }
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added alarm haftaya kopyalandı'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ── Alarm tipi + not + checklist secim penceresi ──────────────────
  Future<_EntryConfig?> _showEntryConfigSheet(
      int weekday, TimeOfDay time) async {
    final labelCtrl = TextEditingController();
    String type = 'normal';
    int? checklistId;
    final lists = await ChecklistService.instance.getAllWithCounts();
    if (!mounted) return null;

    return showModalBottomSheet<_EntryConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    '${ScheduleService.weekdayNames[weekday - 1]} • ${time.format(context)}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  // Alarm tipi
                  Text('Alarm Türü',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  _typeChips(type, (t) => setSheet(() => type = t)),
                  const SizedBox(height: 16),
                  // Not
                  TextField(
                    controller: labelCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Not (opsiyonel)',
                      hintText: 'örn. Sabah vardiyası',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Checklist baglama
                  Text('Kapatınca açılacak liste (opsiyonel)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  if (lists.isEmpty)
                    Text('Henüz kontrol listesi yok',
                        style: TextStyle(
                            fontSize: 12.5, color: AppTheme.textTertiary))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Yok'),
                          selected: checklistId == null,
                          onSelected: (_) =>
                              setSheet(() => checklistId = null),
                        ),
                        for (final l in lists)
                          ChoiceChip(
                            label: Text(l.checklist.title),
                            selected: checklistId == l.checklist.id,
                            onSelected: (_) => setSheet(
                                () => checklistId = l.checklist.id),
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(_EntryConfig(
                      label: labelCtrl.text.trim().isEmpty
                          ? null
                          : labelCtrl.text.trim(),
                      type: type,
                      checklistId: checklistId,
                    )),
                    child: const Text('Ekle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChips(String selected, void Function(String) onSelect) {
    final types = [
      ('normal', 'Normal', Icons.alarm_rounded),
      ('wake', 'Uyanma', Icons.wb_sunny_rounded),
      ('shift_in', 'Mesai Başlama', Icons.login_rounded),
      ('shift_out', 'Mesai Çıkış', Icons.logout_rounded),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in types)
          ChoiceChip(
            avatar: Icon(t.$3,
                size: 16,
                color: selected == t.$1 ? Colors.white : AppTheme.textSecondary),
            label: Text(t.$2),
            selected: selected == t.$1,
            onSelected: (_) => onSelect(t.$1),
          ),
      ],
    );
  }

  // ── Saat ekleme ────────────────────────────────────────────────────
  Future<void> _addEntry(int weekday) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: '${ScheduleService.weekdayNames[weekday - 1]} için saat',
    );
    if (time == null) return;
    if (!mounted) return;

    // Tip + not + checklist secimi.
    final result = await _showEntryConfigSheet(weekday, time);
    if (result == null) return;

    final entry = ScheduleEntry(
      weekday: weekday,
      hour: time.hour,
      minute: time.minute,
      label: result.label,
      alarmType: result.type,
      checklistId: result.checklistId,
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
      alarmType: entry.alarmType,
      checklistId: entry.checklistId,
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

      // SADECE .mp3 kabul et. "alarm" paketi Android'de dosya yolundan
      // .wav/.ogg gibi formatlari guvenilir calamadigi icin (alarm sessiz
      // kalip ekran acilmiyor), kullaniciyi en bastan dogru formata yonlendir.
      final lowerName = f.name.toLowerCase();
      if (!lowerName.endsWith('.mp3')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Lütfen MP3 formatında bir ses seçin. '
                  'Diğer formatlar (WAV, OGG) alarmı sessiz bırakabilir.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return null;
      }

      // Uygulamanin kalici klasorune kopyala.
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/alarm_sounds');
      if (!soundsDir.existsSync()) soundsDir.createSync(recursive: true);
      final dst =
          '${soundsDir.path}/snd_${DateTime.now().millisecondsSinceEpoch}.mp3';
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
    if (!mounted) return;
    // GERI AL: yanlislikla silinen saati tek dokunusla geri koy.
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${e.timeStr} silindi'),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Geri Al',
        textColor: AppTheme.accent,
        onPressed: () => _restoreEntries([e]),
      ),
    ));
  }

  /// Silinen kayitlari geri ekler (alarmlari da yeniden kurar).
  Future<void> _restoreEntries(List<ScheduleEntry> list) async {
    for (final e in list) {
      final entry = ScheduleEntry(
        weekday: e.weekday,
        hour: e.hour,
        minute: e.minute,
        label: e.label,
        enabled: e.enabled,
        soundPath: e.soundPath,
        soundName: e.soundName,
        alarmType: e.alarmType,
        checklistId: e.checklistId,
      );
      final newId = await ScheduleService.instance.add(entry);
      if (entry.enabled) {
        await ScheduleService.instance.setAlarm(ScheduleEntry(
          id: newId,
          weekday: e.weekday,
          hour: e.hour,
          minute: e.minute,
          label: e.label,
          enabled: true,
          soundPath: e.soundPath,
          soundName: e.soundName,
          alarmType: e.alarmType,
          checklistId: e.checklistId,
        ));
      }
    }
    await _load();
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  SERI SAAT EKLE: "04:00 → 06:00, her 10 dakikada bir" gibi bir
  ///  araligi TEK SEFERDE olusturur. Onceden bu saatler tek tek elle
  ///  ekleniyordu (36 alarm!); artik uc dokunusla biter.
  /// ══════════════════════════════════════════════════════════════════
  Future<void> _addRange(int weekday) async {
    TimeOfDay start = const TimeOfDay(hour: 4, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 6, minute: 0);
    int stepMin = 10;
    bool wholeWeek = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          int count() {
            final s0 = start.hour * 60 + start.minute;
            final e0 = end.hour * 60 + end.minute;
            if (e0 < s0 || stepMin <= 0) return 0;
            return ((e0 - s0) ~/ stepMin) + 1;
          }

          Widget timeBtn(String label, TimeOfDay v, bool isStart) {
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showTimePicker(
                      context: ctx, initialTime: v);
                  if (picked != null) {
                    setD(() {
                      if (isStart) {
                        start = picked;
                      } else {
                        end = picked;
                      }
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.hairline),
                  ),
                  child: Column(
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary)),
                      const SizedBox(height: 2),
                      Text(
                          '${v.hour.toString().padLeft(2, '0')}:'
                          '${v.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            );
          }

          final n = count();
          return AlertDialog(
            title: const Text('Seri Saat Ekle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      timeBtn('Başlangıç', start, true),
                      const SizedBox(width: 10),
                      timeBtn('Bitiş', end, false),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Aralık',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [5, 10, 15, 20, 30, 60].map((m) {
                      final sel = stepMin == m;
                      return ChoiceChip(
                        label: Text('$m dk'),
                        selected: sel,
                        onSelected: (_) => setD(() => stepMin = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: wholeWeek,
                    onChanged: (v) =>
                        setD(() => wholeWeek = v ?? false),
                    title: const Text('Tüm haftaya uygula',
                        style: TextStyle(fontSize: 13.5)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (n > 0 ? AppTheme.primary : AppTheme.amber)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      n == 0
                          ? 'Bitiş saati başlangıçtan sonra olmalı.'
                          : '$n saat eklenecek'
                              '${wholeWeek ? ' × 7 gün = ${n * 7}' : ''}'
                              ' · mevcut saatler atlanır',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: n > 0
                              ? AppTheme.primary
                              : AppTheme.amber),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                  onPressed:
                      n == 0 ? null : () => Navigator.pop(ctx, true),
                  child: const Text('Ekle')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    final days = wholeWeek ? List.generate(7, (i) => i + 1) : [weekday];
    final s0 = start.hour * 60 + start.minute;
    final e0 = end.hour * 60 + end.minute;
    int added = 0;
    for (final wd in days) {
      final existing = _grouped[wd] ?? [];
      for (int t = s0; t <= e0; t += stepMin) {
        final h = t ~/ 60, m = t % 60;
        if (existing.any((x) => x.hour == h && x.minute == m)) continue;
        final entry = ScheduleEntry(weekday: wd, hour: h, minute: m);
        final id = await ScheduleService.instance.add(entry);
        await ScheduleService.instance.setAlarm(ScheduleEntry(
            id: id, weekday: wd, hour: h, minute: m));
        added++;
      }
    }
    await _load();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$added saat eklendi'),
      backgroundColor: AppTheme.statusSafe,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// SONRAKI ALARM: bugunden baslayarak ilk aktif saati bulur.
  /// Alarm ekraninin en cok ise yarayan bilgisi — hero'da gosterilir.
  ({ScheduleEntry entry, Duration left})? _nextAlarm() {
    final now = DateTime.now();
    ScheduleEntry? best;
    Duration? bestLeft;
    for (int add = 0; add <= 7; add++) {
      final day = now.add(Duration(days: add));
      final list = _grouped[day.weekday] ?? [];
      for (final e in list) {
        if (!e.enabled) continue;
        final when = DateTime(
            day.year, day.month, day.day, e.hour, e.minute);
        if (!when.isAfter(now)) continue;
        final left = when.difference(now);
        if (bestLeft == null || left < bestLeft) {
          bestLeft = left;
          best = e;
        }
      }
      if (best != null) break; // en yakin gun bulundu
    }
    if (best == null || bestLeft == null) return null;
    return (entry: best, left: bestLeft);
  }

  // ── GUN TOPLU ISLEMLERI ────────────────────────────────────────────
  /// O gunun TUM saatlerini ac ya da kapat (tek tek ugrasma).
  Future<void> _setDayEnabled(int weekday, bool on) async {
    final list = _grouped[weekday] ?? [];
    for (final e in list) {
      if (e.enabled == on) continue;
      final upd = e.copyWith(enabled: on);
      await ScheduleService.instance.update(upd);
      if (e.id != null) {
        if (on) {
          await ScheduleService.instance.setAlarm(upd);
        } else {
          await ScheduleService.instance.cancelAlarm(e.id!);
        }
      }
    }
    await _load();
    HapticFeedback.mediumImpact();
  }

  /// O gunun tum saatlerini siler (onayli + geri alinabilir).
  Future<void> _deleteDay(int weekday) async {
    final list = List<ScheduleEntry>.from(_grouped[weekday] ?? []);
    if (list.isEmpty) return;
    final dayName = ScheduleService.weekdayNames[weekday - 1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$dayName temizlensin mi?'),
        content: Text('${list.length} saat silinecek. '
            'İstersen hemen geri alabilirsin.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final e in list) {
      if (e.id != null) {
        await ScheduleService.instance.cancelAlarm(e.id!);
        await ScheduleService.instance.delete(e.id!);
      }
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$dayName temizlendi (${list.length} saat)'),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Geri Al',
        textColor: AppTheme.accent,
        onPressed: () => _restoreEntries(list),
      ),
    ));
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
      body: _loading
          ? const LoadingState()
          : Column(
              children: [
                _hero(),
                // Pil uyarisi body'de KALIR (kritik, gorunur olmali).
                if (_batteryOptimized) _buildBatteryWarning(),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                        16, 10, 16,
                        MediaQuery.of(context).padding.bottom + 96),
                    itemCount: 7,
                    itemBuilder: (_, i) => _dayCard(i + 1),
                  ),
                ),
              ],
            ),
    );
  }

  /// GRADYAN HERO — uygulamanin tasarim dili + alarm ekraninin en kritik
  /// bilgisi: SONRAKI ALARM ve kalan sure.
  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    final next = _nextAlarm();
    final total = _totalEntries;
    final active = _enabledEntries;

    String nextText;
    if (next == null) {
      nextText = active == 0
          ? 'Aktif alarm yok'
          : 'Yaklaşan alarm bulunamadı';
    } else {
      final d = next.left;
      final h = d.inHours, m = d.inMinutes % 60;
      final dayName =
          ScheduleService.weekdayNames[next.entry.weekday - 1];
      final isToday = DateTime.now().weekday == next.entry.weekday;
      nextText = '${isToday ? 'Bugün' : dayName} ${next.entry.timeStr}'
          ' · ${h > 0 ? '$h sa ' : ''}$m dk kaldı';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.55)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
              ),
              const Expanded(
                child: Text('Çalışma Programı',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                tooltip: 'Alarm Ayarları',
                onPressed: _openSettingsSheet,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // SONRAKI ALARM paneli + sayaclar.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.alarm_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SIRADAKİ ALARM',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Colors.white.withOpacity(0.75))),
                      const SizedBox(height: 1),
                      Text(nextText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                      Text('$total saat · $active aktif',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withOpacity(0.8))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Pil uyarisi (body'de gorunur) ──
  Widget _buildBatteryWarning() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.statusExpired.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.statusExpired.withOpacity(0.4)),
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
                child: Text('Alarm susabilir!',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.statusExpired)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pil optimizasyonu açık. Telefon uykudayken alarm 1-2 saniye '
            'çalıp susabilir. Güvenilir alarm için pil optimizasyonunu KAPAT.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
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
                  padding: const EdgeInsets.symmetric(vertical: 11)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ayarlar kayan penceresi (alarm sesi + arka plan + SKT imha) ──
  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Sheet icindeki degisiklikler hem ana ekrani hem sheet'i guncelle.
          Future<void> refresh() async {
            await _load();
            setSheet(() {});
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            expand: false,
            builder: (ctx, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Alarm Ayarları',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
                      children: [
                        _toolsCard(),
                        _soundCard(onChanged: refresh),
                        _keepAliveCard(onChanged: refresh),
                        _qrLockCard(onChanged: refresh),
                        _sktCard(onChanged: refresh),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Alarm sesi karti
  /// ARAC KARTI: test alarmi + tum alarmlari yeniden kur.
  /// (Onceden test butonu ana ekranda "bocek" ikonuyla duruyordu —
  /// gunluk kullanimda kafa karistiriyordu, ayarlara alindi.)
  Widget _toolsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('Araçlar',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Alarmların gerçekten çalıştığını doğrula ya da telefon '
              'yeniden başladıysa hepsini yeniden kur.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testAlarm,
                  icon: const Icon(Icons.play_circle_outline_rounded,
                      size: 18),
                  label: const Text('Test (10 sn)',
                      style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      side: BorderSide(
                          color: AppTheme.amber.withOpacity(0.5))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _setAllAlarms,
                  icon: const Icon(Icons.alarm_on_rounded, size: 18),
                  label: const Text('Tümünü kur',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _soundCard({required Future<void> Function() onChanged}) {
    return Container(
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
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  _soundName ?? 'Varsayılan alarm sesi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (_soundName != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Varsayılana dön',
              color: AppTheme.textSecondary,
              onPressed: () async {
                await _resetGlobalSound();
                await onChanged();
              },
            ),
          FilledButton(
            onPressed: () async {
              await _pickGlobalSound();
              await onChanged();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Seç',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // Arka planda aktif tut karti
  Widget _keepAliveCard({required Future<void> Function() onChanged}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(accentColor: AppTheme.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shield_rounded,
                    color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Arka Planda Aktif Tut',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
              Switch(
                value: _keepAliveOn,
                onChanged: (v) async {
                  await _toggleKeepAlive(v);
                  await onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _keepAliveOn
                ? 'Uygulama kalıcı bir bildirimle arka planda çalışıyor. Alarmların telefonu kullanmadığında bile güvenilir çalmasına yardım eder (biraz pil kullanır).'
                : 'Alarmlar bazen uygulama kapalıyken çalmıyorsa bunu aç. Kalıcı bir bildirim gösterir ama alarmları daha güvenilir yapar.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  // SKT imha alarmi karti
  Widget _sktCard({required Future<void> Function() onChanged}) {
    return Container(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SKT İmha Alarmı',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Her gün, süresi geçen ürünleri hatırlatır',
                        style: TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Switch(
                value: _sktAlarmOn,
                activeColor: AppTheme.statusExpired,
                onChanged: (v) async {
                  await _toggleSktAlarm(v);
                  await onChanged();
                },
              ),
            ],
          ),
          if (_sktAlarmOn) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () async {
                await _pickSktTime();
                await onChanged();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded,
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
                    Icon(Icons.edit_rounded,
                        size: 15, color: AppTheme.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // QR ile alarm kapatma kilidi karti
  Widget _qrLockCard({required Future<void> Function() onChanged}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(accentColor: AppTheme.amber),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded,
                    color: AppTheme.amber, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('QR ile Kapatma',
                    style: TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
              Switch(
                value: _qrLockOn,
                activeColor: AppTheme.amber,
                onChanged: (v) async {
                  if (v && (_qrValue == null || _qrValue!.isEmpty)) {
                    // Once QR tanimla.
                    final defined = await _defineQr();
                    if (!defined) return;
                  }
                  await SktAlarmSettings.instance.setQrLock(v);
                  await onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _qrLockOn
                ? 'Alarmı kapatmak için kayıtlı QR kodu taratman gerekir. Sessize alabilirsin ama taratmadan kapatamazsın.'
                : 'Açarsan, alarmı kapatmak için bir QR kod taratman gerekir (örn. mutfaktaki bir etiket). Uyandığında yataktan kalkmanı sağlar.',
            style: TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
          ),
          if (_qrValue != null && _qrValue!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.statusSafe, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('QR tanımlı: ${_qrValue!}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary)),
                ),
                TextButton(
                  onPressed: () async {
                    await _defineQr();
                    await onChanged();
                  },
                  child: const Text('Değiştir'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// QR tanimlama: kamera ile bir QR tarat, degerini kaydet. Basari = true.
  Future<bool> _defineQr() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrDefineScreen()),
    );
    if (value != null && value.isNotEmpty) {
      await SktAlarmSettings.instance.setQrValue(value);
      if (mounted) {
        setState(() => _qrValue = value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR kod kaydedildi'),
            backgroundColor: AppTheme.statusSafe,
          ),
        );
      }
      return true;
    }
    return false;
  }

  Widget _dayCard(int weekday) {
    final entries = _grouped[weekday] ?? [];
    final dayName = ScheduleService.weekdayNames[weekday - 1];
    final isToday = DateTime.now().weekday == weekday;
    final open = _openDays.contains(weekday);
    final activeCount = entries.where((e) => e.enabled).length;
    final allOn = entries.isNotEmpty && activeCount == entries.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration:
          AppTheme.card(accentColor: isToday ? AppTheme.accent : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── BASLIK: dokununca acilir/kapanir ──
          InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            onTap: () => setState(() {
              if (open) {
                _openDays.remove(weekday);
              } else {
                _openDays.add(weekday);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
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
                          color: isToday
                              ? AppTheme.accent
                              : AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(dayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ),
                            if (isToday) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent,
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.rPill),
                                ),
                                child: const Text('Bugün',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black)),
                              ),
                            ],
                          ],
                        ),
                        // Kapaliyken bile ozet gorunur: kac saat, hangi
                        // araliкta, kaci aktif.
                        Text(
                          entries.isEmpty
                              ? 'Program yok'
                              : '${entries.length} saat · '
                                  '${entries.first.timeStr}'
                                  '${entries.length > 1 ? '–${entries.last.timeStr}' : ''}'
                                  '${activeCount < entries.length ? ' · $activeCount aktif' : ''}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  // Hizli ekleme (kapaliyken de erisilebilir).
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded,
                        color: AppTheme.primary),
                    tooltip: 'Saat Ekle',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _addEntry(weekday),
                  ),
                  Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppTheme.textTertiary),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1),
            // ── GUN ARAC CUBUGU: seri ekle, tumunu ac/kapat, diger ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _addRange(weekday),
                    icon: const Icon(Icons.timelapse_rounded, size: 17),
                    label: const Text('Seri saat',
                        style: TextStyle(fontSize: 12.5)),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppTheme.accent),
                  ),
                  const Spacer(),
                  if (entries.isNotEmpty) ...[
                    Text(allOn ? 'Tümü açık' : 'Tümünü aç',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textTertiary)),
                    Switch(
                      value: allOn,
                      onChanged: (v) => _setDayEnabled(weekday, v),
                      activeColor: AppTheme.primary,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          size: 20, color: AppTheme.textTertiary),
                      onSelected: (v) {
                        if (v == 'copy') _copyDayToWeek(weekday);
                        if (v == 'clear') _deleteDay(weekday);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'copy',
                          child: Row(children: [
                            Icon(Icons.copy_all_rounded,
                                size: 18, color: AppTheme.accent),
                            SizedBox(width: 8),
                            Text('Tüm haftaya kopyala'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: Row(children: [
                            Icon(Icons.delete_sweep_rounded,
                                size: 18, color: AppTheme.statusExpired),
                            SizedBox(width: 8),
                            Text('Günü temizle'),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          'Bu güne saat eklenmemiş. "Seri saat" ile bir '
                          'aralığı tek seferde oluşturabilirsin.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textTertiary)),
                    )
                  : Column(children: entries.map(_entryTile).toList()),
            ),
          ],
        ],
      ),
    );
  }

  /// Tek saat satiri — sola kaydirinca siler (geri alinabilir),
  /// dokununca duzenler, uzun basinca islem menusu acar.
  Widget _entryTile(ScheduleEntry e) {
    return Dismissible(
      key: ValueKey('sched_${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppTheme.statusExpired.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _deleteEntry(e),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editEntry(e),
        onLongPress: () => _entryMenu(e),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: e.enabled
                    ? AppTheme.primary.withOpacity(0.22)
                    : AppTheme.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 16,
                  color: e.enabled
                      ? AppTheme.primary
                      : AppTheme.textTertiary),
              const SizedBox(width: 8),
              Text(e.timeStr,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: e.enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary,
                      decoration:
                          e.enabled ? null : TextDecoration.lineThrough)),
              const SizedBox(width: 10),
              Expanded(
                child: e.label != null && e.label!.trim().isNotEmpty
                    ? Text(e.label!,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)
                    : const SizedBox(),
              ),
              // Tek kontrol kaldi: ac/kapat. Silme kaydirmayla, diger
              // islemler uzun basisla — satir artik ferah.
              Switch(
                value: e.enabled,
                onChanged: (_) => _toggleEntry(e),
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Satira uzun basinca acilan islem menusu.
  Future<void> _entryMenu(ScheduleEntry e) async {
    HapticFeedback.selectionClick();
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.alarm_rounded,
                      color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Text(e.timeStr,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Düzenle'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.alarm_add_rounded,
                  color: AppTheme.statusSafe),
              title: const Text('Alarmı yeniden kur'),
              enabled: e.enabled,
              onTap: () => Navigator.pop(ctx, 'set'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppTheme.statusExpired),
              title: const Text('Sil'),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (v == 'edit') _editEntry(e);
    if (v == 'set') _setOneAlarm(e);
    if (v == 'del') _deleteEntry(e);
  }
}

/// QR tanimlama ekrani — bir QR tarat, rawValue'sunu geri dondur.
class _QrDefineScreen extends StatefulWidget {
  const _QrDefineScreen();

  @override
  State<_QrDefineScreen> createState() => _QrDefineScreenState();
}

class _QrDefineScreenState extends State<_QrDefineScreen> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [_ctrl];
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(v.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('QR Kodu Tara'),
        backgroundColor: AppTheme.amber,
        foregroundColor: Colors.black,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.amber),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Sabahları taratacağın QR kodu şimdi tarat. '
              'Mutfak, banyo gibi yataktan kalkmanı gerektiren bir yere yapıştırabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(controller: _ctrl, onDetect: _onDetect, errorBuilder: (context, error, child) => ScanErrorRetry(controller: _ctrl)),
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.amber, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alarm ekleme yapilandirmasi (tip + not + checklist).
class _EntryConfig {
  final String? label;
  final String type;
  final int? checklistId;
  const _EntryConfig({this.label, required this.type, this.checklistId});
}
