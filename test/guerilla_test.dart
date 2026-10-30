import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/guerilla.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';

Activity _r(String id, String name, {int target = 1}) =>
    Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: target, timeContext: 'allday');

ChainRun _g(int day, {int done = 4, int? before, int? after, String? kind = kGuerillaKind}) => ChainRun(
      date: '2026-10-${day.toString().padLeft(2, '0')}',
      startedAt: DateTime(2026, 10, day, 15),
      endedAt: DateTime(2026, 10, day, 15, 30),
      doneCount: done,
      total: done,
      completed: false,
      kind: kind,
      bodyBefore: before,
      bodyAfter: after,
    );

void main() {
  final now = DateTime(2026, 10, 30, 16);

  test('guerillaDelta : +1, une grosse cible avance par 5, jamais au-delà du reste', () {
    expect(guerillaDelta(null, 0), 1);
    expect(guerillaDelta(6, 2), 1);
    expect(guerillaDelta(20, 0), 5);
    expect(guerillaDelta(20, 17), 3);
    expect(guerillaDelta(20, 20), 1);
  });

  test('file : deux routines pour une action, sans besoin de base ni activité en pause', () {
    final eau = _r('eau', 'Boire de l\'eau', target: 6);
    final pompes = _r('pom', 'Pompes', target: 20);
    final lit = _r('lit', 'Faire mon lit');
    final manger = _r('man', 'Manger');
    final pause = _r('pau', 'Ranger');
    final nettoyer = Activity(id: 'net', domainId: 'd', name: 'Nettoyer', type: 'time')
      ..ownActions = [TaskAction(title: 'Nettoyer le frigo'), TaskAction(title: 'Vider le congélateur', done: true)];
    final focused = TaskAction(title: 'Relire les supports', focusDate: DateTime(2026, 10, 30));
    final p = Project(
      id: 'p',
      title: 'CM',
      startDate: DateTime(2026, 9, 1),
      createdBy: 'u',
      linkedActivityId: 'net',
      tasks: [ProjectTask(id: 't', title: 't', startDate: DateTime(2026, 9, 1), actions: [focused, TaskAction(title: 'Pas visée')])],
    );
    final acts = [eau, pompes, lit, manger, pause, nettoyer];
    final day = buildRoutineDay(activities: acts, hits: const [], now: now);
    final q = buildGuerillaQueue(day: day, activities: acts, projects: [p], now: now, pausedActivityIds: {'pau'});
    final titles = q.map((c) => c.title).toList();
    expect(titles.where((t) => t.contains('Manger') || t.contains('Ranger')), isEmpty);
    expect(titles, contains('5 × Pompes'));
    expect(q[2].kind, GuerillaKind.action);
    expect(q[2].title, 'Relire les supports'); // visée aujourd'hui d'abord
    expect(q[2].activityId, 'net'); // chrono = activité du projet
    expect(q.where((c) => c.kind == GuerillaKind.action).map((c) => c.title), ['Relire les supports', 'Nettoyer le frigo']);
    expect(q.firstWhere((c) => c.title == '5 × Pompes').delta, 5);
  });

  test('nextCoupIndex saute les coups passés ; point d\'étape tous les 3 coups', () {
    const a = GuerillaCoup(kind: GuerillaKind.routine, title: 'a', hint: '', activityId: 'a');
    const b = GuerillaCoup(kind: GuerillaKind.routine, title: 'b', hint: '', activityId: 'b');
    const c = GuerillaCoup(kind: GuerillaKind.routine, title: 'c', hint: '', activityId: 'c');
    expect(nextCoupIndex([a, b, c], 0, {'r:b'}), 2);
    expect(nextCoupIndex([a, b, c], 2, {}), isNull);
    expect([for (var d = 0; d <= 6; d++) guerillaPauseDue(d)], [false, false, false, true, false, false, true]);
  });

  test('avant / après : remontées, phrase', () {
    expect(guerillaLiftLine([_g(1)]), isNull);
    expect(guerillaLiftLine([_g(1, before: 2, after: 3)]), 'Ta première guérilla t\'a fait remonter.');
    final runs = [_g(1, before: 2, after: 3), _g(2, before: 2, after: 2), _g(3, before: 1, after: 3), _g(4, before: 2, after: 4, kind: null)];
    expect(guerillaLift(runs), (rated: 3, lifted: 2));
    expect(guerillaLiftLine(runs), 'Sur tes 3 guérillas, 2 t\'ont fait remonter.');
    expect(guerillaCountLine(2), 'Encore 1 coup pour qu\'elle compte');
    expect(guerillaCountLine(4), 'Guérilla comptée · 4 coups');
  });

  test('aller-retour JSON ; une guérilla ne compte ni pour Enchaîneur ni pour Plein jour', () {
    final r = _g(5, before: 2, after: 3);
    final back = ChainRun.from(r.toJson());
    expect(back.kind, kGuerillaKind);
    expect(back.bodyBefore, 2);
    expect(back.bodyAfter, 3);
    final deck = computeBadges(
      activities: const [],
      habitHits: const [],
      schedules: const [],
      projects: const [],
      objectives: const [],
      sessions: const [],
      chainRuns: [_g(1), _g(2, done: 2), for (var d = 3; d <= 7; d++) _g(d, before: 2, after: 3)],
      now: now,
    );
    expect(deck.byId('enchaineur')!.value, 0);
    final g = deck.byId('guerilla')!;
    expect(g.value, 6); // la 2e n'a que 2 coups
    expect(g.level, 2); // paliers 1 et 5
    expect(g.nextTarget, 15);
    expect(g.obtained, DateTime(2026, 10, 6)); // 5e comptée : jours 1, 3, 4, 5, 6
  });
}
