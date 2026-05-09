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

  // ✅ NEW
  List<ChecklistItem> checklist;

  DayPlanItem({
    required this.id,
    required this.kind,
    this.refId,
    this.domainId,
    this.activityId,
    this.habitId,
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
class Goal {
  String id, domainId, title;
  String status; // 'active' par défaut
  String? activityId; // activité support (optionnel)
  String? nextAction; // une seule "prochaine action"
  String? context; // ex: "maison", "travail" (optionnel)
  DateTime createdAt;
  DateTime? doneAt;

  int? effortEstimateMin; // estimation totale en minutes (ex: 600 = 10 h)
  int? stepsPlanned; // nb d'étapes prévues (ex: 5 chapitres)
  int stepsDone; // nb d'étapes réalisées
  DateTime? dueDate; // (optionnel) pour plus tard

  Goal({
    String? id,
    required this.domainId,
    required this.title,
    this.status = 'active',
    this.activityId,
    this.nextAction,
    this.context,
    DateTime? createdAt,
    this.doneAt,
    this.effortEstimateMin,
    this.stepsPlanned,
    this.stepsDone = 0,
    this.dueDate,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'title': title,
        'status': status,
        'activityId': activityId,
        'nextAction': nextAction,
        'context': context,
        'createdAt': createdAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'effortEstimateMin': effortEstimateMin,
        'stepsPlanned': stepsPlanned,
        'stepsDone': stepsDone,
        'dueDate': dueDate?.toIso8601String(),
      };

  static Goal from(Map j) => Goal(
        id: j['id'],
        domainId: j['domainId'],
        title: j['title'],
        status: j['status'] ?? 'active',
        activityId: j['activityId'],
        nextAction: j['nextAction'],
        context: j['context'],
        createdAt: DateTime.parse(j['createdAt']),
        doneAt: j['doneAt'] != null ? DateTime.parse(j['doneAt']) : null,
        effortEstimateMin: j['effortEstimateMin'],
        stepsPlanned: j['stepsPlanned'],
        stepsDone: (j['stepsDone'] ?? 0),
        dueDate: j['dueDate'] != null ? DateTime.parse(j['dueDate']) : null,
      );
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
  bool linkedActivitiesMigratedOnce;

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
    this.lastRolloverYmd,
    this.lastCarryYmd,
    this.lastPrepYmd,
    List<HabitHit>? habitHits,
    Map<String, String>? habitPinnedActivity,
    Map<String, List<String>>? habitChecklistByHabitId,
    // ✅ NOUVEAU
    Map<String, List<String>>? nowSkippedByYmd,
    Map<String, List<String>>? nowDoneByYmd,
    Map<String, Map<String, List<int>>>? habitChecklistDone,
    List<ActivityLog>? activityLogs,
    FilterState? filters,
    this.coursesArchivedOnce = false,
    this.linkedActivitiesMigratedOnce = false,
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
        filters = filters ?? FilterState();

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
        'linkedActivitiesMigratedOnce': linkedActivitiesMigratedOnce,
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
      habitHits: _list(j['habitHits'], (e) => HabitHit.from(e)),
      habitPinnedActivity: _mapSS(j['habitPinnedActivity']),
      nowSkippedByYmd: _mapSL(j['nowSkippedByYmd']),
      nowDoneByYmd: _mapSL(j['nowDoneByYmd']),
      habitChecklistByHabitId: _mapSL(j['habitChecklistByHabitId']),
      habitChecklistDone: _mapSMapListInt(j['habitChecklistDone']),
      filters: FilterState.from(j['filters']),
      coursesArchivedOnce: (j['coursesArchivedOnce'] as bool?) ?? false,
      linkedActivitiesMigratedOnce: (j['linkedActivitiesMigratedOnce'] as bool?) ?? false,
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
