part of '../models.dart';

// ─── GESTION DE PROJETS (Gantt) ──────────────────────────────────────────────
//
// TaskAction : action opérationnelle liée à une tâche Gantt.

/// Contextes GTD par défaut (« où/avec quoi » une action est réalisable).
/// Les contextes personnalisés vivent dans `users/{uid}/data/meta.customContexts`.
const List<String> kDefaultGtdContexts = [
  '@maison',
  '@bureau',
  '@ordinateur',
  '@courses',
  '@extérieur',
  '@téléphone',
];

/// Durée estimée d'une tâche sans `estimatedMin` (planificateur de la semaine).
const int kDefaultTaskEstimatedMin = 45;

/// Lit une durée estimée en minutes : entier > 0, sinon null (absent, 0,
/// négatif ou type inattendu → « pas d'estimation »).
int? _parseEstimatedMin(dynamic raw) {
  final v = raw is num ? raw.toInt() : int.tryParse('$raw');
  return v != null && v > 0 ? v : null;
}

/// Micro-action d'une checklist (3ᵉ niveau : projet → tâche → action → item).
/// Cochée pendant un bloc du programme ; le dernier item coché marque
/// l'action faite (règle appliquée par l'UI et par `mark_checklist_item`).
class ChecklistItem {
  String id;
  String title;
  bool done;
  DateTime? doneAt;

  ChecklistItem({String? id, required this.title, this.done = false, this.doneAt})
      : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
      };

  /// Tolère un item réduit à son titre (string).
  static ChecklistItem from(dynamic j) {
    if (j is! Map) return ChecklistItem(title: j.toString());
    return ChecklistItem(
      id: j['id'] as String? ?? _uuid.v4(),
      title: (j['title'] ?? '').toString(),
      done: j['done'] == true,
      doneAt: j['doneAt'] is String ? DateTime.tryParse(j['doneAt']) : null,
    );
  }
}

class TaskAction {
  String id;
  String title;
  bool done;
  DateTime? doneAt;
  DateTime createdAt;
  String? linkedActivityId; // activité-temps liée → chrono ciblé sur cette action
  String? context; // contexte GTD principal (@maison…) — compat lecteurs mono
  // Multi-contextes GTD : une action peut être réalisable dans PLUSIEURS
  // contextes (@ordinateur ET @bureau). `context` reste le principal (1er).
  List<String> contexts;
  int? estimatedMin; // durée estimée ; null = passe tous les filtres « J'ai… »
  List<ChecklistItem> checklist; // micro-actions ; vide = pas de checklist

