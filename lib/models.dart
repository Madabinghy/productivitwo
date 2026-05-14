import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const int kMinDailyGoalMin = 1;

enum PlanKind { action, activityTime, habit }

enum HabitFreq { daily, weekly, monthly }

enum ActionStatus {
  active,
  done,
  archived,
  inbox,
}

class ChecklistItem {
  String id;
  String title;
  bool done;

  ChecklistItem({required this.id, required this.title, this.done = false});

  Map<String, dynamic> toJson() => {
        "id": id,
        "title": title,
        "done": done,
      };

  static ChecklistItem from(Map j) {
    final rawId = (j["id"] ?? "").toString().trim();
    final title = (j["title"] ?? "").toString();
    final done = (j["done"] == true);

    return ChecklistItem(
      id: rawId.isNotEmpty
          ? rawId
          : "migr_${DateTime.now().microsecondsSinceEpoch}", // ✅
      title: title,
      done: done,
    );
  }
}

class DayPlanItem {
  String id;
  PlanKind kind;
  String? refId;
  String? domainId;
  String? activityId;
  String? habitId;
  String? goalActionId;
  String title;
  String yyyymmdd;
  bool done;
  int doneCount;
  bool allDay;
  int order;
  bool isNowFocus;
  bool toPlan; // ✅ item "Courses / à prévoir"
  bool archived; // ✅ archivé (global si habitId == null)
  DateTime? snoozeUntil;
  ActionStatus status;
  DateTime createdAt;
  String? blockId;
  String? recurringActionId; // id de RecurringAction si généré automatiquement

  // ✅ NEW
  List<ChecklistItem> checklist;

  DayPlanItem({
    required this.id,
    required this.kind,
    this.refId,
    this.domainId,
    this.activityId,
    this.habitId,
    this.goalActionId,
    required this.title,
    required this.yyyymmdd,
    this.done = false,
    this.doneCount = 0,
    this.allDay = false,
    this.isNowFocus = false,
    this.order = 0,
    this.toPlan = false,
    this.archived = false,
    DateTime? createdAt,
    this.snoozeUntil,
    ActionStatus? status,
    this.blockId,
    this.recurringActionId,

    // ✅ NEW
    List<ChecklistItem>? checklist,
  })  : createdAt = createdAt ?? DateTime.now(),
        status = status ?? ActionStatus.active,
        checklist = checklist ?? <ChecklistItem>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'refId': refId,
        'domainId': domainId,
        'activityId': activityId,
        'habitId': habitId,
        'goalActionId': goalActionId,
        'title': title,
        'yyyymmdd': yyyymmdd,
        'done': done,
        'doneCount': doneCount,
        'allDay': allDay,
        'isNowFocus': isNowFocus,
        'order': order,
        'toPlan': toPlan,
        'archived': archived,
        'snoozeUntil': snoozeUntil?.toIso8601String(),

        // ✅ AJOUT
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'blockId': blockId,
        'recurringActionId': recurringActionId,

        // ✅ CHECKLIST
        'checklist': checklist.map((c) => c.toJson()).toList(),
      };

  static DayPlanItem from(Map j) {
    final done = _asBool(j['done']);
    final doneCount = j['doneCount'] ?? (done ? 1 : 0);

    final kindStr = (j['kind'] as String?)?.trim();

    final kind = PlanKind.values.firstWhere(
      (k) => k.name == kindStr,
      orElse: () => PlanKind.action, // ✅ ou une valeur par défaut cohérente
    );

    String? refId = (j['refId'] as String?)?.trim();
    String? habitId = (j['habitId'] as String?)?.trim();

    if (kind == PlanKind.habit && (refId == null || refId.isEmpty)) {
      refId = habitId;
      habitId = null;
    }

    return DayPlanItem(
      id: j['id'],
      kind: kind,
      refId: refId,
      habitId: habitId,
      goalActionId: j['goalActionId'] as String?,
      domainId: j['domainId'],
      activityId: j['activityId'],
      title: j['title'] ?? '',
      yyyymmdd: j['yyyymmdd'],
      done: done,
      doneCount: doneCount,
      allDay: _asBool(j['allDay']),
      isNowFocus: _asBool(j['isNowFocus']),
      order: (j['order'] as num?)?.toInt() ?? 0,
      toPlan: _asBool(j['toPlan']),
      archived: _asBool(j['archived']),
      snoozeUntil: j['snoozeUntil'] != null
          ? DateTime.tryParse(j['snoozeUntil'])
          : null,
      status: ActionStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => ActionStatus.active,
      ),
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
          : null,
      blockId: j['blockId'] as String?,
      recurringActionId: j['recurringActionId'] as String?,
      checklist: (j['checklist'] as List?)
              ?.map((c) => ChecklistItem.from(c))
              .toList() ??
          [],
    );
  }

  static bool _asBool(dynamic v, {bool defaultValue = false}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      if (t == 'true' || t == '1' || t == 'yes') return true;
      if (t == 'false' || t == '0' || t == 'no') return false;
    }
    return defaultValue;
  }
}

