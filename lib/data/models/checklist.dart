/// Kontrol listesi oturumu (bir "liste").
class Checklist {
  final int? id;
  final String title;
  final int? color; // ARGB int (null = varsayilan)
  final DateTime createdAt;
  final DateTime updatedAt;

  const Checklist({
    this.id,
    required this.title,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  Checklist copyWith({
    int? id,
    String? title,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Checklist(
      id: id ?? this.id,
      title: title ?? this.title,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'color': color,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Checklist.fromMap(Map<String, dynamic> map) {
    return Checklist(
      id: map['id'] as int?,
      title: map['title'] as String,
      color: map['color'] as int?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}

/// Bir kontrol listesindeki tek madde.
class ChecklistItem {
  final int? id;
  final int checklistId;
  final String text;
  final bool done;
  final int position;

  const ChecklistItem({
    this.id,
    required this.checklistId,
    required this.text,
    this.done = false,
    this.position = 0,
  });

  ChecklistItem copyWith({
    int? id,
    int? checklistId,
    String? text,
    bool? done,
    int? position,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      checklistId: checklistId ?? this.checklistId,
      text: text ?? this.text,
      done: done ?? this.done,
      position: position ?? this.position,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'checklist_id': checklistId,
      'text': text,
      'done': done ? 1 : 0,
      'position': position,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as int?,
      checklistId: map['checklist_id'] as int,
      text: map['text'] as String,
      done: (map['done'] as int) == 1,
      position: map['position'] as int,
    );
  }
}
