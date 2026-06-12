import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

/// SQLite veritabanı bağlantısını yöneten singleton servis.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Yeni kurulum.
  Future<void> _onCreate(Database db, int version) async {
    await _createProductsTable(db);
    await _createBarcodeTable(db);
    await _createShiftTable(db);
    await _createShelfSessionTable(db);
    await _createMorningLabelTable(db);
    await _createPriceChangeTable(db);
    await _createPriceChangeSessionTable(db);
    await _createWarehouseTables(db);
    await _createTransferTable(db);
  }

  /// v1 -> v2 migration: mevcut veriler korunur.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Disposal sutunlari ekle (varsayilan: active).
      await db.execute(
        "ALTER TABLE ${AppConstants.productTable} ADD COLUMN disposal_status TEXT NOT NULL DEFAULT 'active'",
      );
      await db.execute(
        'ALTER TABLE ${AppConstants.productTable} ADD COLUMN disposal_date INTEGER',
      );
      await db.execute(
        'ALTER TABLE ${AppConstants.productTable} ADD COLUMN disposal_note TEXT',
      );
      // Barkod dizini tablosu olustur.
      await _createBarcodeTable(db);
    }
    if (oldVersion < 3) {
      await _createShiftTable(db);
    }
    if (oldVersion < 4) {
      await _createShelfSessionTable(db);
    }
    if (oldVersion < 5) {
      await _createMorningLabelTable(db);
    }
    if (oldVersion < 6) {
      await _createPriceChangeTable(db);
    }
    if (oldVersion < 7) {
      await _createPriceChangeSessionTable(db);
      // Mevcut kalemlere session_id kolonu ekle (0 = oturumsuz/eski).
      await db.execute(
          'ALTER TABLE ${AppConstants.priceChangeTable} ADD COLUMN session_id INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 8) {
      await _createWarehouseTables(db);
    }
    if (oldVersion < 9) {
      await _createTransferTable(db);
    }
    if (oldVersion < 10) {
      await db.execute(
          'ALTER TABLE ${AppConstants.whPalletTable} ADD COLUMN floor_no INTEGER');
    }
    if (oldVersion < 11) {
      await db.execute(
          'ALTER TABLE ${AppConstants.productTable} ADD COLUMN location TEXT');
    }
  }

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.productTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT,
        expiry_date INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        category TEXT,
        created_at INTEGER NOT NULL,
        disposal_status TEXT NOT NULL DEFAULT 'active',
        disposal_date INTEGER,
        disposal_note TEXT,
        location TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_expiry ON ${AppConstants.productTable} (expiry_date)',
    );
    await db.execute(
      'CREATE INDEX idx_disposal ON ${AppConstants.productTable} (disposal_status)',
    );
  }

  Future<void> _createBarcodeTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.barcodeTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL UNIQUE,
        product_name TEXT NOT NULL,
        imported_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_barcode ON ${AppConstants.barcodeTable} (barcode)',
    );
  }

  Future<void> _createShiftTable(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.shiftTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clock_in INTEGER NOT NULL,
        clock_out INTEGER,
        in_lat REAL,
        in_lng REAL,
        out_lat REAL,
        out_lng REAL,
        photo_in TEXT,
        photo_out TEXT,
        note TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_clockin ON ${AppConstants.shiftTable} (clock_in)',
    );
  }

  Future<void> _createShelfSessionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.shelfSessionTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        scanned_count INTEGER NOT NULL DEFAULT 0,
        match_count INTEGER NOT NULL DEFAULT 0,
        mismatch_count INTEGER NOT NULL DEFAULT 0,
        price_diff_count INTEGER NOT NULL DEFAULT 0,
        no_price_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createMorningLabelTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.morningLabelTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT NOT NULL,
        price REAL,
        label_expiry INTEGER,
        label_print INTEGER,
        scanned_at INTEGER NOT NULL,
        a4_photo TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_morning_barcode ON ${AppConstants.morningLabelTable}(barcode)');
  }

  Future<void> _createPriceChangeTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.priceChangeTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id TEXT NOT NULL,
        session_id INTEGER NOT NULL DEFAULT 0,
        barcode TEXT NOT NULL,
        product_name TEXT,
        new_price REAL,
        old_price REAL,
        aisle TEXT,
        created_at INTEGER NOT NULL,
        changed INTEGER NOT NULL DEFAULT 0,
        changed_at INTEGER,
        photo_path TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pricechange_barcode ON ${AppConstants.priceChangeTable}(barcode)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pricechange_session ON ${AppConstants.priceChangeTable}(session_id)');
  }

  Future<void> _createPriceChangeSessionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.priceChangeSessionTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        a4_count INTEGER NOT NULL DEFAULT 0,
        a4_photos TEXT
      )
    ''');
  }

  Future<void> _createWarehouseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.warehouseTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    // Raf: bir depoya ait, sutun + raf no, palet kapasitesi.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.whShelfTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_id INTEGER NOT NULL,
        column_no INTEGER NOT NULL,
        shelf_no INTEGER NOT NULL,
        capacity INTEGER NOT NULL DEFAULT 1,
        label TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shelf_wh ON ${AppConstants.whShelfTable}(warehouse_id)');
    // Palet: bir rafa ait (shelf_id), kod, durum.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.whPalletTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warehouse_id INTEGER NOT NULL,
        shelf_id INTEGER,
        floor_no INTEGER,
        code TEXT NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pallet_wh ON ${AppConstants.whPalletTable}(warehouse_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pallet_shelf ON ${AppConstants.whPalletTable}(shelf_id)');
    // Palet icindeki urunler: barkod + adet (tekli/karisik palet).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.whPalletItemTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pallet_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        product_name TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pitem_pallet ON ${AppConstants.whPalletItemTable}(pallet_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pitem_barcode ON ${AppConstants.whPalletItemTable}(barcode)');
  }

  Future<void> _createTransferTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.whTransferTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pallet_id INTEGER NOT NULL,
        pallet_code TEXT NOT NULL,
        transfer_type TEXT NOT NULL DEFAULT 'internal',
        -- internal: depo ici raf degisimi
        -- external: magaza/depo disi cikis
        from_warehouse_id INTEGER,
        from_shelf_id INTEGER,
        from_warehouse_name TEXT,
        from_shelf_label TEXT,
        to_warehouse_id INTEGER,
        to_shelf_id INTEGER,
        to_warehouse_name TEXT,
        to_shelf_label TEXT,
        to_external_name TEXT,
        to_external_address TEXT,
        note TEXT,
        created_at INTEGER NOT NULL,
        items_snapshot TEXT NOT NULL
        -- items_snapshot: JSON - transfer anindaki palet icerigi
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transfer_pallet ON ${AppConstants.whTransferTable}(pallet_id)');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
