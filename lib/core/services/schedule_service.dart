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
  final String? soundPath; // telefondaki muzik dosyasi yolu (null = varsayilan)
  final String? soundName;  // gosterim adi (orn. "Sabah.mp3")

  const ScheduleEntry({
    this.id,
    required this.weekday,
    required this.hour,
    required this.minute,
    this.label,
    this.enabled = true,
    this.soundPath,
    this.soundName,
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
        soundPath: m['sound_path'] as String?,
        soundName: m['sound_name'] as String?,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled ? 1 : 0,
        'sound_path': soundPath,
        'sound_name': soundName,
      };

  ScheduleEntry copyWith({
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    String? soundPath,
    String? soundName,
  }) =>
      ScheduleEntry(
        id: id,
        weekday: weekday,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
        soundPath: soundPath ?? this.soundPath,
        soundName: soundName ?? this.soundName,
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
  //  ALARM KURMA — "alarm" paketi (native, kilit ekraninda calisir)
  //  Haftalik tekrar paket tarafindan desteklenmedigi icin, alarm
  //  caldiginda main.dart bir sonraki haftaya yeniden kurar.
  // ════════════════════════════════════════════════════════════════════

  static int alarmId(int entryId) => 700000 + entryId;
  static int shiftAlarmId(int shiftId) => 800000 + shiftId;

  /// Bir sonraki [weekday] gununun [hour]:[minute] anini hesaplar.
  static DateTime nextOccurrence(int weekday, int hour, int minute) {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day, hour, minute);
    while (d.weekday != weekday || d.isBefore(now)) {
      d = d.add(const Duration(days: 1));
      d = DateTime(d.year, d.month, d.day, hour, minute);
    }
    return d;
  }

  /// Haftalik alarmi kur (bir sonraki o gun/saate).
  /// Ses: kullanicinin sectigi GENEL alarm sesi (AlarmService otomatik okur).
  Future<void> setAlarm(ScheduleEntry e) async {
    if (e.id == null) return;
    final when = nextOccurrence(e.weekday, e.hour, e.minute);
    await AlarmService.setAlarmAt(
      id: alarmId(e.id!),
      when: when,
      title: e.label ?? 'Mesai Zamani',
      body: '${weekdayNames[e.weekday - 1]} - ${e.timeStr}',
    );
  }

  Future<void> cancelAlarm(int entryId) async {
    await AlarmService.stop(alarmId(entryId));
  }

  Future<void> setAllAlarms(List<ScheduleEntry> entries) async {
    for (final e in entries.where((x) => x.enabled)) {
      await setAlarm(e);
    }
  }

  /// Tum aktif haftalik alarmlari DB'den okuyup yeniden kur.
  /// (Genel alarm sesi degisince hepsini yeni sesle yenilemek icin.)
  Future<void> refreshAllAlarms() async {
    final all = await getAll();
    for (final e in all.where((x) => x.enabled)) {
      await setAlarm(e);
    }
  }

  /// Test: 10 saniye sonra alarm calar.
  Future<void> testAlarmIn10s() async {
    await AlarmService.setAlarmAt(
      id: 999999,
      when: DateTime.now().add(const Duration(seconds: 10)),
      title: 'Test Alarmi',
      body: 'Alarm sistemi calisiyor!',
    );
  }

  // ── Mesai cikis alarmi (giris + 9 saat) ──────────────────────────────
  Future<void> setShiftCheckoutAlarm({
    required int shiftId,
    required DateTime clockIn,
  }) async {
    final when = clockIn.add(const Duration(hours: 9));
    if (when.isBefore(DateTime.now())) return;
    await AlarmService.setAlarmAt(
      id: shiftAlarmId(shiftId),
      when: when,
      title: 'Mesai Cikisi',
      body: 'Cikis yapmayi unutma! Mesain bitti gibi gorunuyor.',
    );
  }

  Future<void> cancelShiftCheckoutAlarm(int shiftId) async {
    await AlarmService.stop(shiftAlarmId(shiftId));
  }

  // ── SKT IMHA alarmi (her gun aksam, suresi gecmis urunler icin) ──────
  // Sabit ID; gunluk tekrar eden tek alarm.
  static const int sktDisposalAlarmId = 850000;

  /// Gunluk SKT imha alarmini [hour]:[minute] icin kur (bir sonraki olusum).
  Future<void> setSktDisposalAlarm({int hour = 19, int minute = 0}) async {
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) {
      when = when.add(const Duration(days: 1)); // bugun gecmisse yarina
    }
    await AlarmService.setAlarmAt(
      id: sktDisposalAlarmId,
      when: when,
      title: 'SKT Kontrolü',
      body: 'Süresi geçen ürünleri imha/iadeye al',
    );
  }

  Future<void> cancelSktDisposalAlarm() async {
    await AlarmService.stop(sktDisposalAlarmId);
  }

  /// SKT imha alarmi caldiginda ertesi gune yeniden kur (gunluk tekrar).
  Future<void> rescheduleSktDisposal({int hour = 19, int minute = 0}) async {
    final now = DateTime.now();
    final when =
        DateTime(now.year, now.month, now.day, hour, minute)
            .add(const Duration(days: 1));
    await AlarmService.setAlarmAt(
      id: sktDisposalAlarmId,
      when: when,
      title: 'SKT Kontrolü',
      body: 'Süresi geçen ürünleri imha/iadeye al',
    );
  }

  /// Alarm caldiginda haftalik tekrar icin yeniden kur.
  /// (Sadece schedule alarmlari icin; mesai alarmi tek seferlik.)
  Future<void> rescheduleIfWeekly(int firedAlarmId) async {
    if (firedAlarmId < 700000 || firedAlarmId >= 800000) return;
    final entryId = firedAlarmId - 700000;
    final all = await getAll();
    for (final e in all) {
      if (e.id == entryId && e.enabled) {
        await setAlarm(e);
        return;
      }
    }
  }
}
