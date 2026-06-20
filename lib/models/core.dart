part of '../models.dart';

class DayBlock {
  String id;
  String name;
  String? emoji;
  int order;
  List<String> activityIds;
  int? startHour;   // heure de début du bloc (null = pas de rappel)
  int? startMinute;

  DayBlock({
    String? id,
    required this.name,
    this.emoji,
    this.order = 0,
    List<String>? activityIds,
    this.startHour,
    this.startMinute,
  })  : id = id ?? _uuid.v4(),
        activityIds = activityIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'order': order,
        'activityIds': activityIds,
        'startHour': startHour,
        'startMinute': startMinute,
      };

  static DayBlock from(Map j) => DayBlock(
        id: j['id'],
        name: j['name'] ?? '',
        emoji: j['emoji'],
        order: (j['order'] as num?)?.toInt() ?? 0,
        activityIds:
            (j['activityIds'] as List?)?.cast<String>() ?? <String>[],
        startHour: j['startHour'] as int?,
        startMinute: j['startMinute'] as int?,
      );
}

class ActivityLog {
  final String id;
  final String activityId;
  final DateTime start;
  final DateTime? end;

  ActivityLog({
    required this.id,
    required this.activityId,
    required this.start,
    this.end,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
      };

  static ActivityLog from(Map<String, dynamic> j) => ActivityLog(
        id: j['id'],
        activityId: j['activityId'],
        start: _parseDate(j['start']),
        end: _parseDateOrNull(j['end']),
      );
}

class InboxItem {
  String id;
  String title;
  DateTime createdAt;
  InboxItem({String? id, required this.title, DateTime? createdAt})
      : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };
  static InboxItem from(Map j) => InboxItem(
        id: j['id'],
        title: j['title'],
        createdAt: _parseDate(j['createdAt']),
      );
}


/// --- DOMAINES ---
class Domain {
  String id, name;
  int? goalMinDay;
  bool autoGoal;
  int? colorValue;
  bool deleted; // true = supprimé via MCP, ignoré dans l'UI

  Domain({
    String? id,
    required this.name,
    this.goalMinDay,
    this.autoGoal = true,
    this.colorValue,
    this.deleted = false,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goalMinDay': goalMinDay,
        'autoGoal': autoGoal,
        'colorValue': colorValue,
        'deleted': deleted,
      };

  static Domain from(Map j) => Domain(
        id: j['id'],
        name: j['name'],
        goalMinDay: j['goalMinDay'],
        autoGoal: j['autoGoal'] ?? true,
        colorValue: j['colorValue'] as int?,
        deleted: j['deleted'] as bool? ?? false,
      );
}
