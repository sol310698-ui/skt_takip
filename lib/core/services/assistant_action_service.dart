import 'dart:convert';

import '../../data/datasources/barcode_directory_datasource.dart';
import 'database_service.dart';
import 'shelf_layout_service.dart';
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
      case AssistantActionType.unknown:
        return [(label: 'Ham veri', value: jsonEncode(args))];
    }
  }

  bool get isDestructive =>
      type == AssistantActionType.deletePallet ||
      type == AssistantActionType.deleteShelfUnit ||
      type == AssistantActionType.removePalletItem;
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
