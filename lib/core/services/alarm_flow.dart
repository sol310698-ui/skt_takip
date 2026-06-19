import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_logger.dart';
import 'schedule_service.dart';
import 'skt_alarm_settings.dart';
import '../../views/screens/alarm_ring_screen.dart';
import '../../views/screens/skt_disposal_alarm_screen.dart';

/// Alarm calma akisini bastan sona yoneten TEK sinif.
///
/// Sorumluluklar (sadece bunlar):
///  1. `alarm` paketinin `ringing` stream'ini dinlemek.
///  2. Alarm caldiginda: ekrani uyanik tutmak (wakelock), alarmi bir sonraki
///     olusuma yeniden kurmak (zincir kopmasin), dogru alarm ekranini acmak.
///  3. Arayuz henuz hazir degilse (soguk baslatma) alarmi BEKLETIP, arayuz
///     hazir olunca veya uygulama one geldiginde gostermek.
///
/// Tasarim ilkeleri:
///  - Tek giris noktasi: [start] (main'de bir kez cagrilir).
///  - Tek "su an ne olmali" durumu: [_pending] ve [_isScreenOpen].
///  - Reschedule UI'dan BAGIMSIZ: ekran acilamasa bile alarm zinciri devam eder.
///  - Ust uste ekran acilmaz; ayni alarm iki kez gosterilmez.
class AlarmFlow {
  AlarmFlow._();
  static final AlarmFlow instance = AlarmFlow._();

  /// Alarm ekranlarini acmak icin global navigator (main'de atanir).
  late final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<AlarmSet>? _sub;

  /// Calmis ama henuz ekrani GOSTERILMEMIS alarm. Arayuz hazir olunca acilir.
  _PendingAlarm? _pending;

  /// Su an bir alarm ekrani acik mi? (Ust uste acilmayi onler.)
  bool _isScreenOpen = false;

  /// ── BASLAT ──
  /// main() icinde, runApp'ten ONCE bir kez cagrilir. Dinleyiciyi runApp'ten
  /// once kurmak kritik: uygulama alarm tarafindan soguk baslatildiginda ilk
  /// `ringing` event'i kaybolmasin.
  void start(GlobalKey<NavigatorState> navKey) {
    navigatorKey = navKey;
    _sub?.cancel();
    _sub = Alarm.ringing.listen(_onRinging);
    AppLogger.instance.log('ALARM', 'AlarmFlow baslatildi (dinleyici kuruldu).');
  }

  /// Arayuz ilk kez hazir oldugunda (ilk frame) ve uygulama her one geldiginde
  /// (resumed) cagrilir. Bekleyen alarm varsa gosterir.
  void onUiReady() => _showPendingIfPossible();

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ───────────────────────── ic akis ─────────────────────────

  void _onRinging(AlarmSet alarmSet) {
    final alarms = alarmSet.alarms;
    AppLogger.instance.log('ALARM',
        'RINGING: ${alarms.length} alarm, idler=${alarms.map((a) => a.id).toList()}');

    if (alarms.isEmpty) {
      // Bos set: tum alarmlar durmus demektir. Wakelock'u birak.
      WakelockPlus.disable();
      return;
    }

    // Ekran/CPU'yu uyanik tut ki ses kesilmesin (Doze modu korumasi).
    WakelockPlus.enable();

    // Birden fazla alarm ayni anda calabilir; ilkini gosteririz, digerleri
    // sirayla (ekran kapaninca) gelir. Hepsini yeniden kurariz.
    for (final alarm in alarms) {
      AppLogger.instance.log('ALARM',
          'Caliyor id=${alarm.id} ses=${alarm.assetAudioPath} '
          'baslik="${alarm.notificationSettings.title}"');
      // Zinciri UI'dan bagimsiz surdur (ekran acilmasa bile).
      _rescheduleNext(alarm.id);
    }

    // Ekranda ilk alarmi goster (digerleri bekler).
    final first = alarms.first;
    _pending = _PendingAlarm(
      id: first.id,
      title: first.notificationSettings.title,
      body: first.notificationSettings.body,
    );
    _showPendingIfPossible();
  }

  /// Bekleyen alarmi, kosullar uygunsa ekranda gosterir.
  void _showPendingIfPossible() {
    final p = _pending;
    if (p == null) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      AppLogger.instance.log('ALARM',
          'Ekran bekliyor: navigator hazir degil (id=${p.id}).');
      return; // arayuz hazir olunca tekrar denenecek
    }

    if (_isScreenOpen) {
      // Zaten bir alarm ekrani var; bu alarm o kapaninca gosterilecek.
      return;
    }

    // Tuket + ac.
    _pending = null;
    _isScreenOpen = true;
    AppLogger.instance.log('ALARM', 'Alarm ekrani aciliyor id=${p.id}.');

    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _buildScreenFor(p),
    );
    nav.push(route).then((_) {
      // Ekran kapandi -> bayragi sifirla, sirada bekleyen alarm varsa ac.
      _isScreenOpen = false;
      _showPendingIfPossible();
    });
  }

  /// Alarm ID'sine gore dogru ekrani uretir.
  Widget _buildScreenFor(_PendingAlarm p) {
    // SKT imha alarmi (sabit ID) -> ozel ekran.
    if (p.id == ScheduleService.sktDisposalAlarmId) {
      return SktDisposalAlarmScreen(
        alarmId: p.id,
        onGoToList: () => navigatorKey.currentState?.popUntil((r) => r.isFirst),
      );
    }
    // Mesai alarmi (800000-899999, SKT imha haric) -> shift modunda.
    final isShift = p.id >= 800000 &&
        p.id < 900000 &&
        p.id != ScheduleService.sktDisposalAlarmId;
    return AlarmRingScreen(
      alarmId: p.id,
      title: p.title,
      body: p.body,
      isShift: isShift,
      shiftId: isShift ? p.id - 800000 : null,
    );
  }

  /// Calan alarmi turune gore bir sonraki olusuma yeniden kurar.
  /// UI'dan bagimsiz; ekran acilmasa bile zincir devam eder.
  Future<void> _rescheduleNext(int firedId) async {
    try {
      if (firedId == ScheduleService.sktDisposalAlarmId) {
        // Gunluk SKT imha alarmi: ertesi gun ayni saate.
        if (await SktAlarmSettings.instance.isEnabled()) {
          final h = await SktAlarmSettings.instance.getHour();
          final m = await SktAlarmSettings.instance.getMinute();
          await ScheduleService.instance.rescheduleSktDisposal(hour: h, minute: m);
        }
      } else if (firedId >= 700000 && firedId < 800000) {
        // Haftalik program alarmi: bir sonraki ayni gun/saate.
        await ScheduleService.instance.rescheduleIfWeekly(firedId);
      }
      // Mesai cikis alarmi (800000+) tek seferlik; yeniden kurulmaz.
    } catch (e) {
      AppLogger.instance.log('ALARM', 'Reschedule hatasi id=$firedId: $e');
    }
  }
}

/// Gosterilmeyi bekleyen alarmin minimal verisi.
class _PendingAlarm {
  final int id;
  final String title;
  final String body;
  const _PendingAlarm({
    required this.id,
    required this.title,
    required this.body,
  });
}
