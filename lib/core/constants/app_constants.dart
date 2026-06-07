import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılan sabitler.
class AppConstants {
  AppConstants._();

  static const String appName = 'SKT Takip';
  static const String dbName = 'skt_takip.db';
  static const int dbVersion = 1;
  static const String productTable = 'products';

  /// Varsayılan bildirim eşik günleri (SKT'den kaç gün önce uyarı).
  static const List<int> defaultNotifyThresholds = [30, 15, 7, 3, 1];

  /// "Yaklaşıyor" kabul edilen gün eşiği.
  static const int warningDays = 7;

  /// "Kritik" kabul edilen gün eşiği.
  static const int criticalDays = 3;
}

/// Bir ürünün son kullanma tarihine göre durumu.
enum ExpiryStatus {
  expired, // Süresi geçmiş
  critical, // Kritik (<= criticalDays)
  warning, // Yaklaşıyor (<= warningDays)
  safe; // Güvenli

  String get label {
    switch (this) {
      case ExpiryStatus.expired:
        return 'Süresi Doldu';
      case ExpiryStatus.critical:
        return 'Kritik';
      case ExpiryStatus.warning:
        return 'Yaklaşıyor';
      case ExpiryStatus.safe:
        return 'Güvenli';
    }
  }

  Color get color {
    switch (this) {
      case ExpiryStatus.expired:
        return const Color(0xFFD32F2F);
      case ExpiryStatus.critical:
        return const Color(0xFFF57C00);
      case ExpiryStatus.warning:
        return const Color(0xFFFBC02D);
      case ExpiryStatus.safe:
        return const Color(0xFF388E3C);
    }
  }
}