enum RecurrenceType { daily, specificDays }

class RecurringAction {
  final String id;
  String title;
  String? domainId;
  String? activityId;
  String? blockId;
  RecurrenceType type;
  List<int> weekdays; // 1=Lun..7=Dim, utilisé pour specificDays
  bool active;
  final DateTime createdAt;

  RecurringAction({
    String? id,
    required this.title,
    this.domainId,
    this.activityId,
    this.blockId,
    this.type = RecurrenceType.daily,
    List<int>? weekdays,
    this.active = true,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        weekdays = weekdays ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'domainId': domainId,
        'activityId': activityId,
        'blockId': blockId,
        'type': type.name,
        'weekdays': weekdays,
        'active': active,
        'createdAt': createdAt.toIso8601String(),
      };

  static RecurringAction from(Map j) => RecurringAction(
        id: j['id'],
        title: j['title'] ?? '',
        domainId: j['domainId'],
        activityId: j['activityId'],
        blockId: j['blockId'],
        type: RecurrenceType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => RecurrenceType.daily,
        ),
        weekdays:
            (j['weekdays'] as List?)?.map((e) => e as int).toList() ?? [],
        active: j['active'] as bool? ?? true,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
            : null,
      );
}

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
        start: DateTime.parse(j['start']),
        end: j['end'] != null ? DateTime.parse(j['end']) : null,
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
        createdAt: DateTime.parse(j['createdAt']),
      );
}

// --- OBJECTIFS (GTD light) ---
// status: 'active' | 'done' | 'archived'
class GoalAction {
  String id;
  String title;
  bool done;
  DateTime? doneAt;

  GoalAction({String? id, required this.title, this.done = false, this.doneAt})
      : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
      };

  static GoalAction from(Map j) => GoalAction(
        id: j['id'],
        title: j['title'] ?? '',
        done: j['done'] as bool? ?? (j['doneAt'] != null),
        doneAt: j['doneAt'] != null ? DateTime.tryParse(j['doneAt']) : null,
      );
}

class Goal {
  String id, domainId, title;
  String status;
  String? activityId;
  List<String> linkedHabitIds;
  String? context;
  DateTime createdAt;
  DateTime? doneAt;
  DateTime? dueDate;
  List<GoalAction> actions;
  int order;
  bool pinned;

