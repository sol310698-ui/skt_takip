import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_logger.dart';
import 'alarm_service.dart';
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
///  - Tek "su an ne olmali" durumu: [_pendingQueue] ve [_isScreenOpen].
///  - Reschedule UI'dan BAGIMSIZ: ekran acilamasa bile alarm zinciri devam eder.
///  - Ust uste ekran acilmaz; ayni alarm iki kez gosterilmez.
class AlarmFlow {
  AlarmFlow._();
  static final AlarmFlow instance = AlarmFlow._();

  /// Alarm ekranlarini acmak icin global navigator (main'de atanir).
  late final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<AlarmSettings>? _sub;

  /// Calmis ama henuz ekrani GOSTERILMEMIS alarmlar (KUYRUK).
  /// ONEMLI: Eskiden bu TEK bir alan (_PendingAlarm?) idi. Art arda yakin
  /// araliklarla (orn. 09:00 ve 09:01) birden fazla alarm calarsa, ekran
  /// hala acikken gelen ikinci alarm bu alani UZERINE YAZIYORDU — araya
  /// giren ucuncu bir alarm gelirse, ikincisi HIC GORUNMEDEN kaybolup
  /// gidiyordu (ekrani hic acilmadigi icin kullanici onu "Durdur"
  /// edemiyor, native ses/zamanlayici gorunmeden arka planda kalabiliyordu).
  /// Bu da "bir alarm acilip 1-2 saniyede kendiliginden kapaniyor" hissini
  /// yaratiyordu: aslinda kapanan alarm degil, ardindan HEMEN baska bir
  /// bekleyen alarmin ekrani acilan ayni ekranin yerine geciyordu.
  /// Simdi: kuyruk kullanarak HICBIR alarm atlanmiyor, hepsi sirayla
  /// (gelis sirasina gore) gosteriliyor.
  final List<_PendingAlarm> _pendingQueue = [];

  /// Su an bir alarm ekrani acik mi? (Ust uste acilmayi onler.)
  bool _isScreenOpen = false;

