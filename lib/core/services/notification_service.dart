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

  Future<void> init() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();

      const androidSettings =
          AndroidInitializationSettings('@drawable/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(initSettings);

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      _initialized = false;
    }
  }

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

  /// Tum bildirimleri iptal eder (APK guncellemesinde temiz baslangic).
  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }

  /// Bir ürün için eşik günlerinde bildirim planlar.
  Future<void> scheduleForProduct(Product product) async {
    if (product.id == null) return;
    await init();

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
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Bir ürünün tüm planlanmış bildirimlerini iptal eder.
  Future<void> cancelForProduct(int productId) async {
    for (final threshold in AppConstants.defaultNotifyThresholds) {
      await _plugin.cancel(_notificationId(productId, threshold));
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
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  int _groupNotifId(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}
