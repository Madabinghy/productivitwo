part of '../models.dart';

// ─── DÉROULÉS RÉUTILISABLES (session_templates) ──────────────────────────────
//
// Un déroulé = la playlist ORDONNÉE d'une séance sur UNE activité-temps
// (« Séance A — haut du corps » sur Musculation, « Couper les herbes » sur
// Jardin). Le chrono parent trace le temps ; chaque étape est soit un simple
// item à cocher (avec checklist optionnelle), soit un POINTEUR vers une
// routine (compteur − / +, palier, streak — l'état vit chez la routine).
// Collection : users/{uid}/session_templates/{id}.

class SessionStep {
  String id;
  String title;
  String kind; // 'check' | 'routine'
  String? routineId; // kind == 'routine' → la routine visée
  List<String> checklist; // sous-items d'une étape simple (« ranger le matos »)

  SessionStep({
    String? id,
    required this.title,
    this.kind = 'check',
    this.routineId,
    List<String>? checklist,
  })  : id = id ?? _uuid.v4(),
        checklist = checklist ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'routineId': routineId,
        'checklist': checklist,
      };

  static SessionStep from(Map<String, dynamic> j) => SessionStep(
        id: j['id'] as String?,
        title: (j['title'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? 'check',
        routineId: j['routineId'] as String?,
        checklist:
            (j['checklist'] as List?)?.map((e) => e.toString()).toList(),
      );
}

class SessionTemplate {
  String id;
  String title;
  String activityId; // l'activité-temps propriétaire du chrono
  List<SessionStep> steps;
  bool archived; // soft-delete, jamais de delete() direct
  DateTime createdAt;

  SessionTemplate({
    String? id,
    required this.title,
    required this.activityId,
    List<SessionStep>? steps,
    this.archived = false,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        steps = steps ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'activityId': activityId,
        'steps': steps.map((s) => s.toJson()).toList(),
        'archived': archived,
        'createdAt': createdAt.toIso8601String(),
      };

  static SessionTemplate from(Map<String, dynamic> j) => SessionTemplate(
        id: j['id'] as String?,
        title: (j['title'] as String?) ?? '',
        activityId: (j['activityId'] as String?) ?? '',
        steps: (j['steps'] as List?)
            ?.map((e) => SessionStep.from(Map<String, dynamic>.from(e as Map)))
            .toList(),
        archived: j['archived'] == true,
        createdAt: _parseDate(j['createdAt']),
      );
}