  /// ── BASLAT ──
  /// main() icinde, runApp'ten ONCE bir kez cagrilir. Dinleyiciyi runApp'ten
  /// once kurmak kritik: uygulama alarm tarafindan soguk baslatildiginda ilk
  /// ring event'i kaybolmasin.
  ///
  /// NOT: alarm 5.2.1'de API `Alarm.ringStream.stream` olup her olayda TEK bir
  /// [AlarmSettings] yayinlar (5.4.x'teki `Alarm.ringing` + `AlarmSet.alarms`
  /// DEGIL). Bu yuzden burada tek tek AlarmSettings isliyoruz.
  void start(GlobalKey<NavigatorState> navKey) {
    navigatorKey = navKey;
    _sub?.cancel();
    _sub = Alarm.ringStream.stream.listen(_onRinging);
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

  void _onRinging(AlarmSettings alarm) {
    AppLogger.instance.log('ALARM',
        'RINGING: id=${alarm.id} ses=${alarm.assetAudioPath} '
        'baslik="${alarm.notificationSettings.title}"');

    // SKT imha alarmi: SADECE bugun dolan/gecmis aktif urun varsa calsin.
    // Urun yoksa sesi hemen durdur, yarina kur, ekrani ACMA.
    if (alarm.id == ScheduleService.sktDisposalAlarmId) {
      _handleSktRinging(alarm);
      return;
    }

    // Ekran/CPU'yu uyanik tut ki ses kesilmesin (Doze modu korumasi).
    WakelockPlus.enable();

    // Zinciri UI'dan bagimsiz surdur (ekran acilmasa bile).
    _rescheduleNext(alarm.id);

    // Kuyruga ekle (hicbir alarm atlanmaz) ve gosterilebiliyorsa goster.
    // Ayni id zaten kuyrukta varsa (cok nadir, native'in cift tetiklemesi
    // gibi durumlarda) tekrar eklenmez.
    if (!_pendingQueue.any((p) => p.id == alarm.id)) {
      _pendingQueue.add(_PendingAlarm(
        id: alarm.id,
        title: alarm.notificationSettings.title,
        body: alarm.notificationSettings.body,
      ));
    }
    _showPendingIfPossible();
  }

  /// SKT alarmi ozel akisi: urun yoksa hic gosterme.
  /// ONEMLI SIRALAMA: wakelock'u HEMEN aciyoruz (veritabani sorgusunu
  /// BEKLEMEDEN). Eskiden once "await hasDueSktProducts()" sonucu
  /// bekleniyordu; bu sorgu (DB acma + tum urunleri okuma) cihaz derin
  /// uykudayken veya soguk baslatmada gecikebiliyor, bu gecikme sirasinda
  /// ekran/CPU uyanik tutulmadigi icin alarm sesi kesilebiliyordu
  /// (kullanicinin bildirdigi "uygulamayi acinca calmaya basladi" hatasi
  /// tam olarak buydu). Simdi: once uyanik tut + algoritmayi calistir,
  /// sonuc "urun yok" ise SADECE O ZAMAN durduruyoruz.
  Future<void> _handleSktRinging(AlarmSettings alarm) async {
    // 1) HEMEN uyanik tut — DB sorgusunu beklemeden. Native ses zaten
    //    calmaya baslamis olabilir; bu satir gecikirse ses kesilebilirdi.
    WakelockPlus.enable();

    // 2) Zinciri UI'dan bagimsiz hemen surdur (ekran acilmasa bile).
    unawaited(_rescheduleNext(alarm.id));

    // 3) Urun kontrolu — bu artik sesi/ekrani GECIKTIRMIYOR, sadece
    //    "urun yoksa durdur" kararini veriyor.
    final hasDue = await ScheduleService.instance.hasDueSktProducts();
    if (!hasDue) {
      AppLogger.instance.log(
          'ALARM', 'SKT alarmi: dolan urun yok, susturuldu (id=${alarm.id}).');
      await AlarmService.stop(alarm.id);
      await WakelockPlus.disable();
      return;
    }

    // Urun var -> ekranda goster (kuyruga ekle, cift eklemeyi engelle).
    if (!_pendingQueue.any((p) => p.id == alarm.id)) {
      _pendingQueue.add(_PendingAlarm(
        id: alarm.id,
        title: alarm.notificationSettings.title,
        body: alarm.notificationSettings.body,
      ));
    }
    _showPendingIfPossible();
  }

  /// Kuyruktaki ilk alarmi, kosullar uygunsa ekranda gosterir.
  void _showPendingIfPossible() {
    if (_pendingQueue.isEmpty) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      AppLogger.instance.log('ALARM',
          'Ekran bekliyor: navigator hazir degil (kuyrukta ${_pendingQueue.length} alarm).');
      return; // arayuz hazir olunca tekrar denenecek
    }

    if (_isScreenOpen) {
      // Zaten bir alarm ekrani var; kuyruktaki bu alarm sirasi gelince
      // (mevcut ekran kapaninca) gosterilecek. SILINMEZ, kuyrukta kalir.
      return;
    }

    // Kuyruktan ilk alarmi cikar + ac (FIFO: en once calan en once gosterilir).
    final p = _pendingQueue.removeAt(0);
    _isScreenOpen = true;
    AppLogger.instance.log('ALARM',
        'Alarm ekrani aciliyor id=${p.id} (kuyrukta kalan: ${_pendingQueue.length}).');

    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _buildScreenFor(p),
    );
    nav.push(route).then((_) {
      // Ekran kapandi -> bayragi sifirla, kuyrukta bekleyen varsa ac.
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
        // Haftalik program alarmi: ARTIK YENIDEN KURULMUYOR (tek atimlik).
        // Kullanici talebi: haftalik alarm tek sefer calsin. Caldiktan sonra
        // DB'de enabled=false yapiyoruz; boylece:
        //  - refreshAllAlarms onu acilista tekrar diriltmez,
        //  - kullanici listede "kapali" gorur ve isterse tekrar acar.
        await ScheduleService.instance.disableEntryByAlarmId(firedId);
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
