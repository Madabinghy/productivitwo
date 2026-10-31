import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/day_settle.dart';
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show deepWorkSessions;
import 'package:productivitwo_v1/utils/block_queue.dart';

void main() {
  test('blocs de temps pour un budget', () {
    final w = timeBlockWants(330);
    expect(w.map((x) => '${timeKindOf(x.activityId)}:${x.minutes}').toList(), ['deep:120', 'small:45', 'deep:90', 'buffer:45']);
    expect(timeBlockWants(60).map((x) => timeKindOf(x.activityId)).toList(), ['small']);
    expect(timeBlockWants(600).where((x) => timeKindOf(x.activityId) == 'deep').length, 3);
    expect(timeKindOf('abc'), isNull);
  });

  test('bloc du programme d\'un bloc de temps', () {
    final b = planOrTimeBlockOf(PlannedBlock(PlanWant(activityId: timeWantId('deep', 1), title: 'Deep work', minutes: 120, reason: ''), 540, 120));
    expect(b.timeBlock, 'deep');
    expect(b.activityId, isNull);
    expect(b.startTime, '09:00');
    expect(ScheduleBlock.from(b.toJson()).timeBlock, 'deep');
  });

  test('tout chrono compte pour un bloc de temps, dans son créneau', () {
    final b = ScheduleBlock(startTime: '09:00', durationMin: 100, title: 'Deep work', category: 'project', timeBlock: 'deep');
    final day = DateTime(2026, 11, 2);
    final sessions = [
      Session(activityId: 'a', startAt: day.add(const Duration(hours: 9)), endAt: day.add(const Duration(hours: 9, minutes: 40))),
      Session(activityId: 'b', startAt: day.add(const Duration(hours: 9, minutes: 45)), endAt: day.add(const Duration(hours: 10, minutes: 10))),
      Session(activityId: 'c', startAt: day.add(const Duration(hours: 14)), endAt: day.add(const Duration(hours: 15))),
    ];
    expect(loggedMinForBlock(b, sessions, day.add(const Duration(hours: 9)), day.add(const Duration(hours: 10, minutes: 40))), 65);
    expect(sessionMatchesBlock(sessions.first, b), isTrue);
    expect(blocksSettledByChrono(blocks: [b], sessions: sessions, date: day, now: day.add(const Duration(days: 1))), [b]);
    expect(freeBlockToClaim([b], 9 * 60 + 30), isNull);
  });

  test('badge Deep work : un bloc de temps tenu 60 min cumulées', () {
    final day = DateTime(2026, 11, 2);
    final b = ScheduleBlock(startTime: '09:00', durationMin: 120, title: 'Deep work', category: 'project', timeBlock: 'deep');
    final sch = DailySchedule(date: '2026-11-02', blocks: [b]);
    final s1 = [
      Session(activityId: 'a', startAt: day.add(const Duration(hours: 9)), endAt: day.add(const Duration(hours: 9, minutes: 35))),
      Session(activityId: 'b', startAt: day.add(const Duration(hours: 9, minutes: 40)), endAt: day.add(const Duration(hours: 10, minutes: 10))),
    ];
    expect(deepWorkSessions(s1, [sch]).length, 1);
    expect(deepWorkSessions(s1.take(1).toList(), [sch]), isEmpty);
  });

  test('file d\'un bloc de temps : parole, retard, visée, prochaine action', () {
    final today = DateTime(2026, 11, 2);
    final lateA = TaskAction(id: 'late', title: 'En retard', dueDate: DateTime(2026, 10, 30));
    final nextA = TaskAction(id: 'next', title: 'Suivante');
    final t = ProjectTask(id: 't', title: 'T', startDate: DateTime(2026, 10, 1), actions: [nextA, lateA]);
    final p = Project(id: 'p', title: 'P', createdBy: 'user', startDate: DateTime(2026, 10, 1), linkedActivityId: 'w', tasks: [t]);
    final own = TaskAction(id: 'own', title: 'Visée', focusDate: today);
    final pledge = TaskAction(id: 'pl', title: 'Parole', focusDate: today);
    final acts = [
      Activity(id: 'w', domainId: 'd', name: 'Travail'),
      Activity(id: 'x', domainId: 'd', name: 'Perso', ownActions: [own, pledge]),
    ];
    final q = timeBlockQueue(projects: [p], activities: acts, today: today, paroleIds: {'pl'});
    expect(q.map((e) => e.id).toList(), ['pl', 'late', 'own']); // la prochaine action du projet est déjà la plus en retard
    expect(q.first.reason, 'PAROLE');
    expect(q[1].activity?.id, 'w');
    expect(q[2].activity?.id, 'x');
  });
}

