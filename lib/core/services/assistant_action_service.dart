import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/datasources/barcode_directory_datasource.dart';
import 'database_service.dart';
import 'shelf_layout_service.dart';
import 'app_lock_service.dart';
import 'flow_prefs.dart';
import 'location_reveal_prefs.dart';
import 'notification_service.dart';
import 'price_check_channel.dart';
import 'shelf_restock_service.dart';
import 'teshir_service.dart';
import 'theme_prefs.dart';
import 'warehouse_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  DEPO ASISTANI — EYLEM (ACTION) KATMANI
/// ────────────────────────────────────────────────────────────────────
///  Asistan artik SADECE cevap vermez; sistemde DEGISIKLIK de onerebilir
///  (urun ekle/sil, palet olustur/tasi/sil, depo/reyon olustur, SKT ekle...).
///
///  Guvenlik modeli: asistan bir EYLEM PLANI (JSON) uretir, uygulama bu
///  plani okunur bir ONAY KARTINA cevirir; kullanici ONAYLAYANA kadar
///  HICBIR sey calismaz. Onaydan sonra [execute] gercek servis cagrisini
///  yapar. Her eylem tek tek onaylanir.
///
///  Asistanin urettigi format (cevabin herhangi bir yerinde):
///    ```action
///    {"type":"add_pallet_item","pallet_code":"P123","barcode":"869...",
///     "name":"Cikolata","quantity":6}
///    ```
///  Birden fazla eylem icin birden fazla ```action blogu olabilir.
/// ════════════════════════════════════════════════════════════════════

enum AssistantActionType {
  addPalletItem,
  removePalletItem,
  createPallet,
  deletePallet,
  movePallet,
  createWarehouse,
  createShelfUnit,
  deleteShelfUnit,
  addSktProduct,
  // ── UYGULAMA KONTROLU (v145) ──
  setTheme,
  setAppLock,
  changePin,
  setBiometric,
  setLocationReveal,
  setCompanyFlow,
  addTeshir,
  removeTeshir,
  addRestock,
  clearNotifications,
  // ── GENEL AMACLI (agent) ──
  dbWrite,
  prefsSet,
  unknown,
}

class AssistantAction {
  final AssistantActionType type;
  final Map<String, dynamic> args;
  const AssistantAction(this.type, this.args);

  /// Onay kartinda gosterilecek insan-okur baslik.
  String get title {
    switch (type) {
      case AssistantActionType.addPalletItem:
        return 'Palete ürün ekle';
      case AssistantActionType.removePalletItem:
        return 'Paletten ürün çıkar';
      case AssistantActionType.createPallet:
        return 'Yeni palet oluştur';
      case AssistantActionType.deletePallet:
        return 'Paleti sil';
      case AssistantActionType.movePallet:
        return 'Paleti taşı';
      case AssistantActionType.createWarehouse:
        return 'Yeni depo oluştur';
      case AssistantActionType.createShelfUnit:
        return 'Yeni reyon oluştur';
      case AssistantActionType.deleteShelfUnit:
        return 'Reyonu sil';
      case AssistantActionType.addSktProduct:
        return 'SKT takibine ürün ekle';
      case AssistantActionType.setTheme:
        return 'Tema ayarını değiştir';
      case AssistantActionType.setAppLock:
        return args['enabled'] == false
            ? 'Uygulama kilidini KAPAT'
            : 'Uygulama kilidini AÇ';
      case AssistantActionType.changePin:
        return 'Uygulama şifresini değiştir';
      case AssistantActionType.setBiometric:
        return args['enabled'] == false
            ? 'Parmak izi girişini kapat'
            : 'Parmak izi girişini aç';
      case AssistantActionType.setLocationReveal:
        return 'Konum canlandırması ayarı';
      case AssistantActionType.setCompanyFlow:
        return 'Şirket uygulaması entegrasyonu';
      case AssistantActionType.addTeshir:
        return 'Teşhire ürün ekle';
      case AssistantActionType.removeTeshir:
        return 'Teşhirden ürün çıkar';
      case AssistantActionType.addRestock:
        return 'Reyona açılacaklara ekle';
      case AssistantActionType.clearNotifications:
        return 'Tüm bildirimleri iptal et';
      case AssistantActionType.dbWrite:
        return args['title']?.toString().trim().isNotEmpty == true
            ? args['title'].toString()
            : 'Veritabanında değişiklik';
      case AssistantActionType.prefsSet:
        return 'Uygulama ayarını değiştir';
      case AssistantActionType.unknown:
        return 'Bilinmeyen işlem';
    }
  }

