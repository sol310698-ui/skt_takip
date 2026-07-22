import 'package:flutter/material.dart';

/// Uygulama genelinde kullanilan sabitler.
class AppConstants {
  AppConstants._();

  static const String appName = 'SKT Takip';
  static const String dbName = 'skt_takip.db';
  static const int dbVersion = 29; // v26: reyon dizilim + urun yerel fotografi
  // Reyon dizilim (planogram): bir reyon = bolum(sutun) x satir(kat) izgarasi.
  static const String shelfUnitTable = 'shelf_units';   // reyon tanimi
  static const String restockTable = 'shelf_restock_items'; // reyona acilacaklar
  static const String teshirTable = 'teshir_items';         // teshirdeki urunler
  static const String shelfSlotTable = 'shelf_slots';   // reyondaki tek urun (foto)
  static const String countTable = 'count_items'; // bagimsiz sayim oturumu
  static const String labelDeletedTable = 'label_deleted'; // silinen etiketler
  static const String productTable = 'products';
  static const String barcodeTable = 'barcode_directory';
  static const String shiftTable = 'shifts';
  static const String shelfSessionTable = 'shelf_sessions';
  static const String morningLabelTable = 'morning_labels';
  static const String priceChangeTable = 'price_change_items';
  static const String priceChangeSessionTable = 'price_change_sessions';
  static const String warehouseTable = 'warehouses';
  static const String whShelfTable = 'wh_shelves';
  static const String whPalletTable = 'wh_pallets';
  static const String whPalletItemTable = 'wh_pallet_items';
  static const String whTransferTable = 'wh_transfers'; // depo-ici + disari
  static const String workScheduleTable = 'work_schedule'; // haftalik program
  static const String checklistTable = 'checklists'; // kontrol listesi oturumlari
  static const String checklistItemTable = 'checklist_items'; // liste maddeleri
  static const String labelHistoryTable = 'label_history'; // etiket basim gecmisi
  static const String labelPendingQueueTable = 'label_pending_queue'; // baska ekrandan gelen bekleyen etiketler
  static const String labelActiveListsTable = 'label_active_lists'; // etiket basim aktif listeleri (kalici)
  static const String controlListTable = 'control_list'; // yonetici kontrol listesi (Excel/foto ile yuklenir)

  static const List<int> defaultNotifyThresholds = [30, 15, 7, 3, 1];
  static const int warningDays = 7;
  static const int criticalDays = 3;

  /// Imha/iade gecmisi kac gun tutulsun.
  static const int disposalHistoryDays = 90;

  /// Etiket basim gecmisi kac gun tutulsun.
  static const int labelHistoryDays = 30;
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
