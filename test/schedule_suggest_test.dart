import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/schedule_suggest.dart';

// ─── SUGGESTIONS DE LIEN À LA SAISIE (ajout de bloc timeline) ────────────────

void main() {
  final activities = [
    Activity(
        id: 'r1',
        name: 'Hygiène du soir',
        domainId: 'd1',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 1),
    Activity(id: 'a1', name: 'Musculation', domainId: 'd1', timerMin: 25),
    Activity(
        id: 'a2',
        name: 'Lecture',
        domainId: 'd1',
        ownActions: [TaskAction(id: 'oa1', title: 'Lire chapitre 4')]),
    Activity(id: 'del', name: 'Hygiène supprimée', domainId: 'd1')
      ..deleted = true,
  ];
  final projects = [
    Project(
        id: 'p1',
        title: 'Site web',
        startDate: DateTime(2026, 7, 1),
        status: 'active',
        createdBy: 'u1',
        tasks: [
          ProjectTask(
              id: 't1',
              title: 'Maquette accueil',
              startDate: DateTime(2026, 7, 1),
              actions: [
                TaskAction(id: 'ac1', title: 'Maquetter le header'),
                TaskAction(id: 'ac2', title: 'Header validé', done: true),
              ]),
          ProjectTask(
              id: 't2',
              title: 'Migration terminée',
              startDate: DateTime(2026, 7, 1),
              status: 'done'),
        ]),
    Project(
        id: 'p2',
        title: 'Archivé',
        startDate: DateTime(2026, 7, 1),
        status: 'archived',
        createdBy: 'u1',
        tasks: [
          ProjectTask(
              id: 't3',
              title: 'Maquette morte',
              startDate: DateTime(2026, 7, 1)),
        ]),
  ];

  List<ScheduleSuggestion> go(String q) =>
      scheduleSuggestions(q, activities: activities, projects: projects);

  test('moins de 2 caractères → rien', () {
    expect(go(''), isEmpty);
    expect(go('h'), isEmpty);
  });

  test('routine trouvée, insensible casse et accents, supprimée exclue', () {
    final s = go('hygiene');
    expect(s, hasLength(1));
    expect(s.first.kind, 'routine');
    expect(s.first.activityId, 'r1');
    expect(s.first.category, 'routine');
  });

  test('activité-temps : durée suggérée = minuteur', () {
    final s = go('muscu');
    expect(s, hasLength(1));
    expect(s.first.kind, 'activity');
    expect(s.first.category, 'personal');
    expect(s.first.durationMin, 25);
  });

  test('tâche Gantt d\'un projet actif ; done et projet archivé exclus', () {
    final s = go('maquette');
    expect(s.map((x) => x.taskId), contains('t1'));
    expect(s.map((x) => x.taskId), isNot(contains('t3')));
    expect(s.any((x) => x.title == 'Migration terminée'), isFalse);
    final task = s.firstWhere((x) => x.taskId == 't1' && x.actionId == null);
    expect(task.projectId, 'p1');
    expect(task.category, 'project');
  });

  test('action de tâche avec actionId ; action done exclue ; préfixe d\'abord',
      () {
    final s = go('maquett');
    // « Maquette accueil » (préfixe, tâche) avant « Maquetter le header »
    // (préfixe, action) — groupe tâche < action ; l'action done absente.
    expect(s.first.taskId, 't1');
    expect(s.first.actionId, isNull);
    final action = s.firstWhere((x) => x.actionId != null);
    expect(action.actionId, 'ac1');
    expect(action.taskId, 't1');
    expect(s.any((x) => x.actionId == 'ac2'), isFalse);
  });

  test('action propre d\'une activité-temps → activityId + actionId', () {
    final s = go('chapitre');
    expect(s, hasLength(1));
    expect(s.first.activityId, 'a2');
    expect(s.first.actionId, 'oa1');
    expect(s.first.kind, 'action');
  });

  test('occurrence au milieu du nom trouvée aussi (rang après préfixe)', () {
    final s = go('soir');
    expect(s, hasLength(1));
    expect(s.first.activityId, 'r1');
  });
}
