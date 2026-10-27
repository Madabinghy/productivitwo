import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';

void main() {
  final now = DateTime(2026, 10, 28, 10); // mercredi
  Activity act(String id, {String type = 'time'}) => Activity(
      id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: type, goalMin: 1,
      habitFreq: type == 'habit' ? HabitFreq.daily : null, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
  ScheduleBlock block(String id, {String? activityId, String? projectId, String status = 'pending'}) =>
      ScheduleBlock(id: id, startTime: '09:00', durationMin: 60, title: id, category: 'project', activityId: activityId, projectId: projectId, status: status);

  test('un bloc sert l\'objectif par son activité engagée, son projet ou l\'activité liée du projet', () {
    final o = StrategicObjective(
      title: 'Livre',
      timeCommitments: [ObjectiveTimeCommitment(activityId: 'ecrire', weeklyMin: 140)],
      routineCommitments: [ObjectiveRoutineCommitment(activityId: 'lecture')],
      projectIds: ['p1'],
    );
    final p1 = Project(id: 'p1', title: 'P1', createdBy: 't', startDate: DateTime(2026, 1, 1), linkedActivityId: 'relire');
    final byId = {'p1': p1};
    expect(blockServesObjective(block('a', activityId: 'ecrire'), o, byId), isTrue);
    expect(blockServesObjective(block('b', activityId: 'lecture'), o, byId), isTrue);
    expect(blockServesObjective(block('c', projectId: 'p1'), o, byId), isTrue);
    expect(blockServesObjective(block('d', activityId: 'relire'), o, byId), isTrue);
    expect(blockServesObjective(block('e', activityId: 'autre'), o, byId), isFalse);
    expect(blockServesObjective(block('f', activityId: 'ecrire', status: 'deleted'), o, byId), isFalse);
  });

  test('temps du jour et de la semaine, attendu lissé sur 7 jours, objectifs actifs seulement', () {
    final o = StrategicObjective(title: 'Livre', timeCommitments: [ObjectiveTimeCommitment(activityId: 'ecrire', weeklyMin: 140)]);
    final done = StrategicObjective(title: 'Fini', status: 'done', timeCommitments: [ObjectiveTimeCommitment(activityId: 'ecrire', weeklyMin: 140)]);
    final sessions = [
      Session(activityId: 'ecrire', startAt: DateTime(2026, 10, 26, 9), endAt: DateTime(2026, 10, 26, 10)), // lundi
      Session(activityId: 'ecrire', startAt: DateTime(2026, 10, 28, 7), endAt: DateTime(2026, 10, 28, 7, 30)), // aujourd'hui
      Session(activityId: 'ecrire', startAt: DateTime(2026, 10, 28, 9, 50)), // ouverte, 10 min
    ];
    final days = buildObjectiveDays(objectives: [o, done], activities: [act('ecrire')], sessions: sessions, blocks: const [], projects: const [], now: now);
    expect(days.length, 1);
    final t = days.single.times.single;
    expect(t.expectedTodayMin, 20);
    expect(t.doneTodayMin, 40);
    expect(t.doneWeekMin, 100);
    expect(t.name, 'ecrire');
  });

  group('objectif du moment', () {
    ObjectiveDay day(StrategicObjective o, {List<ObjectiveTimeToday> times = const [], List<Activity> routines = const [], List<ScheduleBlock> blocks = const []}) =>
        ObjectiveDay(objective: o, times: times, routines: routines, blocks: blocks, nextActions: const []);
    ObjectiveTimeToday time(String id, {int weeklyMin = 140, int doneToday = 0}) =>
        ObjectiveTimeToday(activity: act(id), activityId: id, weeklyMin: weeklyMin, doneTodayMin: doneToday, doneWeekMin: doneToday);
    final a = StrategicObjective(title: 'A', createdAt: DateTime(2026, 10, 1));
    final b = StrategicObjective(title: 'B', createdAt: DateTime(2026, 10, 1));

    test('mode : Flemme = la routine engagée avant le chrono ; En forme = le coup en cours devant', () {
      final coup = StrategicObjective(title: 'Coup', horizon: 'tactical', endDate: DateTime(2026, 10, 30), createdAt: DateTime(2026, 10, 1));
      final r = act('lecture', type: 'habit');
      final low = rankObjectiveMoments(
        [day(a, times: [time('lire')], routines: [r]), day(b, times: [time('ecrire')])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (o) => o.title == 'A' ? .9 : .2, mode: DayMode.low,
      );
      expect(low.first.objective.title, 'A');
      expect(low.first.move.kind, ObjectiveMoveKind.routine);
      final normal = rankObjectiveMoments(
        [day(a, times: [time('lire')], routines: [r]), day(b, times: [time('ecrire')])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (o) => o.title == 'A' ? .9 : .2,
      );
      expect(normal.first.objective.title, 'B');
      expect(normal.first.move.kind, ObjectiveMoveKind.time);
      final high = rankObjectiveMoments(
        [day(a, times: [time('lire')]), day(coup, times: [time('sprint')])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (o) => o.title == 'A' ? .1 : .9, mode: DayMode.high,
      );
      expect(high.first.objective.title, 'Coup');
    });

    test('bloc en cours ou chrono qui tourne = objectif du moment, avant le retard de rythme', () {
      final blk = ScheduleBlock(id: 'k', startTime: '09:30', durationMin: 60, title: 'Écrire', category: 'project', activityId: 'ecrire');
      final ranked = rankObjectiveMoments(
        [day(a, times: [time('lire')]), day(b, blocks: [blk])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (o) => o.title == 'A' ? .2 : .9,
      );
      expect(ranked.first.objective.title, 'B');
      expect(ranked.first.move.kind, ObjectiveMoveKind.block);
      expect(ranked.first.remaining, ['bloc à 09:30']);
      final run = rankObjectiveMoments(
        [day(a, times: [time('lire')]), day(b, times: [time('ecrire', doneToday: 30)])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (_) => .5, runningActivityId: 'ecrire',
      );
      expect(run.first.objective.title, 'B');
      expect(run.first.move.kind, ObjectiveMoveKind.running);
      expect(run.first.remaining, isEmpty);
    });

    test('sinon le plus en retard sur son rythme qui a encore du travail, geste = engagement le plus en retard', () {
      final ranked = rankObjectiveMoments(
        [day(a, times: [time('lire', weeklyMin: 70), time('ecrire', weeklyMin: 280, doneToday: 10)]), day(b, times: [time('x')])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (o) => o.title == 'A' ? .4 : .8,
      );
      expect(ranked.first.objective.title, 'A');
      expect(ranked.first.move.kind, ObjectiveMoveKind.time);
      expect(ranked.first.move.time!.activityId, 'ecrire'); // 30 min restantes contre 10
      expect(ranked.first.remaining, ['10 min de lire', '30 min de ecrire']);
    });

    test('routine non atteinte = +1 ; bloc passé non fait ne compte plus ; tout fait = aucun geste', () {
      final r = act('pompes', type: 'habit');
      final old = ScheduleBlock(id: 'o', startTime: '07:00', durationMin: 30, title: 'Vieux', category: 'project', activityId: 'pompes');
      final ranked = rankObjectiveMoments(
        [day(a, routines: [r], blocks: [old]), day(b, times: [time('x', doneToday: 60)])],
        nowMin: 10 * 60, now: now, routineCount: (_) => 0, weekPercent: (_) => 1,
      );
      expect(ranked.first.objective.title, 'A');
      expect(ranked.first.move.kind, ObjectiveMoveKind.routine);
      expect(ranked.first.remaining, ['1 routine']);
      expect(ranked.last.objective.title, 'B');
      expect(ranked.last.move.kind, ObjectiveMoveKind.none);
      expect(ranked.last.allDone, isTrue);
      final done = rankObjectiveMoments([day(a, routines: [r])], nowMin: 600, now: now, routineCount: (_) => 1, weekPercent: (_) => 1);
      expect(done.single.allDone, isTrue);
    });

    test('relevé dû = geste « noter un relevé » quand rien d’autre ne reste', () {
      final o = StrategicObjective(
          title: 'Poids', createdAt: DateTime(2026, 10, 1), checkInEvery: 3,
          metric: ObjectiveMetric(label: 'Poids', unit: 'kg', startValue: 84, targetValue: 90));
      final ranked = rankObjectiveMoments([day(o), day(a)], nowMin: 600, now: now, routineCount: (_) => 0, weekPercent: (_) => null);
      expect(ranked.first.objective.title, 'Poids');
      expect(ranked.first.readingDue, isTrue);
      expect(ranked.first.move.kind, ObjectiveMoveKind.reading);
      expect(ranked.first.allDone, isFalse);
    });
  });
}
