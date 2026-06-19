import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
            decoration: const BoxDecoration(
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
                  const Text('Alarm Türü',
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
                  const Text('Kapatınca açılacak liste (opsiyonel)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  if (lists.isEmpty)
                    const Text('Henüz kontrol listesi yok',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Alarm Ayarları',
            onPressed: _openSettingsSheet,
          ),
        ],
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
                                'Ayarlar için sağ üstteki ayar simgesine dokun',
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

                // Pil uyarisi body'de KALIR (kritik, gorunur olmali).
                if (_batteryOptimized) _buildBatteryWarning(),

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
          const Text(
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
              decoration: const BoxDecoration(
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
                  style: const TextStyle(
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
            style: const TextStyle(
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
              const Expanded(
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
            style: const TextStyle(
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
                      style: const TextStyle(
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
              if (entries.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_all_rounded,
                      color: AppTheme.accent),
                  tooltip: 'Bu günü tüm haftaya kopyala',
                  onPressed: () => _copyDayToWeek(weekday),
                ),
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

/// QR tanimlama ekrani — bir QR tarat, rawValue'sunu geri dondur.
class _QrDefineScreen extends StatefulWidget {
  const _QrDefineScreen();

  @override
  State<_QrDefineScreen> createState() => _QrDefineScreenState();
}

class _QrDefineScreenState extends State<_QrDefineScreen> {
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
                MobileScanner(controller: _ctrl, onDetect: _onDetect),
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