  /// Onay kartinda gosterilecek detay satirlari (etiket, deger).
  List<({String label, String value})> get details {
    String s(String k) => (args[k]?.toString() ?? '—');
    switch (type) {
      case AssistantActionType.addPalletItem:
        return [
          (label: 'Palet', value: s('pallet_code')),
          (label: 'Ürün', value: s('name')),
          (label: 'Barkod', value: s('barcode')),
          (label: 'Adet', value: s('quantity')),
          if (args['expiry'] != null)
            (label: 'SKT', value: s('expiry')),
        ];
      case AssistantActionType.removePalletItem:
        return [
          (label: 'Palet', value: s('pallet_code')),
          (label: 'Ürün/Barkod', value: s('barcode')),
          (label: 'Adet', value: s('quantity')),
        ];
      case AssistantActionType.createPallet:
        return [
          (label: 'Depo', value: s('warehouse_name')),
          (label: 'Palet kodu', value: s('code')),
          (
            label: 'Konum',
            value: args['floor'] == true ? 'Zemin' : 'Bekleme'
          ),
        ];
      case AssistantActionType.deletePallet:
        return [(label: 'Palet', value: s('pallet_code'))];
      case AssistantActionType.movePallet:
        return [
          (label: 'Palet', value: s('pallet_code')),
          (
            label: 'Hedef',
            value: args['to_floor'] == true
                ? 'Zemin'
                : args['to_waiting'] == true
                    ? 'Bekleme alanı'
                    : 'Sütun ${s('column')} · Raf ${s('row')}'
          ),
        ];
      case AssistantActionType.createWarehouse:
        return [(label: 'Depo adı', value: s('name'))];
      case AssistantActionType.createShelfUnit:
        return [
          (label: 'Reyon adı', value: s('name')),
          (label: 'Sütun sayısı', value: s('sections')),
        ];
      case AssistantActionType.deleteShelfUnit:
        return [(label: 'Reyon', value: s('name'))];
      case AssistantActionType.addSktProduct:
        return [
          (label: 'Ürün', value: s('name')),
          (label: 'Barkod', value: s('barcode')),
          (label: 'SKT', value: s('expiry')),
          (label: 'Adet', value: s('quantity')),
        ];
      case AssistantActionType.setTheme:
        return [
          (
            label: 'Tema',
            value: switch (s('mode')) {
              'dark' => 'Koyu',
              'light' => 'Açık',
              'system' => 'Sistem',
              _ => s('mode'),
            }
          )
        ];
      case AssistantActionType.setAppLock:
        return [
          (label: 'Kilit', value: args['enabled'] == false ? 'Kapalı' : 'Açık')
        ];
      case AssistantActionType.changePin:
        return [
          (label: 'Yeni şifre', value: '••••'),
          (label: 'Uyarı', value: 'Onaylarsan şifre hemen değişir'),
        ];
      case AssistantActionType.setBiometric:
        return [
          (
            label: 'Parmak izi',
            value: args['enabled'] == false ? 'Kapalı' : 'Açık'
          )
        ];
      case AssistantActionType.setLocationReveal:
        return [
          (
            label: 'Canlandırma',
            value: args['enabled'] == false ? 'Kapalı' : 'Açık'
          )
        ];
      case AssistantActionType.setCompanyFlow:
        return [
          (
            label: 'Otomatik geçiş',
            value: args['enabled'] == false ? 'Kapalı' : 'Açık'
          )
        ];
      case AssistantActionType.addTeshir:
        return [
          (label: 'Ürün', value: s('name')),
          (label: 'Barkod', value: s('barcode')),
          if (args['note'] != null) (label: 'Teşhir yeri', value: s('note')),
        ];
      case AssistantActionType.removeTeshir:
        return [(label: 'Barkod', value: s('barcode'))];
      case AssistantActionType.addRestock:
        return [
          (label: 'Ürün', value: s('name')),
          (label: 'Barkod', value: s('barcode')),
          (label: 'Adet', value: s('quantity')),
        ];
      case AssistantActionType.clearNotifications:
        return [(label: 'Kapsam', value: 'Bekleyen tüm SKT bildirimleri')];
      case AssistantActionType.dbWrite:
        return [
          if (args['description'] != null)
            (label: 'Ne yapacak', value: s('description')),
          (label: 'SQL', value: s('sql')),
        ];
      case AssistantActionType.prefsSet:
        return [
          (label: 'Ayar', value: s('key')),
          (label: 'Yeni değer', value: s('value')),
        ];
      case AssistantActionType.unknown:
        return [(label: 'Ham veri', value: jsonEncode(args))];
    }
  }

