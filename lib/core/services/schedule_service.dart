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

  // ════════════════════════════════════════════════════════════════════
  //  ALARM KURMA — flutter_local_notifications zonedSchedule + fullScreen
  //  (android_alarm_manager_plus KULLANILMIYOR; zonedSchedule sistem
  //   tarafından zamanlanır, ayrı isolate/callback gerektirmez, güvenilir.)
  // ════════════════════════════════════════════════════════════════════

  static int alarmId(int entryId) => 700000 + entryId;
  static int shiftAlarmId(int shiftId) => 800000 + shiftId;

  /// Haftalık tekrarlı alarm kur — her hafta o gün/saat çalar.
  Future<void> setAlarm(ScheduleEntry e) async {
    if (e.id == null) return;
    await AlarmService.instance.scheduleWeekly(
      id: alarmId(e.id!),
      weekday: e.weekday,
      hour: e.hour,
      minute: e.minute,
      title: e.label ?? 'Mesai Zamanı',
      body: '${weekdayNames[e.weekday - 1]} • ${e.timeStr}',
      kind: AlarmKind.schedule,
      refId: e.id!,
    );
  }

  Future<void> cancelAlarm(int entryId) async {
    await AlarmService.instance.cancelScheduled(alarmId(entryId));
  }

  Future<void> setAllAlarms(List<ScheduleEntry> entries) async {
    for (final e in entries.where((x) => x.enabled)) {
      await setAlarm(e);
    }
  }

  /// Test: 10 saniye sonra alarm çalar (teşhis için).
  Future<void> testAlarmIn10s() async {
    await AlarmService.instance.scheduleOnceAfter(
      id: 999999,
      delay: const Duration(seconds: 10),
      title: 'Test Alarmı ✓',
      body: 'Alarm sistemi çalışıyor!',
      kind: AlarmKind.schedule,
    );
  }

  // ── Mesai çıkış alarmı (giriş + 9 saat) ──────────────────────────────
  Future<void> setShiftCheckoutAlarm({
    required int shiftId,
    required DateTime clockIn,
  }) async {
    final when = clockIn.add(const Duration(hours: 9));
    if (when.isBefore(DateTime.now())) return;
    await AlarmService.instance.scheduleAt(
      id: shiftAlarmId(shiftId),
      when: when,
      title: 'Mesai Çıkışı',
      body: 'Çıkış yapmayı unutma! Mesain bitti gibi görünüyor.',
      kind: AlarmKind.shiftCheckout,
      refId: shiftId,
    );
  }

  Future<void> cancelShiftCheckoutAlarm(int shiftId) async {
    await AlarmService.instance.cancelScheduled(shiftAlarmId(shiftId));
  }
}
