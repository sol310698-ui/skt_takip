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
        disposal_note TEXT
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
    await db.execute('''\n      CREATE TABLE IF NOT EXISTS ${AppConstants.shelfSessionTable} (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        started_at INTEGER NOT NULL,\n        ended_at INTEGER,\n        scanned_count INTEGER NOT NULL DEFAULT 0,\n        match_count INTEGER NOT NULL DEFAULT 0,\n        mismatch_count INTEGER NOT NULL DEFAULT 0,\n        price_diff_count INTEGER NOT NULL DEFAULT 0,\n        no_price_count INTEGER NOT NULL DEFAULT 0\n      )\n    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
