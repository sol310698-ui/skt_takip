import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Etiket basim formatlari. Her formatin kullanici tarafindan
/// degistirilebilir genislik/yukseklik (mm) degeri vardir.
enum LabelFormat {
  bigRoll, // buyuk rulo/termal etiket
  smallRoll, // kucuk rulo (ron) etiket
  a4Single, // A4 - tekli
  a4Double, // A4 - ikili
  a4Triple, // A4 - uclu
}

extension LabelFormatX on LabelFormat {
  String get dbValue {
    switch (this) {
      case LabelFormat.bigRoll:
        return 'big_roll';
      case LabelFormat.smallRoll:
        return 'small_roll';
      case LabelFormat.a4Single:
        return 'a4_single';
      case LabelFormat.a4Double:
        return 'a4_double';
      case LabelFormat.a4Triple:
        return 'a4_triple';
    }
  }

  String get title {
    switch (this) {
      case LabelFormat.bigRoll:
        return 'Büyük Rulo';
      case LabelFormat.smallRoll:
        return 'Küçük Rön';
      case LabelFormat.a4Single:
        return 'A4 Tekli';
      case LabelFormat.a4Double:
        return 'A4 İkili';
      case LabelFormat.a4Triple:
        return 'A4 Üçlü';
    }
  }

  String get subtitle {
    switch (this) {
      case LabelFormat.bigRoll:
        return 'Tek büyük termal etiket';
      case LabelFormat.smallRoll:
        return 'Küçük rulo etiket';
      case LabelFormat.a4Single:
        return 'A4 sayfada 1 etiket';
      case LabelFormat.a4Double:
        return 'A4 sayfada 2 etiket';
      case LabelFormat.a4Triple:
        return 'A4 sayfada 3 etiket';
    }
  }

  /// Bu format A4 tabanli mi (cok-etiketli sayfa duzeni)?
  bool get isA4 =>
      this == LabelFormat.a4Single ||
      this == LabelFormat.a4Double ||
      this == LabelFormat.a4Triple;

  /// A4 formatlari icin sayfadaki etiket adedi.
  int get perPage {
    switch (this) {
      case LabelFormat.a4Single:
        return 1;
      case LabelFormat.a4Double:
        return 2;
      case LabelFormat.a4Triple:
        return 3;
      default:
        return 1;
    }
  }

  /// Varsayilan genislik (mm).
  double get defaultWidthMm {
    switch (this) {
      case LabelFormat.bigRoll:
        return 100;
      case LabelFormat.smallRoll:
        return 40;
      case LabelFormat.a4Single:
        return 200;
      case LabelFormat.a4Double:
        return 200;
      case LabelFormat.a4Triple:
        return 200;
    }
  }

  /// Varsayilan yukseklik (mm).
  double get defaultHeightMm {
    switch (this) {
      case LabelFormat.bigRoll:
        return 50;
      case LabelFormat.smallRoll:
        return 30;
      case LabelFormat.a4Single:
        return 280;
      case LabelFormat.a4Double:
        return 140;
      case LabelFormat.a4Triple:
        return 93;
    }
  }

  static LabelFormat fromDb(String? v) {
    switch (v) {
      case 'big_roll':
        return LabelFormat.bigRoll;
      case 'small_roll':
        return LabelFormat.smallRoll;
      case 'a4_single':
        return LabelFormat.a4Single;
      case 'a4_double':
        return LabelFormat.a4Double;
      case 'a4_triple':
        return LabelFormat.a4Triple;
      default:
        return LabelFormat.bigRoll;
    }
  }
}

/// Bir formata ait olcu (mm).
class LabelDimensions {
  final double widthMm;
  final double heightMm;
  const LabelDimensions(this.widthMm, this.heightMm);
}

/// Etiket olcu ayarlari. Her format icin kullanici genislik/yukseklik
/// degerini ayarlayabilir; flutter_secure_storage ile saklanir.
class LabelSettingsService {
  LabelSettingsService._();
  static final LabelSettingsService instance = LabelSettingsService._();

  static const _storage = FlutterSecureStorage();

  String _wKey(LabelFormat f) => 'label_${f.dbValue}_w';
  String _hKey(LabelFormat f) => 'label_${f.dbValue}_h';

  Future<LabelDimensions> getDimensions(LabelFormat f) async {
    final w = await _storage.read(key: _wKey(f));
    final h = await _storage.read(key: _hKey(f));
    return LabelDimensions(
      double.tryParse(w ?? '') ?? f.defaultWidthMm,
      double.tryParse(h ?? '') ?? f.defaultHeightMm,
    );
  }

  Future<void> setDimensions(
    LabelFormat f, {
    required double widthMm,
    required double heightMm,
  }) async {
    await _storage.write(key: _wKey(f), value: widthMm.toString());
    await _storage.write(key: _hKey(f), value: heightMm.toString());
  }

  Future<void> resetToDefault(LabelFormat f) async {
    await _storage.delete(key: _wKey(f));
    await _storage.delete(key: _hKey(f));
  }
}
