import 'package:flutter/material.dart';

/// Uygulama genelinde kullanilan sabitler.
class AppConstants {
  AppConstants._();

  static const String appName = 'SKT Takip';
  static const String dbName = 'skt_takip.db';
  static const int dbVersion = 4; // v4: shelf_sessions tablosu
  static const String productTable = 'products';
  static const String barcodeTable = 'barcode_directory';
  static const String shiftTable = 'shifts';
  static const String shelfSessionTable = 'shelf_sessions';

  static const List<int> defaultNotifyThresholds = [30, 15, 7, 3, 1];
  static const int warningDays = 7;
  static const int criticalDays = 3;

  /// Imha/iade gecmisi kac gun tutulsun.
  static const int disposalHistoryDays = 90;
}

enum ExpiryStatus {
  expired,
  critical,
  warning,
  safe;

  String get label {
    switch (this) {
      case ExpiryStatus.expired:  return 'Süresi Doldu';
      case ExpiryStatus.critical: return 'Kritik';
      case ExpiryStatus.warning:  return 'Yaklaşıyor';
      case ExpiryStatus.safe:     return 'Güvenli';
    }
  }

  Color get color {
    switch (this) {
      case ExpiryStatus.expired:  return const Color(0xFFF43F5E);
      case ExpiryStatus.critical: return const Color(0xFFFB923C);
      case ExpiryStatus.warning:  return const Color(0xFFFBBF24);
      case ExpiryStatus.safe:     return const Color(0xFF34D399);
    }
  }
}
