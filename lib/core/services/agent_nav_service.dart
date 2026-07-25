import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../../views/screens/barcode_list_screen.dart';
import '../../views/screens/checklist_screen.dart';
import '../../views/screens/control_list_screen.dart';
import '../../views/screens/count_screen.dart';
import '../../views/screens/history_screen.dart';
import '../../views/screens/import_screen.dart';
import '../../views/screens/label_print_screen.dart';
import '../../views/screens/log_viewer_screen.dart';
import '../../views/screens/pending_products_screen.dart';
import '../../views/screens/price_change_screen.dart';
import '../../views/screens/price_check_screen.dart';
import '../../views/screens/settings_screen.dart';
import '../../views/screens/shift_screen.dart';
import '../../views/screens/shelf_layout_list_screen.dart';
import '../../views/screens/shelf_restock_screen.dart';
import '../../views/screens/teshir_screen.dart';
import '../../views/screens/warehouse_chat_screen.dart';
import '../../views/screens/warehouse_list_screen.dart';
import '../../views/screens/waybill_archive_screen.dart';
import '../../views/screens/work_schedule_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  AGENT GEZINME SERVISI (v159)
/// ────────────────────────────────────────────────────────────────────
///  "Benim yerime dokun" isteginin uygulama ICINDEKI karsiligi: asistan
///  ekranlari SENIN YERINE acar. Sahte dokunus (koordinat tikllama)
///  yerine dogrudan yonlendirme kullanilir — daha hizli ve saglam.
///
///  Ekranlar burada TEK YERDE kayitli; asistan bu anahtarlari kullanir.
/// ════════════════════════════════════════════════════════════════════
class AgentNavService {
  AgentNavService._();
  static final AgentNavService instance = AgentNavService._();

  /// anahtar -> (gorunen ad, ekrani uret)
  static final Map<String, ({String title, Widget Function() build})> _routes =
      {
    'etiket_basim': (
      title: 'Etiket Basım',
      build: () => const LabelPrintScreen(),
    ),
    'fiyat_degisim': (
      title: 'Fiyat Değişim',
      build: () => const PriceChangeScreen(),
    ),
    'fiyat_kontrol': (
      title: 'Fiyat Kontrol (Sesli)',
      build: () => const PriceCheckScreen(),
    ),
    'depo': (
      title: 'Depo',
      build: () => const WarehouseListScreen(),
    ),
    'reyon': (
      title: 'Reyon Dizilimi',
      build: () => const ShelfLayoutListScreen(),
    ),
    'teshir': (
      title: 'Teşhir',
      build: () => const TeshirScreen(),
    ),
    'reyona_acilacaklar': (
      title: 'Reyona Açılacaklar',
      build: () => const ShelfRestockScreen(),
    ),
    'barkod_listesi': (
      title: 'Barkod Listesi',
      build: () => const BarcodeListScreen(),
    ),
    'irsaliye_arsivi': (
      title: 'Transfer İrsaliyeleri',
      build: () => const WaybillArchiveScreen(),
    ),
    'alarmlar': (
      title: 'Çalışma Programı (Alarmlar)',
      build: () => const WorkScheduleScreen(),
    ),
    'sayim': (
      title: 'Sayım',
      build: () => const CountScreen(),
    ),
    'vardiya': (
      title: 'Vardiya',
      build: () => const ShiftScreen(),
    ),
    'kontrol_listesi': (
      title: 'Kontrol Listesi',
      build: () => const ControlListScreen(),
    ),
    'gorevler': (
      title: 'Kontrol Görevleri',
      build: () => const ChecklistScreen(),
    ),
    'bekleyen_urunler': (
      title: 'Bekleyen Ürünler',
      build: () => const PendingProductsScreen(),
    ),
    'gecmis': (
      title: 'Geçmiş / İmha Kayıtları',
      build: () => const HistoryScreen(),
    ),
    'ice_aktar': (
      title: 'İçe Aktar',
      build: () => const ImportScreen(),
    ),
    'gunluk': (
      title: 'Uygulama Günlüğü',
      build: () => const LogViewerScreen(),
    ),
    'asistan': (
      title: 'Depo Asistanı',
      build: () => const WarehouseChatScreen(),
    ),
    'ayarlar': (
      title: 'Ayarlar',
      build: () => const SettingsScreen(),
    ),
  };

  /// Asistanin prompt'unda listelenecek anahtarlar.
  static String get keyList =>
      _routes.entries.map((e) => '${e.key} (${e.value.title})').join(', ');

  static bool exists(String key) => _routes.containsKey(_norm(key));

  static String? titleOf(String key) => _routes[_norm(key)]?.title;

  /// Anahtari esnek cozer: buyuk/kucuk harf, bosluk/tire farketmez;
  /// tam eslesme yoksa ICEREN anahtar aranir ("etiket" -> etiket_basim).
  static String _norm(String raw) {
    final t = raw
        .trim()
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    if (_routes.containsKey(t)) return t;
    for (final k in _routes.keys) {
      if (k.contains(t) || t.contains(k)) return k;
    }
    return t;
  }

  /// Ekrani ac. Basarisizsa false doner (asistan kullaniciya bildirir).
  Future<bool> open(String key) async {
    final k = _norm(key);
    final route = _routes[k];
    final nav = navigatorKey.currentState;
    if (route == null || nav == null) return false;
    await nav.push(MaterialPageRoute(builder: (_) => route.build()));
    return true;
  }
}