  Goal({
    String? id,
    required this.domainId,
    required this.title,
    this.status = 'active',
    this.activityId,
    List<String>? linkedHabitIds,
    this.context,
    DateTime? createdAt,
    this.doneAt,
    this.dueDate,
    List<GoalAction>? actions,
    this.order = 0,
    this.pinned = false,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        linkedHabitIds = linkedHabitIds ?? [],
        actions = actions ?? [];

  GoalAction? get nextAction =>
      actions.where((a) => !a.done).firstOrNull;

  int get stepsDone => actions.where((a) => a.done).length;
  int get stepsTotal => actions.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'title': title,
        'status': status,
        'activityId': activityId,
        'linkedHabitIds': linkedHabitIds,
        'context': context,
        'createdAt': createdAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'order': order,
        'pinned': pinned,
      };

  static Goal from(Map j) {
    // Migration : ancien format avait nextAction (String) + doneActions (List)
    final List<GoalAction> actions = [];
    final rawDone = j['doneActions'] as List?;
    if (rawDone != null) {
      for (final e in rawDone) {
        actions.add(GoalAction.from({...e, 'done': true}));
      }
    }
    final rawActions = j['actions'] as List?;
    if (rawActions != null) {
      for (final e in rawActions) {
        actions.add(GoalAction.from(e));
      }
    }
    final oldNext = j['nextAction'] as String?;
    if (oldNext != null &&
        oldNext.isNotEmpty &&
        !actions.any((a) => !a.done)) {
      actions.add(GoalAction(title: oldNext, done: false));
    }
    return Goal(
      id: j['id'],
      domainId: j['domainId'],
      title: j['title'],
      status: j['status'] ?? 'active',
      activityId: j['activityId'],
      linkedHabitIds: (j['linkedHabitIds'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      context: j['context'],
      createdAt: DateTime.parse(j['createdAt']),
      doneAt: j['doneAt'] != null ? DateTime.parse(j['doneAt']) : null,
      dueDate: j['dueDate'] != null ? DateTime.parse(j['dueDate']) : null,
      actions: actions,
      order: (j['order'] as num?)?.toInt() ?? 0,
      pinned: j['pinned'] as bool? ?? false,
    );
  }
}

/// --- DOMAINES ---
class Domain {
  String id, name;
  int? goalMinDay; // minutes/jour, null => auto (somme des activités time)
  bool autoGoal; // true => objectif = somme des activités time

  Domain({
    String? id,
    required this.name,
    this.goalMinDay,
    this.autoGoal = true,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goalMinDay': goalMinDay,
        'autoGoal': autoGoal,
      };

  static Domain from(Map j) => Domain(
        id: j['id'],
        name: j['name'],
        goalMinDay: j['goalMinDay'],
        autoGoal: j['autoGoal'] ?? true,
      );
}

enum ActivityRole {
  generic,
  shopping, // 👈 Courses
  focus,
  planning
}

/// --- ACTIVITÉS ---
/// type = "time" (timer) ou "habit" (compteur)

class Activity {
  // Identité / base
  final String id;
  final String domainId;
  String name;
  final ActivityRole role;

  /// "time" | "habit"
  final String type;

  /// Objectif/jour pour les activités TEMPS (minutes). Plancher logique = 1.
  int goalMin;

  /// Unité d’une routine (ex: "verres", "pompes")
  String? unit;

  // ---------- Routines (nouveau modèle unifié) ----------
  /// Fréquence active : daily / weekly / monthly (null si aucun réglage encore)
  HabitFreq? habitFreq;

  /// Cible pour la période active (ex: 10/mois, 1/sem, 1/jour). Peut rester null.
  int? habitTarget;

  /// Si true, on n’applique pas l’auto-tune (l’utilisateur pilote la cible).
  bool manualTarget;

  /// Si true (par défaut), la routine peut être ajustée automatiquement.
  bool autoTune;

  /// Métadonnées
  final DateTime createdAt;
  DateTime? lastTuneAt;

  final String? linkedActivityId;

  int order;

  Activity({
    String? id,
    required this.domainId,
    required this.name,
    this.type = 'time',
    this.role = ActivityRole.generic,
    this.goalMin = 1,
    this.unit,
    this.habitFreq,
    this.habitTarget,
    this.manualTarget = false,
    this.autoTune = true,
    DateTime? createdAt,
    this.lastTuneAt,
    this.linkedActivityId,
    this.order = 0,
  })  : id = id ?? _uuid.v4(), // <-- sans const ici
        createdAt = createdAt ?? DateTime.now();

  // -------- Helpers --------
  bool get isHabit => type == 'habit' || type == 'action';

  /// Fréquence « effective » (fallback mensuel si rien n’est défini).
  HabitFreq get effHabitFreq => habitFreq ?? HabitFreq.monthly;

  /// Cible « effective » (fallback 1 si rien n’est défini).
  int get effHabitTarget => (habitTarget ?? 1);

  // -------- Serialization --------
  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'name': name,
        'type': type,
        'role': role.name,
        'goalMin': goalMin,
        'unit': unit,
        // plus de dailyTarget ici
        'habitFreq': habitFreq?.index,
        'habitTarget': habitTarget,
        'manualTarget': manualTarget,
        'autoTune': autoTune,
        'linkedActivityId':linkedActivityId,
        'createdAt': createdAt.toIso8601String(),
        'lastTuneAt': lastTuneAt?.toIso8601String(),
        'order': order,
      };

  /// Migration douce :
  /// - Si l’ancien JSON contient `dailyTarget`, on l’interprète comme (freq=daily, target=dailyTarget).
  /// - Si `habitFreq` est présent on le respecte, sinon on déduit depuis dailyTarget.
  factory Activity.from(Map j) {
    // Legacy
    final int? legacyDaily = j['dailyTarget'];

    HabitFreq? parsedFreq;
    if (j['habitFreq'] != null) {
      try {
        parsedFreq = HabitFreq.values[j['habitFreq']];
      } catch (_) {
        parsedFreq = null; // fallback plus bas
      }
    } else if (legacyDaily != null) {
      parsedFreq = HabitFreq.daily;
    }

    final int? parsedTarget = j['habitTarget'] ?? legacyDaily;

    return Activity(
      id: j['id'],
      domainId: j['domainId'],
      name: j['name'],
      type: (j['type'] ?? 'time'),
      role: ActivityRole.values.firstWhere(
        (r) => r.name == j['role'],
        orElse: () => ActivityRole.generic,
      ),
      goalMin: (j['goalMin'] ?? 1) is int ? (j['goalMin'] ?? 1) : 1,
      unit: j['unit'],
      habitFreq: parsedFreq,
      habitTarget: parsedTarget,
      manualTarget: j['manualTarget'] ?? false,
      autoTune: j['autoTune'] ?? true,
      linkedActivityId:j['linkedActivityId'],
      createdAt: j['createdAt'] != null
          ? DateTime.parse(j['createdAt'])
          : DateTime.now(),
      lastTuneAt:
          j['lastTuneAt'] != null ? DateTime.parse(j['lastTuneAt']) : null,
      order: (j['order'] as num?)?.toInt() ?? 0,
    );
  }

  // -------- Utilities --------
  Activity copyWith({
    String? id,
    String? domainId,
    String? name,
    String? type,
    int? goalMin,
    String? unit,
    HabitFreq? habitFreq,
    int? habitTarget,
    bool? manualTarget,
    bool? autoTune,
    DateTime? createdAt,
    DateTime? lastTuneAt,
    String? linkedActivityId,
  }) {
    return Activity(
      id: id ?? this.id,
      domainId: domainId ?? this.domainId,
      name: name ?? this.name,
      type: type ?? this.type,
      goalMin: goalMin ?? this.goalMin,
      unit: unit ?? this.unit,
      habitFreq: habitFreq ?? this.habitFreq,
      habitTarget: habitTarget ?? this.habitTarget,
      manualTarget: manualTarget ?? this.manualTarget,
      autoTune: autoTune ?? this.autoTune,
      createdAt: createdAt ?? this.createdAt,
      lastTuneAt: lastTuneAt ?? this.lastTuneAt,
      linkedActivityId: linkedActivityId ?? null,
    );
  }

  @override
  String toString() => 'Activity($id, $name, type=$type, '
      'goalMin=$goalMin, freq=$habitFreq, target=$habitTarget, '
      'manual=$manualTarget, auto=$autoTune)';

  @override
  bool operator ==(Object other) {
    return other is Activity &&
        other.id == id &&
        other.domainId == domainId &&
        other.name == name &&
        other.type == type &&
        other.goalMin == goalMin &&
        other.unit == unit &&
        other.habitFreq == habitFreq &&
        other.habitTarget == habitTarget &&
        other.manualTarget == manualTarget &&
        other.autoTune == autoTune &&
        other.createdAt == createdAt &&
        other.lastTuneAt == lastTuneAt&&
        other.linkedActivityId == linkedActivityId ;
  }

  @override
  int get hashCode => Object.hash(
        id,
        domainId,
        name,
        type,
        goalMin,
        unit,
        habitFreq,
        habitTarget,
        manualTarget,
        autoTune,
        createdAt,
        lastTuneAt,
        linkedActivityId,
      );
}

/// --- SESSIONS TEMPS ---
class Session {
  String id, activityId;
  DateTime startAt;
  DateTime? endAt;
  Session(
      {String? id, required this.activityId, required this.startAt, this.endAt})
      : id = id ?? _uuid.v4();
  Duration get duration => (endAt ?? DateTime.now()).difference(startAt);
  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String()
      };
  static Session from(Map j) => Session(
      id: j['id'],
      activityId: j['activityId'],
      startAt: DateTime.parse(j['startAt']),
      endAt: j['endAt'] != null ? DateTime.parse(j['endAt']) : null);
}

class HabitHit {
  String id;
  String habitId; // (= activityId de l'habit)
  DateTime ts;
  String? contextActivityId; // activité en cours au moment de l'incrément

  HabitHit({
    String? id,
    required this.habitId,
    required this.ts,
    this.contextActivityId,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'habitId': habitId,
        'ts': ts.toIso8601String(),
        'contextActivityId': contextActivityId,
      };

  static HabitHit from(Map j) => HabitHit(
        id: j['id'],
        habitId: j['habitId'],
        ts: DateTime.parse(j['ts']),
        contextActivityId: j['contextActivityId'],
      );
}

/// --- PROGRESSION HABITUDES ---
/// Stocke la valeur d’une habitude pour un jour donné (clé date "YYYYMMDD")
class HabitProgress {
  String id, activityId, yyyymmdd;
  int value;
  HabitProgress({
    String? id,
    required this.activityId,
    required this.yyyymmdd,
    this.value = 0,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'yyyymmdd': yyyymmdd,
        'value': value
      };

  static HabitProgress from(Map j) => HabitProgress(
        id: j['id'],
        activityId: j['activityId'],
        yyyymmdd: j['yyyymmdd'],
        value: j['value'] ?? 0,
      );
}

class FilterState {
  bool enabled; // toggle global "Filtré"
  bool focusOnly; // mode Focus ⭐ (optionnel ici)
  Set<String> domainIds;
  Set<String> activityIds;
  Set<String> contextIds; // si tu as une notion de contexte
  bool includeNoDomain;
  bool includeNoActivity;

  FilterState({
    this.enabled = true,
    this.focusOnly = false,
    Set<String>? domainIds,
    Set<String>? activityIds,
    Set<String>? contextIds,
    this.includeNoDomain = true,
    this.includeNoActivity = true,
  })  : domainIds = domainIds ?? <String>{},
        activityIds = activityIds ?? <String>{},
        contextIds = contextIds ?? <String>{};

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'focusOnly': focusOnly,
        'domainIds': domainIds.toList(),
        'activityIds': activityIds.toList(),
        'contextIds': contextIds.toList(),
        'includeNoDomain': includeNoDomain,
        'includeNoActivity': includeNoActivity,
      };

  static FilterState from(dynamic j) {
    if (j == null) return FilterState();
    final m = j as Map;
    return FilterState(
      enabled: (m['enabled'] as bool?) ?? false,
      focusOnly: (m['focusOnly'] as bool?) ?? false,
      domainIds: ((m['domainIds'] as List?)?.cast<String>() ?? const <String>[])
          .toSet(),
      activityIds:
          ((m['activityIds'] as List?)?.cast<String>() ?? const <String>[])
              .toSet(),
      contextIds:
          ((m['contextIds'] as List?)?.cast<String>() ?? const <String>[])
              .toSet(),
      includeNoDomain: (m['includeNoDomain'] as bool?) ?? true,
      includeNoActivity: (m['includeNoActivity'] as bool?) ?? true,
    );
  }

  bool get isActive => domainIds.isNotEmpty || activityIds.isNotEmpty;
}

// ─── Badges ──────────────────────────────────────────────────────────────────

enum BadgeId {
  streak3, streak7, streak21, streak66, streak100,
  scoreFirst100, score7dAt80, score30dAt80,
  actions10, actions50, actions100,
}

class BadgeMeta {
  final String emoji;
  final String label;
  final String description;
  const BadgeMeta(this.emoji, this.label, this.description);
}

BadgeMeta badgeMeta(BadgeId id) {
  switch (id) {
    case BadgeId.streak3:      return const BadgeMeta('🔥', '3 jours',        'Série de 3 jours d\'affilée');
    case BadgeId.streak7:      return const BadgeMeta('🔥', '7 jours',        'Une semaine sans fauter');
    case BadgeId.streak21:     return const BadgeMeta('⚡', '21 jours',       'L\'habitude est prise');
    case BadgeId.streak66:     return const BadgeMeta('💎', '66 jours',       'Ancré dans le quotidien');
    case BadgeId.streak100:    return const BadgeMeta('👑', '100 jours',      'Centurion');
    case BadgeId.scoreFirst100:return const BadgeMeta('⭐', 'Journée parfaite','Première journée à 100%');
    case BadgeId.score7dAt80:  return const BadgeMeta('🌟', 'Semaine solide', '7 jours consécutifs à 80%+');
    case BadgeId.score30dAt80: return const BadgeMeta('🌟', 'Mois solide',    '30 jours consécutifs à 80%+');
    case BadgeId.actions10:    return const BadgeMeta('✅', '10 actions',      'En route !');
    case BadgeId.actions50:    return const BadgeMeta('✅', '50 actions',      'Productif !');
    case BadgeId.actions100:   return const BadgeMeta('✅', '100 actions',     'Centurion des tâches');
  }
}

class EarnedBadge {
  final BadgeId id;
  final String? habitId; // null = badge global
  final String earnedAt; // yyyymmdd

  EarnedBadge({required this.id, this.habitId, required this.earnedAt});

  Map<String, dynamic> toJson() => {
    'id': id.name,
    if (habitId != null) 'habitId': habitId,
    'earnedAt': earnedAt,
  };

  static EarnedBadge? tryFrom(dynamic j) {
    try {
      final m = j as Map;
      final id = BadgeId.values.firstWhere((b) => b.name == m['id'] as String);
      return EarnedBadge(
        id: id,
        habitId: m['habitId'] as String?,
        earnedAt: m['earnedAt'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AppState {
  List<Domain> domains;
  List<Activity> activities;
  List<Session> sessions;
  List<HabitProgress> habitProgress;

  DateTime? lastGoalsReview;

  // NEW: activité → ISO8601 jusqu’à quand elle est “snoozed”
  Map<String, String> snoozedUntil;

  List<Goal> goals;
  List<InboxItem> inbox;
  List<DayPlanItem> dayPlan;

  String? lastRolloverYmd;
  String? lastCarryYmd; // on a déjà fait "Hier → Aujourd'hui" pour ce jour ?
  String? lastPrepYmd; // on a déjà fait "Aujourd'hui → Demain" pour ce jour ?

  List<String> focusTodayIds;
  bool sortTodayByDashboard;
  bool onboardingDone;

  // ✅ Habits context (associations)
  List<HabitHit> habitHits;
  Map<String, String> habitPinnedActivity;
  Map<String, List<String>> nowSkippedByYmd; // ids de DayPlanItem (ou virt ids)
  Map<String, List<String>> nowDoneByYmd; // ids "pas aujourd'hui / ok"
  Map<String, List<String>>
      habitChecklistByHabitId; // habitId -> ["item1","item2"]

  // ✅ NEW : progress checklist persisté
// habitId -> periodKey -> [indexes cochés]
  Map<String, Map<String, List<int>>> habitChecklistDone;
  FilterState filters;

  List<ActivityLog> activityLogs;
  bool coursesArchivedOnce;
  bool coursesRestoredOnce;
  bool coursesRestoredV2;
  bool linkedActivitiesMigratedOnce;
  bool voitureMigratedOnce;

  // Blocs journaliers
  List<DayBlock> blocks;
  List<RecurringAction> recurringActions;
  Map<String, List<String>> disabledBlocksByYmd; // ymd -> [blockIds désactivés]

  // Gamification
  List<EarnedBadge> earnedBadges;
  List<String> skippedChallengeDates;
  int weeklyScoreTarget; // % objectif hebdomadaire (0-100) // yyyymmdd où le défi a été passé
  int notifHour;           // rappel quotidien (défaut 9h)
  int notifMinute;
  bool notifEnabled;
  int reviewNotifHour;     // résumé fin de journée (défaut 21h)
  int reviewNotifMinute;
  bool reviewNotifEnabled;
  int streakNotifHour;     // streak en danger (défaut 20h)
  int streakNotifMinute;
  bool streakNotifEnabled;
  int challengeNotifHour;  // défi du jour (défaut 16h)
  int challengeNotifMinute;
  bool challengeNotifEnabled;
  int midDayNotifHour;     // score mi-journée (défaut 13h)
  int midDayNotifMinute;
  bool midDayNotifEnabled;
  bool domainIdBackfilledOnce;

  AppState({
    required this.domains,
    required this.activities,
    required this.sessions,
    required this.habitProgress,
    this.lastGoalsReview,
    Map<String, String>? snoozedUntil,
    List<Goal>? goals,
    List<InboxItem>? inbox,
    List<DayPlanItem>? dayPlan,
    List<String>? focusTodayIds,
    this.sortTodayByDashboard = false,
    this.onboardingDone = false,
    this.lastRolloverYmd,
    this.lastCarryYmd,
    this.lastPrepYmd,
    List<HabitHit>? habitHits,
    Map<String, String>? habitPinnedActivity,
    Map<String, List<String>>? habitChecklistByHabitId,
    List<DayBlock>? blocks,
    List<RecurringAction>? recurringActions,
    Map<String, List<String>>? disabledBlocksByYmd,
    List<EarnedBadge>? earnedBadges,
    List<String>? skippedChallengeDates,
    this.weeklyScoreTarget = 80,
    this.notifHour = 9,
    this.notifMinute = 0,
    this.notifEnabled = true,
    this.reviewNotifHour = 21,
    this.reviewNotifMinute = 0,
    this.reviewNotifEnabled = true,
    this.streakNotifHour = 20,
    this.streakNotifMinute = 0,
    this.streakNotifEnabled = true,
    this.challengeNotifHour = 16,
    this.challengeNotifMinute = 0,
    this.challengeNotifEnabled = true,
    this.midDayNotifHour = 13,
    this.midDayNotifMinute = 0,
    this.midDayNotifEnabled = true,
    this.domainIdBackfilledOnce = false,
    // ✅ NOUVEAU
    Map<String, List<String>>? nowSkippedByYmd,
    Map<String, List<String>>? nowDoneByYmd,
    Map<String, Map<String, List<int>>>? habitChecklistDone,
    List<ActivityLog>? activityLogs,
    FilterState? filters,
    this.coursesArchivedOnce = false,
    this.linkedActivitiesMigratedOnce = false,
    this.voitureMigratedOnce = false,
    this.coursesRestoredOnce = false,
    this.coursesRestoredV2 = false,
  })  : snoozedUntil = snoozedUntil ?? <String, String>{},
        goals = goals ?? <Goal>[],
        inbox = inbox ?? <InboxItem>[],
        dayPlan = dayPlan ?? <DayPlanItem>[],
        focusTodayIds = focusTodayIds ?? <String>[],
        habitHits = habitHits ?? <HabitHit>[],
        habitPinnedActivity = habitPinnedActivity ?? <String, String>{},
        habitChecklistByHabitId =
            habitChecklistByHabitId ?? <String, List<String>>{},
        // ✅ NOUVEAU
        nowSkippedByYmd = nowSkippedByYmd ?? <String, List<String>>{},
        nowDoneByYmd = nowDoneByYmd ?? <String, List<String>>{},
        habitChecklistDone =
            habitChecklistDone ?? <String, Map<String, List<int>>>{},
        activityLogs = activityLogs ?? <ActivityLog>[],
        filters = filters ?? FilterState(),
        blocks = blocks ?? <DayBlock>[],
        recurringActions = recurringActions ?? <RecurringAction>[],
        disabledBlocksByYmd = disabledBlocksByYmd ?? <String, List<String>>{},
        earnedBadges = earnedBadges ?? <EarnedBadge>[],
        skippedChallengeDates = skippedChallengeDates ?? <String>[];

  Map<String, dynamic> toJson() => {
        'domains': domains.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'habitProgress': habitProgress.map((e) => e.toJson()).toList(),
        'lastGoalsReview': lastGoalsReview?.toIso8601String(),
        'snoozedUntil': snoozedUntil,
        'goals': goals.map((e) => e.toJson()).toList(),
        'inbox': inbox.map((e) => e.toJson()).toList(),
        'dayPlan': dayPlan.map((e) => e.toJson()).toList(),

        'lastRolloverYmd': lastRolloverYmd,
        'lastCarryYmd': lastCarryYmd,
        'lastPrepYmd': lastPrepYmd,

        'focusTodayIds': focusTodayIds,
        'sortTodayByDashboard': sortTodayByDashboard,
        'onboardingDone': onboardingDone,

        // ✅ persist
        'habitHits': habitHits.map((e) => e.toJson()).toList(),
        'habitPinnedActivity': habitPinnedActivity,

        // ✅ NOW TAB
        'nowSkippedByYmd': nowSkippedByYmd,
        'nowDoneByYmd': nowDoneByYmd,
        'habitChecklistByHabitId': habitChecklistByHabitId,
        'habitChecklistDone': habitChecklistDone,
        'activityLogs': activityLogs.map((e) => e.toJson()).toList(),
        'filters': filters.toJson(),
        'coursesArchivedOnce': coursesArchivedOnce,
        'coursesRestoredOnce': coursesRestoredOnce,
        'coursesRestoredV2': coursesRestoredV2,
        'linkedActivitiesMigratedOnce': linkedActivitiesMigratedOnce,
        'voitureMigratedOnce': voitureMigratedOnce,
        'blocks': blocks.map((e) => e.toJson()).toList(),
        'recurringActions': recurringActions.map((e) => e.toJson()).toList(),
        'disabledBlocksByYmd': disabledBlocksByYmd,
        'earnedBadges': earnedBadges.map((e) => e.toJson()).toList(),
        'skippedChallengeDates': skippedChallengeDates,
        'weeklyScoreTarget': weeklyScoreTarget,
        'notifHour': notifHour,
        'notifMinute': notifMinute,
        'notifEnabled': notifEnabled,
        'reviewNotifHour': reviewNotifHour,
        'reviewNotifMinute': reviewNotifMinute,
        'reviewNotifEnabled': reviewNotifEnabled,
        'streakNotifHour': streakNotifHour,
        'streakNotifMinute': streakNotifMinute,
        'streakNotifEnabled': streakNotifEnabled,
        'challengeNotifHour': challengeNotifHour,
        'challengeNotifMinute': challengeNotifMinute,
        'challengeNotifEnabled': challengeNotifEnabled,
        'midDayNotifHour': midDayNotifHour,
        'midDayNotifMinute': midDayNotifMinute,
        'midDayNotifEnabled': midDayNotifEnabled,
        'domainIdBackfilledOnce': domainIdBackfilledOnce,
      };

  static AppState from(Map j) {
    Map<String, List<String>> _mapSL(dynamic v) {
      if (v == null) return <String, List<String>>{};
      return (v as Map).map(
        (k, val) => MapEntry(
          k as String,
          (val as List).cast<String>(),
        ),
      );
    }

    Map<String, Map<String, List<int>>> _mapSMapListInt(dynamic v) {
      if (v == null) return <String, Map<String, List<int>>>{};

      final out = <String, Map<String, List<int>>>{};
      (v as Map).forEach((k, vv) {
        final inner = <String, List<int>>{};
        (vv as Map).forEach((kk, list) {
          inner[kk as String] =
              (list as List).map((e) => (e as num).toInt()).toList();
        });
        out[k as String] = inner;
      });
      return out;
    }

    // Helpers safe
    List<T> _list<T>(dynamic v, T Function(dynamic) mapFn) {
      if (v == null) return <T>[];
      return (v as List).map(mapFn).toList();
    }

    Map<String, String> _mapSS(dynamic v) {
      if (v == null) return <String, String>{};
      return (v as Map).map((k, val) => MapEntry(k as String, val as String));
    }

    return AppState(
      domains: _list(j['domains'], (e) => Domain.from(e)),
      activities: _list(j['activities'], (e) => Activity.from(e)),
      sessions: _list(j['sessions'], (e) => Session.from(e)),
      habitProgress: _list(j['habitProgress'], (e) => HabitProgress.from(e)),
      lastGoalsReview: j['lastGoalsReview'] == null
          ? null
          : DateTime.parse(j['lastGoalsReview']),
      snoozedUntil: _mapSS(j['snoozedUntil']),
      goals: _list(j['goals'], (e) => Goal.from(e)),
      inbox: _list(j['inbox'], (e) => InboxItem.from(e)),
      dayPlan: _list(j['dayPlan'], (e) => DayPlanItem.from(e)),
      lastRolloverYmd: j['lastRolloverYmd'] as String?,
      lastCarryYmd: j['lastCarryYmd'] as String?,
      lastPrepYmd: j['lastPrepYmd'] as String?,
      focusTodayIds:
          (j['focusTodayIds'] as List?)?.cast<String>() ?? <String>[],
      sortTodayByDashboard: (j['sortTodayByDashboard'] as bool?) ?? false,
      onboardingDone: (j['onboardingDone'] as bool?) ?? false,
      habitHits: _list(j['habitHits'], (e) => HabitHit.from(e)),
      habitPinnedActivity: _mapSS(j['habitPinnedActivity']),
      nowSkippedByYmd: _mapSL(j['nowSkippedByYmd']),
      nowDoneByYmd: _mapSL(j['nowDoneByYmd']),
      habitChecklistByHabitId: _mapSL(j['habitChecklistByHabitId']),
      habitChecklistDone: _mapSMapListInt(j['habitChecklistDone']),
      filters: FilterState.from(j['filters']),
      coursesArchivedOnce: (j['coursesArchivedOnce'] as bool?) ?? false,
      coursesRestoredOnce: (j['coursesRestoredOnce'] as bool?) ?? false,
      coursesRestoredV2: (j['coursesRestoredV2'] as bool?) ?? false,
      linkedActivitiesMigratedOnce: (j['linkedActivitiesMigratedOnce'] as bool?) ?? false,
      voitureMigratedOnce: (j['voitureMigratedOnce'] as bool?) ?? false,
      blocks: _list(j['blocks'], (e) => DayBlock.from(e)),
      recurringActions: _list(j['recurringActions'], (e) => RecurringAction.from(e)),
      disabledBlocksByYmd: _mapSL(j['disabledBlocksByYmd']),
      earnedBadges: _list(j['earnedBadges'], (e) => EarnedBadge.tryFrom(e))
          .whereType<EarnedBadge>()
          .toList(),
      skippedChallengeDates:
          (j['skippedChallengeDates'] as List?)?.cast<String>() ?? <String>[],
      weeklyScoreTarget: (j['weeklyScoreTarget'] as int?) ?? 80,
      notifHour: (j['notifHour'] as int?) ?? 9,
      notifMinute: (j['notifMinute'] as int?) ?? 0,
      notifEnabled: (j['notifEnabled'] as bool?) ?? true,
      reviewNotifHour: (j['reviewNotifHour'] as int?) ?? 21,
      reviewNotifMinute: (j['reviewNotifMinute'] as int?) ?? 0,
      reviewNotifEnabled: (j['reviewNotifEnabled'] as bool?) ?? true,
      streakNotifHour: (j['streakNotifHour'] as int?) ?? 20,
      streakNotifMinute: (j['streakNotifMinute'] as int?) ?? 0,
      streakNotifEnabled: (j['streakNotifEnabled'] as bool?) ?? true,
      challengeNotifHour: (j['challengeNotifHour'] as int?) ?? 16,
      challengeNotifMinute: (j['challengeNotifMinute'] as int?) ?? 0,
      challengeNotifEnabled: (j['challengeNotifEnabled'] as bool?) ?? true,
      midDayNotifHour: (j['midDayNotifHour'] as int?) ?? 13,
      midDayNotifMinute: (j['midDayNotifMinute'] as int?) ?? 0,
      midDayNotifEnabled: (j['midDayNotifEnabled'] as bool?) ?? true,
      domainIdBackfilledOnce: (j['domainIdBackfilledOnce'] as bool?) ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  static AppState decode(String s) {
    final t = s.trim();
    if (t.isEmpty) {
      // retourne un état vide (ou tu peux appeler ton _seedMinimal ailleurs)
      return AppState(
        domains: <Domain>[],
        activities: <Activity>[],
        sessions: <Session>[],
        habitProgress: <HabitProgress>[],
      );
    }

    try {
      return from(jsonDecode(t));
    } catch (_) {
      return AppState(
        domains: <Domain>[],
        activities: <Activity>[],
        sessions: <Session>[],
        habitProgress: <HabitProgress>[],
      );
    }
  }
}

/// Utilitaires de date
String yyyymmdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
