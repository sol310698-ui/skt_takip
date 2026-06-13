import 'package:android_intent_plus/android_intent.dart';

import '../constants/app_constants.dart';
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

  // Android AlarmClock DAYS sabitleri: Pazar=1..Cumartesi=7
  // DateTime.weekday: Pzt=1..Paz=7 -> donusum gerekiyor.
  static int _toAlarmClockDay(int dtWeekday) {
    // dt: 1=Pzt..7=Paz  →  alarmclock: 1=Paz,2=Pzt..7=Cmt
    return dtWeekdayToAlarmClock[dtWeekday]!;
  }

  static const Map<int, int> dtWeekdayToAlarmClock = {
    1: 2, // Pzt
    2: 3, // Sal
    3: 4, // Çar
    4: 5, // Per
    5: 6, // Cum
    6: 7, // Cmt
    7: 1, // Paz
  };

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

  /// Telefonun alarm uygulamasina TEK haftalik tekrarli alarm kurar.
  Future<void> setAlarm(ScheduleEntry e) async {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      flags: <int>[
        268435456, // FLAG_ACTIVITY_NEW_TASK (0x10000000)
      ],
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': e.hour,
        'android.intent.extra.alarm.MINUTES': e.minute,
        'android.intent.extra.alarm.MESSAGE':
            e.label ?? 'Mesai - ${weekdayNames[e.weekday - 1]}',
        'android.intent.extra.alarm.DAYS': <int>[_toAlarmClockDay(e.weekday)],
        // SKIP_UI false → alarm uygulaması açılıp onay alır.
        'android.intent.extra.alarm.SKIP_UI': false,
      },
    );
    await intent.launch();
  }

  /// Tum aktif kalemleri sirayla alarm olarak kurar.
  /// (Kullanici her biri icin alarm uygulamasinda onaylar.)
  Future<void> setAllAlarms(List<ScheduleEntry> entries) async {
    for (final e in entries.where((x) => x.enabled)) {
      await setAlarm(e);
      // Kisa bekleme — intent'ler ust uste binmesin.
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }
}
