import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';

import '../constants/app_constants.dart';
import 'alarm_service.dart';
import 'database_service.dart';

/// Haftalik calisma programi kalemi (gun + saat).
class ScheduleEntry {
  final int? id;
  final int weekday;  // 1=Pzt ... 7=Paz (DateTime.weekday ile uyumlu)
  final int hour;
  final int minute;
  final String? label;
  final bool enabled;

  const ScheduleEntry({
    this.id,
    required this.weekday,
    required this.hour,
    required this.minute,
    this.label,
    this.enabled = true,
  });

  String get timeStr =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  factory ScheduleEntry.fromMap(Map<String, Object?> m) => ScheduleEntry(
        id: m['id'] as int?,
        weekday: m['weekday'] as int,
        hour: m['hour'] as int,
        minute: m['minute'] as int,
        label: m['label'] as String?,
        enabled: (m['enabled'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled ? 1 : 0,
      };

  ScheduleEntry copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
  }) =>
      ScheduleEntry(
        id: id,
        weekday: weekday,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
      );
}

class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  // Gun adlari (1=Pzt)
  static const List<String> weekdayNames = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];
  static const List<String> weekdayShort = [
    'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'
  ];

  Future<int> add(ScheduleEntry e) async {
    final db = await DatabaseService.instance.database;
    return db.insert(
        AppConstants.workScheduleTable, e.toMap()..remove('id'));
  }

  Future<void> update(ScheduleEntry e) async {
    final db = await DatabaseService.instance.database;
    await db.update(AppConstants.workScheduleTable, e.toMap(),
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.workScheduleTable,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ScheduleEntry>> getAll() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.workScheduleTable,
        orderBy: 'weekday ASC, hour ASC, minute ASC');
    return rows.map(ScheduleEntry.fromMap).toList();
  }

  /// Gunlere gore grupla (1..7).
  Future<Map<int, List<ScheduleEntry>>> getGrouped() async {
    final all = await getAll();
    final map = <int, List<ScheduleEntry>>{};
    for (final e in all) {
      map.putIfAbsent(e.weekday, () => []).add(e);
    }
    return map;
  }

  /// Bir sonraki [weekday] gününün [hour]:[minute] anını hesaplar.
  static DateTime _nextOccurrence(int weekday, int hour, int minute) {
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day, hour, minute);
    // Hedef güne ilerle.
    while (date.weekday != weekday || date.isBefore(now)) {
      date = date.add(const Duration(days: 1));
      date = DateTime(date.year, date.month, date.day, hour, minute);
    }
    return date;
  }

  /// Alarm id → AndroidAlarmManager için benzersiz int.
  static int alarmId(int entryId) => 700000 + entryId;

  /// Uygulama içi alarmı kur (kilit ekranında çalar).
  /// android_alarm_manager_plus ile cihaz uykudayken bile tetiklenir,
  /// callback haftalık tekrar için kendini yeniden kurar.
  Future<void> setAlarm(ScheduleEntry e) async {
    if (e.id == null) return;
    final when = _nextOccurrence(e.weekday, e.hour, e.minute);
    await AndroidAlarmManager.oneShotAt(
      when,
      alarmId(e.id!),
      scheduleAlarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  Future<void> cancelAlarm(int entryId) async {
    await AndroidAlarmManager.cancel(alarmId(entryId));
  }

  /// Tüm aktif kalemler için alarmları kurar.
  Future<void> setAllAlarms(List<ScheduleEntry> entries) async {
    for (final e in entries.where((x) => x.enabled)) {
      await setAlarm(e);
    }
  }

  // ── Mesai çıkış alarmı ──────────────────────────────────────────────
  static int shiftAlarmId(int shiftId) => 800000 + shiftId;

  /// Mesai çıkış alarmı kur: giriş + 9 saat (8→17, 13→22).
  Future<void> setShiftCheckoutAlarm({
    required int shiftId,
    required DateTime clockIn,
  }) async {
    final when = clockIn.add(const Duration(hours: 9));
    if (when.isBefore(DateTime.now())) return;
    await AndroidAlarmManager.oneShotAt(
      when,
      shiftAlarmId(shiftId),
      shiftCheckoutCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  Future<void> cancelShiftCheckoutAlarm(int shiftId) async {
    await AndroidAlarmManager.cancel(shiftAlarmId(shiftId));
  }
}

/// ════════════════════════════════════════════════════════════════════
///  TOP-LEVEL ALARM CALLBACK
///  android_alarm_manager_plus bunu ayrı bir isolate'te çağırır.
///  Burada alarmı çaldırır ve haftalık tekrar için yeniden kurar.
/// ════════════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> scheduleAlarmCallback(int alarmId) async {
  // Ayrı isolate — plugin'leri başlat.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final entryId = alarmId - 700000;

  // DB'den ilgili kaydı bul.
  ScheduleEntry? entry;
  try {
    final entries = await ScheduleService.instance.getAll();
    for (final e in entries) {
      if (e.id == entryId) {
        entry = e;
        break;
      }
    }
  } catch (_) {}
  if (entry == null || !entry.enabled) return;

  // Alarmı çaldır (tam ekran bildirim + ses + titreşim).
  await AlarmService.instance.fireAlarm(RingingAlarm(
    id: 700000 + entryId,
    title: entry.label ?? 'Mesai Zamanı',
    body:
        '${ScheduleService.weekdayNames[entry.weekday - 1]} • ${entry.timeStr}',
    kind: AlarmKind.schedule,
    refId: entryId,
  ));

  // Haftalık tekrar: bir sonraki aynı güne yeniden kur.
  await ScheduleService.instance.setAlarm(entry);
}

/// Mesai çıkış alarmı callback'i (giriş + 9 saat). Tek seferlik.
@pragma('vm:entry-point')
Future<void> shiftCheckoutCallback(int alarmId) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final shiftId = alarmId - 800000;
  await AlarmService.instance.fireAlarm(RingingAlarm(
    id: alarmId,
    title: 'Mesai Çıkışı',
    body: 'Çıkış yapmayı unutma! Mesain bitti gibi görünüyor.',
    kind: AlarmKind.shiftCheckout,
    refId: shiftId,
  ));
}
