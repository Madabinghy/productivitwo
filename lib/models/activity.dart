part of '../models.dart';

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
  String domainId;
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

  // ---------- Progression par paliers (routines quotidiennes) ----------
  /// Cap déclaré (ex : 50 pompes/jour). `habitTarget` devient le PALIER
  /// courant, démarré bas, ajusté chaque semaine selon les hits RÉELS.
  /// Null = pas de progression — la routine garde sa cible fixe.
  int? finalTarget;

  /// Lundi (YYYY-MM-DD) de la dernière évaluation hebdo du palier — fait
  /// anti-double : une seule évaluation par semaine.
  String? stepUpdatedWeek;

  /// Si true (par défaut), la routine peut être ajustée automatiquement.
  bool autoTune;

  /// Origine de la cible de temps (`goalMin`) : "default" (valeur d'onboarding),
  /// "orion" (posée/ajustée par ORION), "user" (épinglée à la main). ORION ne
  /// touche jamais une cible "user".
  String targetSource;

  /// Métadonnées
  final DateTime createdAt;
  DateTime? lastTuneAt;

  String? linkedActivityId; // mutable : modifiable depuis la fiche routine

  int order;

  /// Code point d'une icône Material Icons (optionnel).
  int? iconCode;

  bool deleted;
  bool todayFlag; // priorité du jour (routines)

  /// Durée minuteur préférée en minutes (null = chrono libre).
  int? timerMin;

  /// Contexte horaire choisi par l'utilisateur (clé de kTimeContexts :
  /// morning/midday/afternoon/evening/meal/day/allday/any). Null = dérivé du
  /// catalogue d'archétypes (utils/routine_context.dart), lui-même optionnel.
  String? timeContext;

  /// Actions « propres » de l'activité : des TaskAction qui appartiennent
  /// directement à l'activité (sans tâche/projet). Le chrono ciblé fonctionne
  /// via Session.actionId. Persisté dans la collection `activities`.
  List<TaskAction> ownActions;

  /// Contextes GTD de l'activité/routine (@maison…) — additive. Sert au
  /// filtre « je suis » (Maintenant) et aux CTA d'enchaînement (« tu viens de
  /// finir X @maison — Y l'est aussi »).
  List<String> contexts;

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
    this.finalTarget,
    this.stepUpdatedWeek,
    this.autoTune = true,
    this.targetSource = 'default',
    DateTime? createdAt,
    this.lastTuneAt,
    this.linkedActivityId,
    this.order = 0,
    this.iconCode,
    this.deleted = false,
    this.todayFlag = false,
    this.timerMin,
    this.timeContext,
    List<TaskAction>? ownActions,
    List<String>? contexts,
  })  : id = id ?? _uuid.v4(), // <-- sans const ici
        ownActions = ownActions ?? <TaskAction>[],
        contexts = contexts ?? <String>[],
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
        'finalTarget': finalTarget,
        'stepUpdatedWeek': stepUpdatedWeek,
        'autoTune': autoTune,
        'targetSource': targetSource,
        'linkedActivityId':linkedActivityId,
        'createdAt': createdAt.toIso8601String(),
        'lastTuneAt': lastTuneAt?.toIso8601String(),
        'order': order,
        'iconCode': iconCode,
        'deleted': deleted,
        'todayFlag': todayFlag,
        'timerMin': timerMin,
        'timeContext': timeContext,
        'ownActions': ownActions.map((e) => e.toJson()).toList(),
        'contexts': contexts,
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
      domainId: j['domainId'] ?? '',
      name: j['name'] ?? '',
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
      finalTarget: (j['finalTarget'] as num?)?.toInt(),
      stepUpdatedWeek: j['stepUpdatedWeek'] as String?,
      autoTune: j['autoTune'] ?? true,
      targetSource: j['targetSource'] ?? 'default',
      linkedActivityId:j['linkedActivityId'],
      createdAt: _parseDate(j['createdAt']),
      lastTuneAt: _parseDateOrNull(j['lastTuneAt']),
      order: (j['order'] as num?)?.toInt() ?? 0,
      iconCode: (j['iconCode'] as num?)?.toInt(),
      deleted: j['deleted'] as bool? ?? false,
      todayFlag: j['todayFlag'] as bool? ?? false,
      timerMin: (j['timerMin'] as num?)?.toInt(),
      timeContext: j['timeContext'] as String?,
      ownActions: (j['ownActions'] as List?)
          ?.map((e) => TaskAction.from(e as Map))
          .toList(),
      contexts: (j['contexts'] as List?)?.cast<String>(),
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
    String? targetSource,
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
      targetSource: targetSource ?? this.targetSource,
      createdAt: createdAt ?? this.createdAt,
      lastTuneAt: lastTuneAt ?? this.lastTuneAt,
      linkedActivityId: linkedActivityId ?? null,
    );
  }

  @override
  String toString() => 'Activity($id, $name, type=$type, '
      'goalMin=$goalMin, freq=$habitFreq, target=$habitTarget, '
      'manual=$manualTarget, auto=$autoTune, src=$targetSource)';

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
        other.targetSource == targetSource &&
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
        targetSource,
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
  String? taskId; // tâche Gantt travaillée pendant cette session (lien optionnel)
  String? actionId; // action précise (TaskAction) travaillée — chrono ciblé
  Session(
      {String? id,
      required this.activityId,
      required this.startAt,
      this.endAt,
      this.taskId,
      this.actionId})
      : id = id ?? _uuid.v4();
  Duration get duration => (endAt ?? DateTime.now()).difference(startAt);
  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'taskId': taskId,
        'actionId': actionId,
      };
  static Session from(Map j) => Session(
      id: j['id'],
      activityId: j['activityId'],
      startAt: _parseDate(j['startAt']),
      endAt: _parseDateOrNull(j['endAt']),
      taskId: j['taskId'] as String?,
      actionId: j['actionId'] as String?);
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
        ts: _parseDate(j['ts']),
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