  bool get isDestructive =>
      type == AssistantActionType.deletePallet ||
      type == AssistantActionType.deleteShelfUnit ||
      type == AssistantActionType.removePalletItem ||
      // Guvenlik ayarlari: geri alinamaz/riskli sayilir, kirmizi onay ister.
      type == AssistantActionType.changePin ||
      type == AssistantActionType.clearNotifications ||
      (type == AssistantActionType.setAppLock && args['enabled'] == false) ||
      // Ham SQL: her zaman dikkatli onay istenir.
      type == AssistantActionType.dbWrite;
}

class AssistantActionService {
  AssistantActionService._();
  static final AssistantActionService instance = AssistantActionService._();

  static const int _defaultWarehouseFallback = 1;

  /// Asistan cevabindaki ```action ... ``` bloklarini ayikla + parse et.
  /// Bloklar cevaptan SILINIR; geriye kalan duz metin sohbette gosterilir.
  ({String cleanText, List<AssistantAction> actions}) parse(String reply) {
    final actions = <AssistantAction>[];
    final re = RegExp(r'```action\s*([\s\S]*?)```', multiLine: true);
    final clean = reply.replaceAllMapped(re, (m) {
      final raw = (m.group(1) ?? '').trim();
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) actions.add(_fromMap(e));
          }
        } else if (decoded is Map<String, dynamic>) {
          actions.add(_fromMap(decoded));
        }
      } catch (_) {
        // Bozuk JSON -> yok say (metinden yine de silinir).
      }
      return '';
    }).trim();
    return (cleanText: clean, actions: actions);
  }

  AssistantAction _fromMap(Map<String, dynamic> m) {
    final t = (m['type'] ?? '').toString().trim();
    final type = switch (t) {
      'add_pallet_item' => AssistantActionType.addPalletItem,
      'remove_pallet_item' => AssistantActionType.removePalletItem,
      'create_pallet' => AssistantActionType.createPallet,
      'delete_pallet' => AssistantActionType.deletePallet,
      'move_pallet' => AssistantActionType.movePallet,
      'create_warehouse' => AssistantActionType.createWarehouse,
      'create_shelf_unit' => AssistantActionType.createShelfUnit,
      'delete_shelf_unit' => AssistantActionType.deleteShelfUnit,
      'add_skt_product' => AssistantActionType.addSktProduct,
      'set_theme' => AssistantActionType.setTheme,
      'set_app_lock' => AssistantActionType.setAppLock,
      'change_pin' => AssistantActionType.changePin,
      'set_biometric' => AssistantActionType.setBiometric,
      'set_location_reveal' => AssistantActionType.setLocationReveal,
      'set_company_flow' => AssistantActionType.setCompanyFlow,
      'add_teshir' => AssistantActionType.addTeshir,
      'remove_teshir' => AssistantActionType.removeTeshir,
      'add_restock' => AssistantActionType.addRestock,
      'clear_notifications' => AssistantActionType.clearNotifications,
      'db_write' => AssistantActionType.dbWrite,
      'prefs_set' => AssistantActionType.prefsSet,
      _ => AssistantActionType.unknown,
    };
    return AssistantAction(type, m);
  }

  // ── LOOKUP YARDIMCILARI ───────────────────────────────────────────
  Future<int?> _warehouseIdByName(String? name) async {
    final all = await WarehouseService.instance.getWarehouses();
    if (all.isEmpty) return null;
    if (name == null || name.trim().isEmpty) return all.first.id;
    final n = name.trim().toLowerCase();
    for (final w in all) {
      if (w.name.toLowerCase() == n) return w.id;
    }
    for (final w in all) {
      if (w.name.toLowerCase().contains(n)) return w.id;
    }
    return all.first.id;
  }

  /// Palet kodundan (tum depolarda) paleti bulur.
  Future<WhPallet?> _palletByCode(String? code) async {
    if (code == null || code.trim().isEmpty) return null;
    final c = code.trim().toLowerCase();
    final all = await WarehouseService.instance.getWarehouses();
    for (final w in all) {
      final pallets =
          await WarehouseService.instance.getAllPallets(w.id!);
      for (final ps in pallets) {
        if (ps.pallet.code.toLowerCase() == c) return ps.pallet;
      }
    }
    return null;
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final p = s.trim().split(RegExp(r'[./\-]'));
      if (p.length == 3) {
        // gg.aa.yyyy ya da yyyy-aa-gg destekle.
        if (p[0].length == 4) {
          return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        }
        final y = int.parse(p[2].length == 2 ? '20${p[2]}' : p[2]);
        return DateTime(y, int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    return null;
  }

  /// Eylemi GERCEKTEN calistirir (onaydan SONRA cagirilir).
  /// Basari/hata mesaji doner (sohbette gosterilir).
  Future<String> execute(AssistantAction a) async {
    try {
      switch (a.type) {
        case AssistantActionType.addPalletItem:
          {
            final pallet = await _palletByCode(a.args['pallet_code']?.toString());
            if (pallet == null) {
              return '❌ "${a.args['pallet_code']}" kodlu palet bulunamadı.';
            }
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            if (barcode.isEmpty) return '❌ Barkod gerekli.';
            final qty = _int(a.args['quantity'], 1);
            final itemId = await WarehouseService.instance.addItemToPallet(
              palletId: pallet.id!,
              barcode: barcode,
              quantity: qty,
              productName: a.args['name']?.toString(),
            );
            final exp = _parseDate(a.args['expiry']?.toString());
            if (exp != null) {
              final db = await DatabaseService.instance.database;
              await db.insert('products', {
                'name': a.args['name']?.toString() ?? barcode,
                'barcode': barcode,
                'expiry_date': exp.millisecondsSinceEpoch,
                'quantity': qty,
                'created_at': DateTime.now().millisecondsSinceEpoch,
                'disposal_status': 'active',
                'location_type': 'pallet',
                'location_ref': itemId,
              });
            }
            return '✅ ${pallet.code} paletine $qty adet eklendi.';
          }

        case AssistantActionType.removePalletItem:
          {
            final pallet = await _palletByCode(a.args['pallet_code']?.toString());
            if (pallet == null) {
              return '❌ "${a.args['pallet_code']}" kodlu palet bulunamadı.';
            }
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            final items =
                await WarehouseService.instance.getPalletItems(pallet.id!);
            final match = items
                .where((e) =>
                    e.barcode == barcode ||
                    (e.productName?.toLowerCase() ==
                        barcode.toLowerCase()))
                .toList();
            if (match.isEmpty) {
              return '❌ Bu palette "$barcode" bulunamadı.';
            }
            final qty = _int(a.args['quantity'], match.first.quantity);
            await WarehouseService.instance
                .removeItemQuantity(match.first.id!, qty);
            return '✅ ${pallet.code} paletinden $qty adet çıkarıldı.';
          }

        case AssistantActionType.createPallet:
          {
            final wid = await _warehouseIdByName(
                    a.args['warehouse_name']?.toString()) ??
                _defaultWarehouseFallback;
            final floor = a.args['floor'] == true;
            final id = await WarehouseService.instance.createPallet(
              warehouseId: wid,
              floorNo: floor ? 0 : null,
              code: (a.args['code'] ?? 'Palet').toString().trim(),
            );
            if (id == -1) return '❌ Palet oluşturulamadı (raf dolu).';
            return '✅ "${a.args['code']}" paleti oluşturuldu.';
          }

        case AssistantActionType.deletePallet:
          {
            final pallet = await _palletByCode(a.args['pallet_code']?.toString());
            if (pallet == null) {
              return '❌ "${a.args['pallet_code']}" kodlu palet bulunamadı.';
            }
            await WarehouseService.instance.deletePallet(pallet.id!);
            return '✅ ${pallet.code} paleti silindi.';
          }

        case AssistantActionType.movePallet:
          {
            final pallet = await _palletByCode(a.args['pallet_code']?.toString());
            if (pallet == null) {
              return '❌ "${a.args['pallet_code']}" kodlu palet bulunamadı.';
            }
            int? targetShelfId;
            if (a.args['to_waiting'] != true && a.args['to_floor'] != true) {
              final col = _intN(a.args['column']);
              final row = _intN(a.args['row']);
              if (col != null && row != null) {
                final shelves = await WarehouseService.instance
                    .getShelves(pallet.warehouseId);
                final s = shelves
                    .where((e) => e.columnNo == col && e.shelfNo == row)
                    .toList();
                if (s.isEmpty) {
                  return '❌ Sütun $col · Raf $row bulunamadı.';
                }
                targetShelfId = s.first.id;
              }
            }
            final ok = await WarehouseService.instance
                .movePallet(pallet.id!, targetShelfId);
            return ok
                ? '✅ ${pallet.code} taşındı.'
                : '❌ Hedef raf dolu, taşınamadı.';
          }

        case AssistantActionType.createWarehouse:
          {
            final name = (a.args['name'] ?? '').toString().trim();
            if (name.isEmpty) return '❌ Depo adı gerekli.';
            await WarehouseService.instance.createWarehouse(name);
            return '✅ "$name" deposu oluşturuldu.';
          }

        case AssistantActionType.createShelfUnit:
          {
            final name = (a.args['name'] ?? 'Reyon').toString().trim();
            final sections = _int(a.args['sections'], 4);
            await ShelfLayoutService.instance
                .createUnit(name: name, sections: sections);
            return '✅ "$name" reyonu ($sections sütun) oluşturuldu.';
          }

        case AssistantActionType.deleteShelfUnit:
          {
            final name = (a.args['name'] ?? '').toString().trim().toLowerCase();
            final units =
                await ShelfLayoutService.instance.getUnitSummaries();
            final match = units
                .where((u) => u.unit.name.toLowerCase() == name)
                .toList();
            if (match.isEmpty) {
              return '❌ "${a.args['name']}" adlı reyon bulunamadı.';
            }
            await ShelfLayoutService.instance.deleteUnit(match.first.unit.id!);
            return '✅ "${match.first.unit.name}" reyonu silindi.';
          }

        case AssistantActionType.addSktProduct:
          {
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            final exp = _parseDate(a.args['expiry']?.toString());
            if (exp == null) return '❌ Geçerli SKT gerekli (gg.aa.yyyy).';
            final qty = _int(a.args['quantity'], 1);
            final db = await DatabaseService.instance.database;
            await db.insert('products', {
              'name': a.args['name']?.toString() ??
                  (barcode.isEmpty ? 'Ürün' : barcode),
              'barcode': barcode.isEmpty ? null : barcode,
              'expiry_date': exp.millisecondsSinceEpoch,
              'quantity': qty,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'disposal_status': 'active',
            });
            return '✅ SKT takibine eklendi.';
          }

        // ── UYGULAMA KONTROLU (v145) ──────────────────────────────
        case AssistantActionType.setTheme:
          {
            final m = (a.args['mode'] ?? '').toString().trim().toLowerCase();
            final mode = switch (m) {
              'dark' || 'koyu' || 'karanlik' || 'karanlık' => ThemeMode.dark,
              'light' || 'acik' || 'açık' || 'aydinlik' => ThemeMode.light,
              'system' || 'sistem' || 'otomatik' => ThemeMode.system,
              _ => null,
            };
            if (mode == null) return '❌ Geçersiz tema: "$m".';
            await ThemePrefs.instance.setMode(mode);
            final label = switch (mode) {
              ThemeMode.dark => 'Koyu',
              ThemeMode.light => 'Açık',
              ThemeMode.system => 'Sistem',
            };
            return '✅ Tema "$label" olarak ayarlandı.';
          }

        case AssistantActionType.setAppLock:
          {
            final enable = a.args['enabled'] != false;
            if (enable) {
              final has = await AppLockService.instance.hasPin();
              if (!has) {
                return '❌ Önce bir şifre belirlemelisin. '
                    '"Şifremi 1234 yap" diyebilirsin.';
              }
            }
            await AppLockService.instance.setLockEnabled(enable);
            return enable
                ? '✅ Uygulama kilidi açıldı.'
                : '✅ Uygulama kilidi kapatıldı.';
          }

        case AssistantActionType.changePin:
          {
            final pin = (a.args['pin'] ?? '').toString().trim();
            if (pin.length < 4 || pin.length > 8 ||
                int.tryParse(pin) == null) {
              return '❌ Şifre 4-8 haneli rakam olmalı.';
            }
            await AppLockService.instance.setPin(pin);
            await AppLockService.instance.setLockEnabled(true);
            return '✅ Uygulama şifresi değiştirildi ve kilit açık.';
          }

        case AssistantActionType.setBiometric:
          {
            final enable = a.args['enabled'] != false;
            if (enable) {
              final ok =
                  await AppLockService.instance.isBiometricAvailable();
              if (!ok) return '❌ Bu cihazda parmak izi kullanılamıyor.';
            }
            await AppLockService.instance.setBiometricEnabled(enable);
            return enable
                ? '✅ Parmak izi girişi açıldı.'
                : '✅ Parmak izi girişi kapatıldı.';
          }

        case AssistantActionType.setLocationReveal:
          {
            final enable = a.args['enabled'] != false;
            await LocationRevealPrefs.instance.setEnabled(enable);
            return enable
                ? '✅ Konum canlandırması açıldı.'
                : '✅ Konum canlandırması kapatıldı.';
          }

        case AssistantActionType.setCompanyFlow:
          {
            final enable = a.args['enabled'] != false;
            await FlowPrefs.instance.setAutoFlow(enable);
            try {
              await PriceCheckChannel.setAutoFlow(enable);
            } catch (_) {}
            return enable
                ? '✅ Şirket uygulaması entegrasyonu açıldı.'
                : '✅ Şirket uygulaması entegrasyonu kapatıldı.';
          }

        case AssistantActionType.addTeshir:
          {
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            if (barcode.isEmpty) return '❌ Barkod gerekli.';
            await TeshirService.instance.add(
              barcode,
              productName: a.args['name']?.toString(),
              note: a.args['note']?.toString(),
            );
            return '✅ Teşhir listesine eklendi.';
          }

        case AssistantActionType.removeTeshir:
          {
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            final row = await TeshirService.instance.find(barcode);
            if (row == null) return '❌ Bu ürün teşhir listesinde yok.';
            await TeshirService.instance.remove(row['id'] as int);
            return '✅ Teşhirden çıkarıldı.';
          }

        case AssistantActionType.addRestock:
          {
            final barcode = (a.args['barcode'] ?? '').toString().trim();
            if (barcode.isEmpty) return '❌ Barkod gerekli.';
            await ShelfRestockService.instance.add(
              barcode,
              productName: a.args['name']?.toString(),
              qty: _int(a.args['quantity'], 1),
            );
            return '✅ Reyona açılacaklar listesine eklendi.';
          }

        case AssistantActionType.clearNotifications:
          {
            await NotificationService.instance.cancelAll();
            return '✅ Bekleyen tüm bildirimler iptal edildi.';
          }

        // ── GENEL AMACLI: ham SQL yazma (agent'in sinirsiz eli) ──
        case AssistantActionType.dbWrite:
          {
            final sql = (a.args['sql'] ?? '').toString().trim()
                .replaceAll(RegExp(r';\s*$'), '');
            if (sql.isEmpty) return '❌ sql alanı boş.';
            if (sql.contains(';')) {
              return '❌ Tek bir SQL ifadesi gönder (";" kullanma).';
            }
            final head = sql.toLowerCase().trimLeft();
            if (head.startsWith('select') || head.startsWith('pragma')) {
              return '❌ Okuma için db_query aracını kullan.';
            }
            final db = await DatabaseService.instance.database;
            if (head.startsWith('insert')) {
              final id = await db.rawInsert(sql);
              return '✅ Eklendi (id: $id).';
            } else if (head.startsWith('update')) {
              final n = await db.rawUpdate(sql);
              return '✅ $n kayıt güncellendi.';
            } else if (head.startsWith('delete')) {
              final n = await db.rawDelete(sql);
              return '✅ $n kayıt silindi.';
            } else {
              await db.execute(sql);
              return '✅ Uygulandı.';
            }
          }

        // ── GENEL AMACLI: herhangi bir uygulama ayarini yaz ──
        case AssistantActionType.prefsSet:
          {
            final key = (a.args['key'] ?? '').toString().trim();
            if (key.isEmpty) return '❌ key gerekli.';
            final lower = key.toLowerCase();
            if (lower.contains('pin') ||
                lower.contains('password') ||
                lower.contains('api_key') ||
                lower.contains('apikey') ||
                lower.contains('token')) {
              return '❌ Güvenlik anahtarları böyle değiştirilemez; '
                  'şifre için change_pin eylemini kullan.';
            }
            // Uygulama ayarlari FlutterSecureStorage'ta METIN olarak durur.
            final v = a.args['value']?.toString() ?? '';
            const storage = FlutterSecureStorage();
            await storage.write(key: key, value: v);
            return '✅ "$key" ayarı güncellendi. '
                '(Bazı ayarlar uygulama yeniden açılınca etkinleşir.)';
          }

        case AssistantActionType.unknown:
          return '❌ Bu işlem türü desteklenmiyor.';
      }
    } catch (e) {
      return '❌ İşlem başarısız: $e';
    }
  }

  int _int(Object? v, int fallback) =>
      v is int ? v : (int.tryParse(v?.toString() ?? '') ?? fallback);
  int? _intN(Object? v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '');
}
