import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../data/models/product.dart';
import '../constants/app_constants.dart';

/// Yerel bildirimleri yöneten servis.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Mesai "Bitir" aksiyonuna basildiginda tetiklenecek callback.
  // main.dart'tan veya shift ekranindan atanir.
  static void Function(int shiftId)? onShiftFinishRequested;

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@drawable/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      // "Alarmlar ve hatırlatıcılar" iznini iste (Samsung/Android 13+).
      await androidImpl?.requestExactAlarmsPermission();

      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

  /// Bildirim ya da aksiyon butonuna basilinca.
  static void _onNotificationResponse(NotificationResponse resp) {
    final payload = resp.payload ?? '';
    if (payload.startsWith('shift_checkout:')) {
      final shiftId = int.tryParse(payload.split(':').last);
      if (shiftId == null) return;
      // "Bitir" aksiyonu veya bildirime dokunma → çıkış akışı.
      if (resp.actionId == 'shift_finish' || resp.actionId == null) {
        onShiftFinishRequested?.call(shiftId);
      }
      // "Yoksay" → cancelNotification:true zaten kapatıyor, ek iş yok.
    }
  }

  /// Mesai çıkış hatırlatması — giriş + 9 saat sonra.
  /// "Bitir" ve "Yoksay" aksiyon butonları içerir.
  /// shiftId payload olarak iletilir; uygulama açılınca çıkış akışı tetiklenir.
  Future<void> scheduleShiftCheckoutReminder({
    required int shiftId,
    required DateTime clockIn,
  }) async {
    if (!_initialized) await init();
    final fireAt = clockIn.add(const Duration(hours: 9));
    // Geçmişse kurma.
    if (fireAt.isBefore(DateTime.now())) return;

    final tzTime = tz.TZDateTime.from(fireAt, tz.local);
    final androidDetails = AndroidNotificationDetails(
      'shift_checkout',
      'Mesai Çıkış Hatırlatma',
      channelDescription: 'Mesai bitiş saatinde çıkış hatırlatması',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: const [
        AndroidNotificationAction('shift_finish', 'Bitir',
            showsUserInterface: true),
        AndroidNotificationAction('shift_ignore', 'Yoksay',
            cancelNotification: true),
      ],
    );

    // Onceki ayni shiftId icin kurulmus olabilecek alarmi once iptal et
    // (idempotent: tekrar cagrilirsa cakisma/birikme olmasin).
    await _plugin.cancel(_shiftNotifId(shiftId));
    try {
      await _plugin.zonedSchedule(
        _shiftNotifId(shiftId),
        'Mesai Çıkışı',
        'Çıkış yapmayı unutma! Mesain bitti gibi görünüyor.',
        tzTime,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'shift_checkout:$shiftId',
      );
    } catch (e) {
      // Limit/izin hatasinda uygulama crash olmasin.
    }
  }

  Future<void> cancelShiftCheckout(int shiftId) async {
    if (!_initialized) await init();
    await _plugin.cancel(_shiftNotifId(shiftId));
  }

  // Mesai bildirimleri icin ayri id araligi (cakismayi onlemek icin).
  int _shiftNotifId(int shiftId) => 900000 + shiftId;

  /// Eski 100x sema (v24 ve oncesi) ile planlanmis bildirimleri temizler.
  /// Guvenlik icin genis aralik: her urun icin eski ve yeni schema dener.
  /// Cagiran: ProductListNotifier.build (uygulama acilisinda bir kez).
  Future<void> migrateOldSchemaIfNeeded(List<int> productIds) async {
    if (!_initialized) await init();
    // Eski carpan 100 ile uretilen id'leri iptal et.
    for (final id in productIds) {
      for (final threshold in AppConstants.defaultNotifyThresholds) {
        await _plugin.cancel(id * 100 + threshold);
      }
    }
  }

  /// YETİM ALARM TEMİZLİĞİ: artık var olmayan (silinmiş/eskiden kalmış)
  /// ürünlere ait SKT alarmlarını topluca temizler. "concurrent alarms 500
  /// reached" crashinin asil kaynagi budur — mukerrer kayit/guncelleme
  /// donemlerinde biriken yetim alarmlar gercek urun sayisinin cok ustune
  /// cikabilir. Uygulama acilisinda bir kez, mevcut urun id listesiyle
  /// cagrilir (ProductListNotifier.build).
  Future<void> purgeOrphanProductAlarms(List<int> validProductIds) async {
    if (!_initialized) await init();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final validIds = validProductIds.toSet();
      for (final req in pending) {
        // Sadece urun-SKT alarm araligi (id < 900000; mesai/grup alarmlari
        // farkli araliklarda, onlara dokunma).
        if (req.id >= 900000) continue;
        final productId = req.id ~/ 1000;
        if (productId <= 0) continue; // grup/diger sema disinda kalsin
        if (!validIds.contains(productId)) {
          await _plugin.cancel(req.id);
        }
      }
    } catch (_) {
      // Pending sorgusu basarisiz olursa sessizce gec, bir sonraki
      // acilista tekrar denenir.
    }
  }

  /// Tum bildirimleri iptal eder (APK guncellemesinde temiz baslangic).
  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  /// Bir ürün için eşik günlerinde bildirim planlar.
  /// ÖNCE bu ürüne ait olası TÜM eski alarmları iptal eder (mükerrer
  /// kayıt / tekrar kaydetme durumlarında alarm birikip Android'in
  /// "concurrent alarms" limitine çarpmasını önlemek için). Böylece bu
  /// fonksiyon her zaman güvenle tekrar çağrılabilir (idempotent).
  Future<void> scheduleForProduct(Product product) async {
    if (product.id == null) return;
    await init();
    await cancelForProduct(product.id!);

    for (final threshold in AppConstants.defaultNotifyThresholds) {
      final notifyDate = product.expiryDate.subtract(Duration(days: threshold));
      if (notifyDate.isBefore(DateTime.now())) continue;

      // Saat 09:00'da uyar.
      final scheduled = tz.TZDateTime(
        tz.local,
        notifyDate.year,
        notifyDate.month,
        notifyDate.day,
        9,
      );

      final notifId = _notificationId(product.id!, threshold);

      try {
        await _plugin.zonedSchedule(
          notifId,
          'SKT Yaklaşıyor: ${product.name}',
          '$threshold gün kaldı (${_formatDate(product.expiryDate)})',
          scheduled,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'skt_channel',
              'SKT Uyarıları',
              channelDescription: 'Son kullanma tarihi uyarıları',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        // Android "concurrent alarms" limitine cakilsa bile uygulama
        // CRASH OLMASIN: bu esigi atla, digerlerine devam et. Boylece
        // kullanici en azindan urunu kaydedebilir, sadece bildirim
        // kurulamaz (kritik degil).
      }
    }
  }

  /// Bir ürünün tüm planlanmış bildirimlerini iptal eder.
  /// Sadece güncel eşik listesiyle değil, o ürüne ait GERÇEKTEN bekleyen
  /// (pending) alarmları sorgulayıp hepsini iptal ederek de güvenceye alır.
  /// Böylece eski ayar/sürümlerden kalan "yetim" alarmlar da temizlenir ve
  /// birikip Android'in 500 concurrent-alarm limitine çarpması önlenir.
  Future<void> cancelForProduct(int productId) async {
    if (!_initialized) await init();
    for (final threshold in AppConstants.defaultNotifyThresholds) {
      await _plugin.cancel(_notificationId(productId, threshold));
    }
    // Guvenlik taramasi: bu urune ait baska (eski sema/esik) bekleyen
    // alarm var mi diye gercek pending listesine bak ve onlari da iptal et.
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final prefix = productId * 1000;
      for (final req in pending) {
        // _notificationId semasi: productId * 1000 + threshold (threshold<1000
        // oldugu icin bu aralik sadece bu urune ait olabilir).
        if (req.id >= prefix && req.id < prefix + 1000) {
          await _plugin.cancel(req.id);
        }
      }
    } catch (_) {
      // pending sorgusu basarisizsa yukaridaki sabit-esik temizligi yeterli.
    }
  }

  /// Ürün id + eşik günden benzersiz bildirim id üretir.
  /// Carpan 1000: esik (en fazla ~365) ile cakismaz, urun id'leri ayrik kalir.
  int _notificationId(int productId, int threshold) {
    return productId * 1000 + threshold;
  }

  /// Tum urunler icin gruplama bildirimi planlar (ayni gun bircok urun varsa ozet).
  Future<void> scheduleGroupedSummary(List<Product> products) async {
    if (!_initialized) await init();
    // Her esik gunu icin kac urun var say.
    final Map<DateTime, List<Product>> byDay = {};
    for (final p in products) {
      if (p.id == null) continue;
      for (final threshold in AppConstants.defaultNotifyThresholds) {
        final day = DateTime(
          p.expiryDate.year,
          p.expiryDate.month,
          p.expiryDate.day,
        ).subtract(Duration(days: threshold));
        if (day.isBefore(DateTime.now())) continue;
        byDay.putIfAbsent(day, () => []).add(p);
      }
    }
    // 3'ten fazla urun olan gunlerde grup bildirimi planla.
    for (final entry in byDay.entries) {
      if (entry.value.length < 3) continue;
      final notifyAt = tz.TZDateTime(
          tz.local, entry.key.year, entry.key.month, entry.key.day, 9);
      try {
        await _plugin.zonedSchedule(
          _groupNotifId(entry.key),
          'SKT Uyarısı: ${entry.value.length} ürün',
          '${entry.value.map((p) => p.name.split(' ').first).take(3).join(', ')} ve diğerleri yaklaşıyor',
          notifyAt,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'skt_group_channel',
              'SKT Grup Uyarıları',
              channelDescription: 'Toplu son kullanma tarihi bildirimleri',
              importance: Importance.high,
              priority: Priority.high,
              groupKey: 'skt_group',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        // Limit/izin hatasinda uygulama crash olmasin, sonraki gune devam.
      }
    }
  }

  /// Planlı (bekleyen) bildirimleri döndürür.
  Future<List<PendingNotificationRequest>> getPending() async {
    if (!_initialized) await init();
    return _plugin.pendingNotificationRequests();
  }

  /// Tek bildirimi iptal et.
  Future<void> cancelOne(int id) async {
    if (!_initialized) await init();
    await _plugin.cancel(id);
  }

  int _groupNotifId(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}
