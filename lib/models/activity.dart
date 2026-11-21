part of '../models.dart';

enum ActivityRole {
  generic,
  shopping, // 👈 Courses
  focus,
  planning
}

/// Nombre d'anciennes cibles gardées par routine (une par semaine au plus : plus de deux ans).
const int kTargetLogMax = 120;

/// Une ancienne cible d'une routine : jusqu'au jour [until] (`YYYY-MM-DD`) compris, elle valait [target].
class TargetStep {
  final String until;
  final int target;
  const TargetStep(this.until, this.target);

  Map<String, dynamic> toJson() => {'until': until, 'target': target};

  static List<TargetStep> listFrom(dynamic raw) {
    if (raw is! List) return <TargetStep>[];
    final out = <TargetStep>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final until = e['until'];
      final target = (e['target'] as num?)?.toInt();
      if (until is String && until.length == 10 && target != null && target > 0) out.add(TargetStep(until, target));
    }
    out.sort((a, b) => a.until.compareTo(b.until));
    return out;
  }
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

  /// Rang manuel d'une routine dans son moment (vue Routines, 2026-10) ;
  /// null = pas encore ordonnée (après les ordonnées, par nom).
  int? routineOrder;

  bool deleted;
  bool todayFlag; // priorité du jour (routines)

  /// Durée minuteur préférée en minutes (null = chrono libre).
  int? timerMin;

  /// Contexte horaire choisi par l'utilisateur (clé de kTimeContexts :
  /// morning/midday/afternoon/evening/meal/day/allday/any). Null = dérivé du
  /// catalogue d'archétypes (utils/routine_context.dart), lui-même optionnel.
  String? timeContext;

  /// Routine RÉPARTIE (2026-10-30) : moments horaires où elle se fait
  /// (morning / midday / afternoon / evening), deux ou plus. La cible du jour
  /// est partagée entre eux (`momentShareOf`, utils/routine_moments.dart).
  /// Vide = un seul moment (le `timeContext`).
  List<String> splitMoments;

  /// Parts RÉGLÉES d'une routine répartie (2026-11-21) : moment → part de la cible du jour (« 1 au Miracle
  /// Morning, 2 le matin »). Vide = parts égales. Lues au prorata (`momentParts`, utils/routine_moments.dart) :
  /// la somme suit la cible du jour même quand elle change.
  Map<String, int> momentShares;

  /// Actions « propres » de l'activité : des TaskAction qui appartiennent
  /// directement à l'activité (sans tâche/projet). Le chrono ciblé fonctionne
  /// via Session.actionId. Persisté dans la collection `activities`.
  List<TaskAction> ownActions;

  /// Contextes GTD de l'activité/routine (@maison…) — additive. Sert au
  /// filtre « je suis » (Maintenant) et aux CTA d'enchaînement (« tu viens de
  /// finir X @maison — Y l'est aussi »).
  List<String> contexts;

  /// Routine quotidienne comptée « sur 7 jours » (2026-11-19, `utils/routine_cover.dart`) :
  /// ce qui est fait en plus couvre les jours suivants. Faux = chaque jour.
  bool rolling;

  /// Routine quotidienne « rattrapable » (2026-11-19, maquette validée « Routines rattrapables ») : un jour raté se
  /// rattrape dans les 7 jours en faisant plus un autre jour, sans avance. « Sur 7 jours » ([rolling]) rattrape aussi.
  bool catchUp;

  /// « 1 coche = n min » (2026-11-19) : minutes de chrono sur l'activité liée
  /// (`linkedActivityId`) qui valent une coche de la routine. Null = le chrono ne coche pas.
  int? minPerHit;

  /// Le chrono ne coche PAS cette routine, par choix (2026-11-20). Faux par défaut : une routine qui a une
  /// durée et qui est seule liée à son activité se coche d'office par le chrono (`chronoHitMin`,
  /// `utils/routine_cover.dart`) ; éteindre l'interrupteur de la fiche pose ce champ.
  bool chronoOff;

  /// Cible automatique (2026-11-20, `utils/auto_target.dart`) : la cible d'une routine quotidienne suit ce
  /// qui est vraiment fait (un cran de plus à 120 % sur 7 jours, un cran de moins sous 50 %). Faux par défaut.
  bool autoTarget;

  /// Anciennes cibles, de la plus ancienne à la plus récente : jusqu'au jour `until` compris, la cible valait
  /// `target`. Un jour passé est jugé avec la cible de ce jour-là ([targetOnYmd]) : une hausse automatique ne
  /// casse jamais une série déjà tenue.
  List<TargetStep> targetLog;

  /// Routine activée depuis le catalogue (2026-11-01, `catalog/routine_catalog.dart`) :
  /// sa carte porte le dessin du catalogue. Null = routine créée à la main.
  String? catalogId;

  /// RUNTIME, jamais sérialisé : les champs que portait le document lu
  /// (`Activity.from`). Un champ absent a été écrit par une version de l'app
  /// qui ne le connaît pas : ce n'est pas une valeur (`keepLocalFields`).
  Set<String>? docKeys;

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
    this.routineOrder,
    this.deleted = false,
    this.todayFlag = false,
    this.timerMin,
    this.timeContext,
    List<String>? splitMoments,
    Map<String, int>? momentShares,
    List<TaskAction>? ownActions,
    List<String>? contexts,
    this.catalogId,
    this.rolling = false,
    this.catchUp = false,
    this.autoTarget = false,
    this.chronoOff = false,
    List<TargetStep>? targetLog,
    this.minPerHit,
  })  : id = id ?? _uuid.v4(), // <-- sans const ici
        splitMoments = splitMoments ?? <String>[],
        momentShares = momentShares ?? <String, int>{},
        ownActions = ownActions ?? <TaskAction>[],
        contexts = contexts ?? <String>[],
        targetLog = targetLog ?? <TargetStep>[],
        createdAt = createdAt ?? DateTime.now();

  // -------- Helpers --------
  bool get isHabit => type == 'habit' || type == 'action';

  /// Fréquence « effective » (fallback mensuel si rien n’est défini).
  HabitFreq get effHabitFreq => habitFreq ?? HabitFreq.monthly;

  /// Cible « effective » (fallback 1 si rien n’est défini).
  int get effHabitTarget => (habitTarget ?? 1);

  /// La cible en vigueur le jour [ymd] (`YYYY-MM-DD`) : celle de l'historique si elle a changé depuis,
  /// sinon la cible d'aujourd'hui ; 1 au moins.
  int targetOnYmd(String ymd) {
    for (final s in targetLog) {
      if (s.until.compareTo(ymd) >= 0) return s.target < 1 ? 1 : s.target;
    }
    final t = habitTarget ?? 1;
    return t < 1 ? 1 : t;
  }

  /// Retient la cible actuelle comme celle en vigueur jusqu'à [untilYmd] compris, AVANT de la changer.
  /// Deux changements le même jour ne laissent qu'une trace (la cible d'avant le premier).
  void keepTargetUntil(String untilYmd) {
    if (targetLog.isNotEmpty && targetLog.last.until.compareTo(untilYmd) >= 0) return;
    targetLog.add(TargetStep(untilYmd, effHabitTarget));
    if (targetLog.length > kTargetLogMax) targetLog.removeRange(0, targetLog.length - kTargetLogMax);
  }

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
        'routineOrder': routineOrder,
        'deleted': deleted,
        'todayFlag': todayFlag,
        'timerMin': timerMin,
        'timeContext': timeContext,
        'splitMoments': splitMoments,
        if (momentShares.isNotEmpty) 'momentShares': momentShares,
        'ownActions': ownActions.map((e) => e.toJson()).toList(),
        'contexts': contexts,
        if (catalogId != null) 'catalogId': catalogId,
        'rolling': rolling,
        'catchUp': catchUp,
        'minPerHit': minPerHit,
        'autoTarget': autoTarget,
        'chronoOff': chronoOff,
        if (targetLog.isNotEmpty) 'targetLog': [for (final s in targetLog) s.toJson()],
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
      routineOrder: (j['routineOrder'] as num?)?.toInt(),
      deleted: j['deleted'] as bool? ?? false,
      todayFlag: j['todayFlag'] as bool? ?? false,
      // Une seule durée par routine (2026-11-19) : quand « le chrono coche » est réglé, sa durée est aussi
      // celle du minuteur (les deux réglages pouvaient différer avant la fusion ; celle du chrono gagne).
      timerMin: _oneDuration(j),
      timeContext: j['timeContext'] as String?,
      splitMoments: (j['splitMoments'] as List?)?.map((e) => e.toString()).toList(),
      momentShares: j['momentShares'] is Map
          ? {
              for (final e in (j['momentShares'] as Map).entries)
                if (e.value is num) e.key.toString(): (e.value as num).toInt(),
            }
          : null,
      ownActions: (j['ownActions'] as List?)
          ?.map((e) => TaskAction.from(e as Map))
          .toList(),
      contexts: (j['contexts'] as List?)?.cast<String>(),
      catalogId: j['catalogId'] as String?,
      rolling: j['rolling'] as bool? ?? false,
      catchUp: j['catchUp'] as bool? ?? false,
      minPerHit: (j['minPerHit'] as num?)?.toInt(),
      autoTarget: j['autoTarget'] as bool? ?? false,
      chronoOff: j['chronoOff'] as bool? ?? false,
      targetLog: TargetStep.listFrom(j['targetLog']),
    )..docKeys = {for (final k in j.keys) k.toString()};
  }

  static int? _oneDuration(Map j) {
    final per = (j['minPerHit'] as num?)?.toInt();
    if ((j['type'] ?? 'time') == 'habit' && per != null && per > 0) return per;
    return (j['timerMin'] as num?)?.toInt();
  }

  /// La durée d'une fois d'une routine : le temps du ⏱ et, si le chrono coche, le temps d'une coche.
  int? get onceMin => (minPerHit ?? 0) > 0 ? minPerHit : ((timerMin ?? 0) > 0 ? timerMin : null);

  /// Règle la durée d'une fois (null = aucune) : le minuteur, et la coche du chrono si elle est allumée.
  void setOnceMin(int? minutes) {
    final m = (minutes ?? 0) > 0 ? minutes : null;
    timerMin = m;
    if (minPerHit != null) minPerHit = m;
  }

  /// Allume ou éteint « le chrono coche » : il compte à la durée d'une fois. Éteint, c'est un choix
  /// ([chronoOff]) : la routine ne se cochera pas d'office, même seule sur son activité.
  void setChronoHits(bool on) {
    final m = onceMin;
    minPerHit = on ? m : null;
    chronoOff = !on;
    // Éteindre garde la durée d'une fois (le ⏱), qui vivait peut-être seulement dans la coche du chrono.
    if (!on && m != null) timerMin = m;
  }

  /// Fusion au lancement (2026-11-19, bug user : « Sur 7 jours » réglé puis
  /// perdu) : le serveur gagne, SAUF pour les champs que son document ne porte
  /// pas — il a été réécrit par une version plus ancienne de l'app, qui pousse
  /// la routine entière sans les champs qu'elle ne connaît pas. Pour ceux-là,
  /// l'appareil garde sa valeur (et la renvoie au serveur au push qui suit).
  static Activity keepLocalFields(Activity local, Activity remote) {
    final keys = remote.docKeys;
    if (keys == null) return remote;
    final mine = local.toJson();
    final missing = [for (final k in mine.keys) if (!keys.contains(k)) k];
    if (missing.isEmpty) return remote;
    final json = remote.toJson();
    for (final k in missing) {
      json[k] = mine[k];
    }
    return Activity.from(json);
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
      catalogId: catalogId,
      rolling: rolling,
      catchUp: catchUp,
      minPerHit: minPerHit,
      autoTarget: autoTarget,
      chronoOff: chronoOff,
      targetLog: [...targetLog],
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
  // Suppression douce (MCP delete_sessions / update_session, ou autre appareil) :
  // la session sort de l'état local au merge, puis le doc est hard-deleté.
  bool deleted;
  Session(
      {String? id,
      required this.activityId,
      required this.startAt,
      this.endAt,
      this.taskId,
      this.actionId,
      this.deleted = false})
      : id = id ?? _uuid.v4();
  Duration get duration => (endAt ?? DateTime.now()).difference(startAt);
  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        'taskId': taskId,
        'actionId': actionId,
        if (deleted) 'deleted': true,
      };
  static Session from(Map j) => Session(
      id: j['id'],
      activityId: j['activityId'],
      startAt: _parseDate(j['startAt']),
      endAt: _parseDateOrNull(j['endAt']),
      taskId: j['taskId'] as String?,
      actionId: j['actionId'] as String?,
      deleted: j['deleted'] == true);
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
        // Heure locale : un hit écrit par le serveur (widget, Siri, Claude) est en UTC (« …Z ») ;
        // la journée vécue se lit sur l'heure de l'horloge.
        ts: _parseDate(j['ts']).toLocal(),
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