  TaskAction({
    String? id,
    required this.title,
    this.done = false,
    this.doneAt,
    DateTime? createdAt,
    this.linkedActivityId,
    this.context,
    List<String>? contexts,
    this.estimatedMin,
    List<ChecklistItem>? checklist,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        contexts = contexts ?? [],
        checklist = checklist ?? [];

  int get checklistDone => checklist.where((c) => c.done).length;
  int get checklistTotal => checklist.length;

  /// Tous les contextes de l'action (multi + legacy mono), sans doublon.
  /// C'est LE lecteur unique des contextes : ne jamais lire `context` seul.
  Set<String> get allContexts =>
      {...contexts, if (context != null && context!.isNotEmpty) context!};

  /// Contexte principal (badge, étiquette du programme) : `contexts[0]`,
  /// repli sur le legacy `context`.
  String? get primaryContext => contexts.isNotEmpty
      ? contexts.first
      : (context != null && context!.isNotEmpty ? context : null);

  /// Pose la liste des contextes (le principal = premier, pour les lecteurs
  /// mono : badges, ORION, groupement de la vue Demain).
  void setContexts(List<String> list) {
    contexts = List.of(list);
    context = list.isEmpty ? null : list.first;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'linkedActivityId': linkedActivityId,
        'context': context,
        'contexts': contexts,
        'estimatedMin': estimatedMin,
        'checklist': checklist.map((c) => c.toJson()).toList(),
      };

  static TaskAction from(Map j) {
    // Migration à la lecture : les deux champs se complètent (une action MCP
    // n'avait que `contexts`, une action app ancienne que `context`) ; la
    // prochaine sauvegarde persiste la forme complète.
    final legacy = (j['context'] as String?)?.trim();
    final multi = ((j['contexts'] as List?)?.map((e) => e.toString()).toList() ?? [])
        .where((c) => c.trim().isNotEmpty)
        .toList();
    if (multi.isEmpty && legacy != null && legacy.isNotEmpty) multi.add(legacy);
    return TaskAction(
      id: j['id'] ?? _uuid.v4(),
      title: j['title'] ?? '',
      done: j['done'] as bool? ?? (j['doneAt'] != null),
      doneAt: j['doneAt'] != null ? DateTime.tryParse(j['doneAt']) : null,
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      linkedActivityId: j['linkedActivityId'] as String?,
      context: multi.isNotEmpty ? multi.first : null,
      contexts: multi,
      estimatedMin: _parseEstimatedMin(j['estimatedMin']),
      checklist: (j['checklist'] as List?)?.map(ChecklistItem.from).toList() ?? [],
    );
  }
}

//
// Ces modèles sont indépendants de AppState : ils sont chargés à la demande
// (vue web Gantt, section Projets mobile) via ProjectSync, pas au démarrage.
//
// Hiérarchie : StrategicObjective → Project → ProjectTask
//              ApiToken  (authentification API externe)

class ProjectPhase {
  String id;
  String label;
  String? color;
  DateTime startDate;
  DateTime endDate;

  ProjectPhase({
    String? id,
    required this.label,
    this.color,
    required this.startDate,
    required this.endDate,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'color': color,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
      };

  static ProjectPhase from(Map j) => ProjectPhase(
        id: j['id'],
        label: j['label'] ?? '',
        color: j['color'],
        startDate: _parseDate(j['startDate']),
        endDate: _parseDate(j['endDate']),
      );
}

class ProjectTask {
  String id;
  String title;
  String? description;
  String? phaseId;
  String? groupLabel;
  DateTime startDate;
  DateTime? endDate;
  bool isMilestone;
  String? color;
  String? barLabel;
  String status; // pending | done | skipped
  List<TaskAction> actions; // détail opérationnel
  bool todayFlag; // priorité du jour
  int? estimatedMin; // durée estimée ; null = kDefaultTaskEstimatedMin
  /// Intervention (séance datée) dont cette tâche fait partie, et son rôle :
  /// `prep` (📝 Préparer) · `session` (🎯 jalon) · `closure` (✅ Clôturer).
  /// Posés par le serveur (add_intervention / migrate_interventions) ; null =
  /// tâche ordinaire. Toujours ré-écrits tels quels (round-trip).
  String? interventionId;
  String? interventionRole;

  ProjectTask({
    String? id,
    required this.title,
    this.description,
    this.phaseId,
    this.groupLabel,
    required this.startDate,
    this.endDate,
    this.isMilestone = false,
    this.color,
    this.barLabel,
    this.status = 'pending',
    List<TaskAction>? actions,
    this.todayFlag = false,
    this.estimatedMin,
    this.interventionId,
    this.interventionRole,
  })  : id = id ?? _uuid.v4(),
        actions = actions ?? [];

  int get stepsDone => actions.where((a) => a.done).length;
  int get stepsTotal => actions.length;

  /// Durée à planifier : l'estimation saisie, sinon 45 min.
  int get plannedMin => estimatedMin ?? kDefaultTaskEstimatedMin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'phaseId': phaseId,
        'groupLabel': groupLabel,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'isMilestone': isMilestone,
        'color': color,
        'barLabel': barLabel,
        'status': status,
        'actions': actions.map((a) => a.toJson()).toList(),
        'todayFlag': todayFlag,
        'estimatedMin': estimatedMin,
        if (interventionId != null) 'interventionId': interventionId,
        if (interventionRole != null) 'interventionRole': interventionRole,
      };

  static ProjectTask from(Map j) => ProjectTask(
        id: j['id'],
        title: j['title'] ?? '',
        description: j['description'],
        phaseId: j['phaseId'],
        groupLabel: j['groupLabel'],
        startDate: _parseDate(j['startDate']),
        endDate: _parseDateOrNull(j['endDate']),
        isMilestone: j['isMilestone'] as bool? ?? false,
        color: j['color'],
        barLabel: j['barLabel'],
        status: j['status'] ?? 'pending',
        actions: (j['actions'] as List?)
                ?.map((a) => a is Map
                    ? TaskAction.from(a)
                    : TaskAction(title: a.toString()))
                .toList() ??
            [],
        todayFlag: j['todayFlag'] as bool? ?? false,
        estimatedMin: _parseEstimatedMin(j['estimatedMin']),
        interventionId: j['interventionId'] as String?,
        interventionRole: j['interventionRole'] as String?,
      );
}

/// Intervention : séance datée (cours, journée client, module) portée par le
/// projet — date + créneau + lieu + bilan. Ses trois tâches sont des
/// `ProjectTask` ordinaires taguées `interventionId` / `interventionRole`.
/// Créée par le serveur (`add_intervention`), lue ici ; l'app ré-écrit la
/// liste telle quelle dans `Project.toJson` (ne jamais la perdre).
class ProjectIntervention {
  String id;
  String title;
  DateTime date;
  String startTime; // HH:mm
  String endTime; // HH:mm
  String? place;
  String? templateId;
  String? docUrl;
  String status; // planned | done | cancelled
  String? debriefText;
  List<ChecklistItem> carryOver;
  DateTime? debriefAt;
  final Map<String, dynamic> _raw;

  ProjectIntervention({
    String? id,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.place,
    this.templateId,
    this.docUrl,
    this.status = 'planned',
    this.debriefText,
    List<ChecklistItem>? carryOver,
    this.debriefAt,
    Map<String, dynamic>? raw,
  })  : id = id ?? _uuid.v4(),
        carryOver = carryOver ?? [],
        _raw = raw ?? {};

  String get ymd =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  int get slotMin {
    int m(String hm) {
      final p = hm.split(':');
      return p.length == 2 ? (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0) : 0;
    }
    final d = m(endTime) - m(startTime);
    return d > 0 ? d : 0;
  }

  Map<String, dynamic> toJson() => {
        ..._raw,
        'id': id,
        'title': title,
        'date': ymd,
        'startTime': startTime,
        'endTime': endTime,
        'place': place,
        'templateId': templateId,
        'docUrl': docUrl,
        'status': status,
        'debriefText': debriefText,
        'carryOver': carryOver.map((c) => c.toJson()).toList(),
        'debriefAt': debriefAt?.toIso8601String(),
      };

  static ProjectIntervention from(Map j) => ProjectIntervention(
        id: j['id'],
        title: j['title'] ?? '',
        date: _parseDate(j['date']),
        startTime: j['startTime'] ?? '',
        endTime: j['endTime'] ?? '',
        place: j['place'],
        templateId: j['templateId'],
        docUrl: j['docUrl'],
        status: j['status'] ?? 'planned',
        debriefText: j['debriefText'],
        carryOver: (j['carryOver'] as List?)
                ?.whereType<Map>()
                .map((c) => ChecklistItem.from(c))
                .toList() ??
            [],
        debriefAt: _parseDateOrNull(j['debriefAt']),
        raw: Map<String, dynamic>.from(j),
      );
}

/// Provenance d'un projet auto-créé par ORION : l'idée inbox qui l'a nourri.
class ProjectOriginIdea {
  final String text;
  final String date; // YYYY-MM-DD
  const ProjectOriginIdea({required this.text, required this.date});

  Map<String, dynamic> toJson() => {'text': text, 'date': date};
  static ProjectOriginIdea from(Map j) =>
      ProjectOriginIdea(text: j['text'] ?? '', date: j['date'] ?? '');
}

class Project {
  String id;
  String title;
  String? description;
  String? strategicObjectiveId;
  String? domainId;
  /// Projet parent (null = projet racine). Hiérarchie en adjacency list —
  /// l'arbre est reconstruit côté client. Rétro-compatible : absent = racine.
  String? parentProjectId;
  DateTime startDate;
  DateTime? endDate;
  String status; // draft | active | done | archived
  /// Projet EN PAUSE (GTD « someday/maybe » léger) : reste actif mais ses
  /// actions sortent des listes de contextes, du coach et de la planification.
  bool paused;
  /// Activité-temps liée : les actions du projet héritent de ce chrono
  /// (sauf lien propre `TaskAction.linkedActivityId`) et remontent dans
  /// « Possible maintenant » quand cette activité tourne.
  String? linkedActivityId;
  List<ProjectPhase> phases;
  List<ProjectTask> tasks;
  /// Séances datées du projet (voir [ProjectIntervention]).
  List<ProjectIntervention> interventions;
  String createdBy; // uid Firebase
  String sourceType; // manual | claude_api | coach
  /// Origine fonctionnelle : "user" (manuel/MCP) ou "orion" (auto-créé depuis
  /// les idées) — pilote le style visuel distinct.
  String source;
  /// Idées inbox qui ont donné naissance / nourri ce projet (effet « wow »).
  List<ProjectOriginIdea> originIdeas;
  DateTime createdAt;
  DateTime? updatedAt;

  Project({
    String? id,
    required this.title,
    this.description,
    this.strategicObjectiveId,
    this.domainId,
    this.parentProjectId,
    required this.startDate,
    this.endDate,
    this.status = 'active',
    this.paused = false,
    this.linkedActivityId,
    List<ProjectPhase>? phases,
    List<ProjectTask>? tasks,
    List<ProjectIntervention>? interventions,
    required this.createdBy,
    this.sourceType = 'manual',
    this.source = 'user',
    List<ProjectOriginIdea>? originIdeas,
    DateTime? createdAt,
    this.updatedAt,
  })  : id = id ?? _uuid.v4(),
        originIdeas = originIdeas ?? [],
        createdAt = createdAt ?? DateTime.now(),
        phases = phases ?? [],
        tasks = tasks ?? [],
        interventions = interventions ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'strategicObjectiveId': strategicObjectiveId,
        'domainId': domainId,
        'parentProjectId': parentProjectId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'status': status,
        'paused': paused,
        'linkedActivityId': linkedActivityId,
        'phases': phases.map((p) => p.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'interventions': interventions.map((i) => i.toJson()).toList(),
        'createdBy': createdBy,
        'sourceType': sourceType,
        'source': source,
        'originIdeas': originIdeas.map((o) => o.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static Project from(Map j) => Project(
        id: j['id'],
        title: j['title'] ?? '',
        description: j['description'],
        strategicObjectiveId: j['strategicObjectiveId'],
        domainId: j['domainId'],
        parentProjectId: j['parentProjectId'],
        startDate: _parseDate(j['startDate']),
        endDate: _parseDateOrNull(j['endDate']),
        status: j['status'] ?? 'active',
        paused: j['paused'] == true,
        linkedActivityId: j['linkedActivityId'] as String?,
        phases: (j['phases'] as List?)?.map((p) => ProjectPhase.from(p)).toList() ?? [],
        tasks: (j['tasks'] as List?)?.map((t) => ProjectTask.from(t)).toList() ?? [],
        interventions: (j['interventions'] as List?)
                ?.whereType<Map>()
                .map((i) => ProjectIntervention.from(i))
                .toList() ??
            [],
        createdBy: j['createdBy'] ?? '',
        sourceType: j['sourceType'] ?? 'manual',
        source: j['source'] ?? 'user',
        originIdeas: (j['originIdeas'] as List?)
                ?.map((o) => ProjectOriginIdea.from(o as Map))
                .toList() ??
            [],
        createdAt: _parseDate(j['createdAt']),
        updatedAt: _parseDateOrNull(j['updatedAt']),
      );
}

/// Engagement de temps hebdo sur une activité `time` (moyen opérationnel d'un objectif).
class ObjectiveTimeCommitment {
  String activityId;
  int weeklyMin; // minutes / semaine

  ObjectiveTimeCommitment({required this.activityId, required this.weeklyMin});

  Map<String, dynamic> toJson() => {
        'activityId': activityId,
        'weeklyMin': weeklyMin,
      };

  static ObjectiveTimeCommitment from(Map j) => ObjectiveTimeCommitment(
        activityId: j['activityId'] ?? '',
        weeklyMin: (j['weeklyMin'] as num?)?.toInt() ?? 0,
      );
}

/// Engagement sur une routine — la cible vit déjà sur `habitFreq`/`habitTarget`.
class ObjectiveRoutineCommitment {
  String activityId;

  ObjectiveRoutineCommitment({required this.activityId});

  Map<String, dynamic> toJson() => {'activityId': activityId};

  static ObjectiveRoutineCommitment from(Map j) =>
      ObjectiveRoutineCommitment(activityId: j['activityId'] ?? '');
}

class StrategicObjective {
  String id;
  String title;
  String? description;
  String? domainId;
  String? kpiTarget; // ex: "100 payants · MRR 500€"
  String? horizonLabel; // ex: "3 mois", "Q2 2026"
  DateTime? startDate;
  DateTime? endDate;
  String status; // active | done | archived
  List<String> projectIds;
  List<ObjectiveTimeCommitment> timeCommitments;
  List<ObjectiveRoutineCommitment> routineCommitments;
  DateTime createdAt;
  DateTime? updatedAt;

  StrategicObjective({
    String? id,
    required this.title,
    this.description,
    this.domainId,
    this.kpiTarget,
    this.horizonLabel,
    this.startDate,
    this.endDate,
    this.status = 'active',
    List<String>? projectIds,
    List<ObjectiveTimeCommitment>? timeCommitments,
    List<ObjectiveRoutineCommitment>? routineCommitments,
    DateTime? createdAt,
    this.updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now(),
        projectIds = projectIds ?? [],
        timeCommitments = timeCommitments ?? [],
        routineCommitments = routineCommitments ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'domainId': domainId,
        'kpiTarget': kpiTarget,
        'horizonLabel': horizonLabel,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'status': status,
        'projectIds': projectIds,
        'timeCommitments': timeCommitments.map((c) => c.toJson()).toList(),
        'routineCommitments':
            routineCommitments.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static StrategicObjective from(Map j) => StrategicObjective(
        id: j['id'],
        title: j['title'] ?? '',
        description: j['description'],
        domainId: j['domainId'],
        kpiTarget: j['kpiTarget'],
        horizonLabel: j['horizonLabel'],
        startDate: _parseDateOrNull(j['startDate']),
        endDate: _parseDateOrNull(j['endDate']),
        status: j['status'] ?? 'active',
        projectIds: (j['projectIds'] as List?)?.cast<String>() ?? [],
        timeCommitments: (j['timeCommitments'] as List?)
                ?.map((c) => ObjectiveTimeCommitment.from(c as Map))
                .toList() ??
            [],
        routineCommitments: (j['routineCommitments'] as List?)
                ?.map((c) => ObjectiveRoutineCommitment.from(c as Map))
                .toList() ??
            [],
        createdAt: _parseDate(j['createdAt']),
        updatedAt: _parseDateOrNull(j['updatedAt']),
      );
}
