import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/offensive.dart';

TaskAction _a(String title, {bool done = false, DateTime? due, DateTime? focus, String? linked}) =>
    TaskAction(title: title, done: done, dueDate: due, focusDate: focus, linkedActivityId: linked);

ProjectTask _t(String id, List<TaskAction> actions, {DateTime? start, DateTime? end, String status = 'pending'}) =>
    ProjectTask(id: id, title: id, startDate: start ?? DateTime(2026, 10, 1), endDate: end, actions: actions, status: status);

Project _p(String id, List<ProjectTask> tasks, {bool paused = false, String? linked}) =>
    Project(id: id, title: id, startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: tasks, paused: paused, linkedActivityId: linked);

ChainRun _run(int day, int won, {String kind = kOffensiveKind}) => ChainRun(
      date: '2026-10-${day.toString().padLeft(2, '0')}',
      startedAt: DateTime(2026, 10, day, 9),
      endedAt: DateTime(2026, 10, day, 10),
      doneCount: won,
      total: 2,
      completed: false,
      kind: kind,
    );

void main() {
  final now = DateTime(2026, 10, 30, 16);

  test('openTargets : hors tâches à venir et faites, par date de travail puis Gantt', () {
    final p = _p('cm', [
      _t('t1', [_a('sans date'), _a('échéance 5 nov', due: DateTime(2026, 11, 5)), _a('fait', done: true)]),
      _t('t2', [_a('visée hier', focus: DateTime(2026, 10, 29))]),
      _t('t3', [_a('à venir')], start: DateTime(2026, 11, 10)),
      _t('t4', [_a('tâche faite')], status: 'done'),
    ]);
    expect(openTargets(p, now).map((x) => x.action.title), ['visée hier', 'échéance 5 nov', 'sans date']);
  });

  test('fronts : en retard d\'abord, sans projet en pause ni vide ; ligne', () {
    final late = _p('late', [_t('t', [_a('x', due: DateTime(2026, 10, 20)), _a('y', due: DateTime(2026, 10, 25)), _a('z')])]);
    final calm = _p('calm', [_t('t', [_a('a'), _a('b'), _a('c'), _a('d')])]);
    final paused = _p('paused', [_t('t', [_a('a', due: DateTime(2026, 10, 1))])], paused: true);
    final empty = _p('empty', [_t('t', [_a('a', done: true)])]);
    final f = offensiveFronts([calm, late, paused, empty], now);
    expect(f.map((x) => x.project.id), ['late', 'calm']);
    expect(frontLine(f.first), '2 en retard · 3 actions prêtes');
  });

  test('tout mélanger : la prochaine action de chaque projet, en retard d\'abord ; chrono = action sinon projet', () {
    final a = _p('a', [_t('t', [_a('A1', due: DateTime(2026, 11, 20)), _a('A2')])], linked: 'contenu');
    final b = _p('b', [_t('t', [_a('B1', due: DateTime(2026, 10, 25), linked: 'admin')])]);
    final q = buildOffensiveQueue([a, b], now);
    expect(q.map((x) => x.action.title), ['B1', 'A1']);
    expect(q.first.chronoActivityId, 'admin');
    expect(q.last.chronoActivityId, 'contenu');
    expect(buildOffensiveQueue([a, b], now, projectId: 'a').map((x) => x.action.title), ['A1', 'A2']);
  });

  test('point d\'étape, minutes, plan', () {
    expect([for (var w = 0; w <= 6; w++) offensivePauseDue(w)], [false, false, false, true, false, false, true]);
    expect(fmtOffensiveMin(47), '47 min');
    expect(fmtOffensiveMin(92), '1 h 32');
    final p = _p('p', [_t('t1', [], end: DateTime(2026, 10, 20), status: 'done'), _t('t2', [], end: DateTime(2026, 10, 25)), _t('t3', [], end: DateTime(2026, 11, 20))]);
    expect(planSnapshot(p, now), (done: 1, total: 3, behind: 1));
  });

  test('badge Offensive dès 3 coups, à part de Guérilla et d\'Enchaîneur', () {
    final deck = computeBadges(
      activities: const [],
      habitHits: const [],
      schedules: const [],
      projects: const [],
      objectives: const [],
      sessions: const [],
      chainRuns: [_run(1, 3), _run(2, 2), _run(3, 6), _run(4, 4, kind: 'guerilla')],
      now: now,
    );
    final o = deck.byId('offensive')!;
    expect(o.value, 2);
    expect(o.level, 1);
    expect(o.nextTarget, 5);
    expect(deck.byId('guerilla')!.value, 1);
    expect(deck.byId('enchaineur')!.value, 0);
  });
}
