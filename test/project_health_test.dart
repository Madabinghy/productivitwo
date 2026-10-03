import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

final _now = DateTime(2026, 9, 30, 15); // mercredi

ProjectTask _task(String id, String start,
        {String? end, String status = 'pending', List<TaskAction>? actions}) =>
    ProjectTask(
        id: id,
        title: 'Tâche $id',
        startDate: DateTime.parse(start),
        endDate: end == null ? null : DateTime.parse(end),
        status: status,
        actions: actions);

Project _proj(List<ProjectTask> tasks,
        {DateTime? end, List<ProjectPhase>? phases, DateTime? createdAt, String? linked}) =>
    Project(
        id: 'p',
        title: 'Refonte web',
        startDate: DateTime(2026, 9, 1),
        endDate: end,
        createdBy: 'u',
        tasks: tasks,
        phases: phases,
        createdAt: createdAt ?? DateTime(2026, 9, 1),
        linkedActivityId: linked);

Session _session(DateTime start, int min, {String? taskId, String activityId = 'act'}) =>
    Session(activityId: activityId, startAt: start, endAt: start.add(Duration(minutes: min)), taskId: taskId);

void main() {
  test('ganttOrder : par date de début, stable à égalité', () {
    final p = _proj([_task('b', '2026-09-10'), _task('c', '2026-09-05'), _task('a', '2026-09-10')]);
    expect(ganttOrder(p).map((t) => t.id).toList(), ['c', 'b', 'a']);
  });

  test('phaseSections : phases par date de début, orphelines dans « Sans phase »', () {
    final ph1 = ProjectPhase(id: 'p1', label: 'Cadrage', startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 9, 15));
    final ph2 = ProjectPhase(id: 'p2', label: 'Build', startDate: DateTime(2026, 9, 16), endDate: DateTime(2026, 10, 30));
    final a = _task('a', '2026-09-20')..phaseId = 'p2';
    final b = _task('b', '2026-09-02')..phaseId = 'p1';
    final c = _task('c', '2026-09-03')..phaseId = 'p1';
    final loose = _task('x', '2026-09-05')..phaseId = 'disparue';
    final p = _proj([a, loose, c, b], phases: [ph2, ph1]);
    final sections = phaseSections(p);
    expect(sections.map((s) => s.phase?.id).toList(), ['p1', 'p2', null]);
    expect(sections[0].tasks.map((t) => t.id).toList(), ['b', 'c']);
    expect(sections[1].tasks.map((t) => t.id).toList(), ['a']);
    expect(sections[2].tasks.map((t) => t.id).toList(), ['x']);
  });

  test('phaseSections : sans phase → une seule section nulle, même vide', () {
    expect(phaseSections(_proj([])).map((s) => s.phase).toList(), [null]);
    final withPhase = _proj([_task('a', '2026-09-02')..phaseId = 'p1'],
        phases: [ProjectPhase(id: 'p1', label: 'A', startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 9, 9))]);
    expect(phaseSections(withPhase).length, 1); // pas de « Sans phase » vide
  });

  test('isTaskOverdue : ouverte et échéance passée uniquement', () {
    expect(isTaskOverdue(_task('a', '2026-09-01', end: '2026-09-29'), _now), isTrue);
    expect(isTaskOverdue(_task('a', '2026-09-01', end: '2026-09-30'), _now), isFalse); // le jour même
    expect(isTaskOverdue(_task('a', '2026-09-01', end: '2026-09-29', status: 'done'), _now), isFalse);
    expect(isTaskOverdue(_task('a', '2026-09-01', end: '2026-09-29', status: 'skipped'), _now), isFalse);
    expect(isTaskOverdue(_task('a', '2026-09-01'), _now), isFalse); // sans échéance
  });

  test('taskProgress ignore les skipped', () {
    final p = _proj([
      _task('1', '2026-09-01', status: 'done'),
      _task('2', '2026-09-01', status: 'skipped'),
      _task('3', '2026-09-01'),
    ]);
    expect(taskProgress(p), (done: 1, total: 2));
  });

  test('currentPhase : contient aujourd\'hui, sinon null', () {
    final p = _proj([], phases: [
      ProjectPhase(label: 'Cadrage', startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 9, 15)),
      ProjectPhase(label: 'Build', startDate: DateTime(2026, 9, 16), endDate: DateTime(2026, 10, 10)),
    ]);
    expect(currentPhase(p, _now)!.label, 'Build');
    expect(currentPhase(p, DateTime(2026, 11, 1)), isNull);
  });

  test('nextAction : première action ouverte de la première tâche ouverte', () {
    final p = _proj([
      _task('later', '2026-09-20', actions: [TaskAction(title: 'plus tard')]),
      _task('done', '2026-09-01', status: 'done', actions: [TaskAction(title: 'x')]),
      _task('first', '2026-09-05', actions: [
        TaskAction(title: 'faite', done: true),
        TaskAction(title: 'suivante'),
      ]),
    ]);
    final n = nextAction(p)!;
    expect(n.task.id, 'first');
    expect(n.action.title, 'suivante');
    expect(nextAction(_proj([_task('t', '2026-09-05')])), isNull);
  });

  test('minutesLast7Days : par tâche ou activité liée, tronqué à 7 jours', () {
    final p = _proj([_task('t1', '2026-09-01')], linked: 'act');
    final sessions = [
      _session(_now.subtract(const Duration(days: 1)), 60, taskId: 't1', activityId: 'other'),
      _session(_now.subtract(const Duration(days: 2)), 30), // activité liée
      _session(_now.subtract(const Duration(days: 10)), 90, taskId: 't1'), // trop vieux
      _session(_now.subtract(const Duration(days: 1)), 45, activityId: 'other'), // sans lien
      _session(_now.subtract(const Duration(days: 7, hours: 1)), 120, taskId: 't1'), // chevauche
    ];
    expect(minutesLast7Days(p, sessions, _now), 60 + 30 + 60);
  });

  group('projectHealth', () {
    test('au point mort : rien depuis 7 jours (création comprise)', () {
      final p = _proj([_task('t', '2026-09-01')], createdAt: DateTime(2026, 9, 10));
      final h = projectHealth(p, [], _now);
      expect(h.kind, HealthKind.stalled);
      expect(h.count, 20);
      expect(h.label, 'Au point mort · 20 j');
    });
    test('à risque : tâche en retard', () {
      final p = _proj([_task('t', '2026-09-01', end: '2026-09-25')]);
      final s = [_session(_now.subtract(const Duration(days: 1)), 30, taskId: 't')];
      final h = projectHealth(p, s, _now);
      expect(h.kind, HealthKind.atRisk);
      expect(h.label, 'À risque · 1 retard');
    });
    test('à risque : échéance ≤ 7 j et < 70 % fait', () {
      final p = _proj([_task('a', '2026-09-01', status: 'done'), _task('b', '2026-09-01')],
          end: DateTime(2026, 10, 5));
      final s = [_session(_now.subtract(const Duration(days: 1)), 30, taskId: 'a')];
      expect(projectHealth(p, s, _now).label, 'À risque · échéance proche');
    });
    test('sans échéance / dans les temps', () {
      final s = [_session(_now.subtract(const Duration(days: 1)), 30, taskId: 'a')];
      expect(projectHealth(_proj([_task('a', '2026-09-01')]), s, _now).kind, HealthKind.noDeadline);
      expect(
          projectHealth(_proj([_task('a', '2026-09-01')], end: DateTime(2026, 12, 1)), s, _now).kind,
          HealthKind.onTrack);
    });
    test('une action cochée récemment compte comme signe de vie', () {
      final p = _proj([
        _task('a', '2026-09-01', actions: [TaskAction(title: 'x', done: true, doneAt: _now.subtract(const Duration(days: 2)))])
      ]);
      expect(projectHealth(p, [], _now).kind, HealthKind.noDeadline);
    });
  });

  test('daysLeftLabel', () {
    expect(daysLeftLabel(DateTime(2026, 10, 3), _now), 'J-3');
    expect(daysLeftLabel(DateTime(2026, 9, 30), _now), 'J-0');
    expect(daysLeftLabel(DateTime(2026, 9, 25), _now), 'J+5');
    expect(daysLeftLabel(null, _now), '—');
  });

  test('projectMatches : projet ou tâche, casse et accents ignorés', () {
    final p = _proj([_task('t', '2026-09-01')..title = 'Écrire la spec']);
    expect(projectMatches(p, ''), isTrue);
    expect(projectMatches(p, 'REFONTE'), isTrue);
    expect(projectMatches(p, 'ecrire'), isTrue);
    expect(projectMatches(p, 'budget'), isFalse);
  });
}
