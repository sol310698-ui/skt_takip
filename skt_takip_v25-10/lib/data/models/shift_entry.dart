/// Mesai (vardiya) kaydi modeli.
class ShiftEntry {
  final int? id;
  final DateTime clockIn;        // giris zamani
  final DateTime? clockOut;      // cikis zamani (null = devam ediyor)
  final double? inLatitude;      // giris konumu
  final double? inLongitude;
  final double? outLatitude;     // cikis konumu
  final double? outLongitude;
  final String? photoInPath;     // giris fotografi (dosya yolu)
  final String? photoOutPath;    // cikis fotografi
  final String? note;

  const ShiftEntry({
    this.id,
    required this.clockIn,
    this.clockOut,
    this.inLatitude,
    this.inLongitude,
    this.outLatitude,
    this.outLongitude,
    this.photoInPath,
    this.photoOutPath,
    this.note,
  });

  bool get isOpen => clockOut == null;

  /// Calisma suresi (devam ediyorsa simdiye kadar).
  Duration get duration {
    final end = clockOut ?? DateTime.now();
    return end.difference(clockIn);
  }

  String get durationLabel {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}s ${m}dk';
  }

  ShiftEntry copyWith({
    int? id,
    DateTime? clockIn,
    DateTime? clockOut,
    double? inLatitude,
    double? inLongitude,
    double? outLatitude,
    double? outLongitude,
    String? photoInPath,
    String? photoOutPath,
    String? note,
  }) {
    return ShiftEntry(
      id: id ?? this.id,
      clockIn: clockIn ?? this.clockIn,
      clockOut: clockOut ?? this.clockOut,
      inLatitude: inLatitude ?? this.inLatitude,
      inLongitude: inLongitude ?? this.inLongitude,
      outLatitude: outLatitude ?? this.outLatitude,
      outLongitude: outLongitude ?? this.outLongitude,
      photoInPath: photoInPath ?? this.photoInPath,
      photoOutPath: photoOutPath ?? this.photoOutPath,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'clock_in': clockIn.millisecondsSinceEpoch,
        'clock_out': clockOut?.millisecondsSinceEpoch,
        'in_lat': inLatitude,
        'in_lng': inLongitude,
        'out_lat': outLatitude,
        'out_lng': outLongitude,
        'photo_in': photoInPath,
        'photo_out': photoOutPath,
        'note': note,
      };

  factory ShiftEntry.fromMap(Map<String, Object?> m) => ShiftEntry(
        id: m['id'] as int?,
        clockIn: DateTime.fromMillisecondsSinceEpoch(m['clock_in'] as int),
        clockOut: m['clock_out'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['clock_out'] as int)
            : null,
        inLatitude: (m['in_lat'] as num?)?.toDouble(),
        inLongitude: (m['in_lng'] as num?)?.toDouble(),
        outLatitude: (m['out_lat'] as num?)?.toDouble(),
        outLongitude: (m['out_lng'] as num?)?.toDouble(),
        photoInPath: m['photo_in'] as String?,
        photoOutPath: m['photo_out'] as String?,
        note: m['note'] as String?,
      );
}
