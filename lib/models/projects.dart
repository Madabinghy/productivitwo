part of '../models.dart';

// ─── GESTION DE PROJETS (Gantt) ──────────────────────────────────────────────
//
// TaskAction : action opérationnelle liée à une tâche Gantt.

class TaskAction {
  String id;
  String title;
  bool done;
  DateTime? doneAt;
  DateTime createdAt;
  String? linkedActivityId; // activité-temps liée → chrono ciblé sur cette action

  TaskAction({
    String? id,
    required this.title,
    this.done = false,
    this.doneAt,
    DateTime? createdAt,
    this.linkedActivityId,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'linkedActivityId': linkedActivityId,
      };

  static TaskAction from(Map j) => TaskAction(
        id: j['id'] ?? _uuid.v4(),
        title: j['title'] ?? '',
        done: j['done'] as bool? ?? (j['doneAt'] != null),
        doneAt: j['doneAt'] != null ? DateTime.tryParse(j['doneAt']) : null,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt']) ?? DateTime.now()
            : DateTime.now(),
        linkedActivityId: j['linkedActivityId'] as String?,
      );
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
  })  : id = id ?? _uuid.v4(),
        actions = actions ?? [];

  int get stepsDone => actions.where((a) => a.done).length;
  int get stepsTotal => actions.length;

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
  List<ProjectPhase> phases;
  List<ProjectTask> tasks;
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
    List<ProjectPhase>? phases,
    List<ProjectTask>? tasks,
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
        tasks = tasks ?? [];

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
        'phases': phases.map((p) => p.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
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
        phases: (j['phases'] as List?)?.map((p) => ProjectPhase.from(p)).toList() ?? [],
        tasks: (j['tasks'] as List?)?.map((t) => ProjectTask.from(t)).toList() ?? [],
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
