import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
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
}
