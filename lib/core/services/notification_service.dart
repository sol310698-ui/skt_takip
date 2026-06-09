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

      // Android 13+ bildirim izni.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _initialized = true;
    } catch (e) {
      // Bildirim baslatma basarisiz olsa bile uygulama acilmali.
      _initialized = false;
    }
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
  int _notificationId(int productId, int threshold) {
    return productId * 100 + threshold;
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}
