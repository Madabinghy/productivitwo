part of '../models.dart';

/// Pointage de l'état de la personne (lot 2 badges, 2026-10) : un geste, jamais
/// bloquant. `kind` : "elan" (avant, 1 Flemme → 5 Lancé, au premier geste d'un
/// moment, 3 par jour au plus), "effort" (après un bloc, 0 Facile · 1 Juste ·
/// 2 Dur), "mood" (humeur du jour, le soir, 0 Bas · 1 Neutre · 2 Bon).
/// Collection `users/{uid}/mood_marks/{id}`. Le lien entre un pointage d'élan
/// et « ce qui a été fait ensuite » n'est jamais stocké : il est recalculé par
/// fenêtre (`utils/elan_logic.dart`), comme le lien session ↔ bloc.
const kMoodElan = 'elan';
const kMoodEffort = 'effort';
const kMoodMood = 'mood';

const kElanLabels = ['', 'Flemme', 'Mou', 'Moyen', 'En forme', 'Lancé'];
const kEffortLabels = ['Facile', 'Juste', 'Dur'];
const kMoodLabels = ['Bas', 'Neutre', 'Bon'];

class MoodMark {
  String id;
  DateTime at;
  String ymd; // journée vécue, YYYY-MM-DD
  String kind;
  int value;
  String? moment; // élan : "matin" | "aprem" | "soir"
  String? activityId, projectId, taskId, actionId, blockId;

  MoodMark({
    String? id,
    required this.at,
    required this.ymd,
    required this.kind,
    required this.value,
    this.moment,
    this.activityId,
    this.projectId,
    this.taskId,
    this.actionId,
    this.blockId,
  }) : id = id ?? _uuid.v4();

  bool get isElan => kind == kMoodElan;
  /// Flemme ou Mou ; 0 = recharge (pointage virtuel de la nuit), jamais bas.
  bool get lowElan => isElan && value >= 1 && value <= 2;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'ymd': ymd,
        'kind': kind,
        'value': value,
        if (moment != null) 'moment': moment,
        if (activityId != null) 'activityId': activityId,
        if (projectId != null) 'projectId': projectId,
        if (taskId != null) 'taskId': taskId,
        if (actionId != null) 'actionId': actionId,
        if (blockId != null) 'blockId': blockId,
      };

  static MoodMark from(Map j) => MoodMark(
        id: j['id'] as String?,
        at: _parseDate(j['at']),
        ymd: (j['ymd'] ?? '').toString(),
        kind: (j['kind'] ?? kMoodElan).toString(),
        value: (j['value'] as num?)?.toInt() ?? 0,
        moment: j['moment'] as String?,
        activityId: j['activityId'] as String?,
        projectId: j['projectId'] as String?,
        taskId: j['taskId'] as String?,
        actionId: j['actionId'] as String?,
        blockId: j['blockId'] as String?,
      );
}
