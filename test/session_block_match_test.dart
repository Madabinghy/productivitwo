import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  final t0 = DateTime(2026, 9, 29, 8);
  ScheduleBlock blk({String? projectId, String? taskId, String? activityId}) => ScheduleBlock(
      startTime: '08:00', durationMin: 60, title: 'b',
      projectId: projectId, taskId: taskId, activityId: activityId);

  test('bloc de tâche : même tâche = même source, même activité ne suffit pas', () {
    final b = blk(projectId: 'p', taskId: 't');
    expect(sessionMatchesBlock(Session(activityId: 'a', startAt: t0, taskId: 't'), b), isTrue);
    expect(sessionMatchesBlock(Session(activityId: 'a', startAt: t0), b), isFalse);
  });

  test('bloc d\'activité : même activité', () {
    final b = blk(activityId: 'vaisselle');
    expect(sessionMatchesBlock(Session(activityId: 'vaisselle', startAt: t0), b), isTrue);
    expect(sessionMatchesBlock(Session(activityId: 'contenu', startAt: t0), b), isFalse);
  });

  test('bloc projet sans tâche : activité liée du projet ; bloc libre : jamais', () {
    final b = blk(projectId: 'p');
    expect(sessionMatchesBlock(Session(activityId: 'a', startAt: t0), b, projectLinkedActivityId: 'a'), isTrue);
    expect(sessionMatchesBlock(Session(activityId: 'a', startAt: t0), b), isFalse);
    expect(sessionMatchesBlock(Session(activityId: 'a', startAt: t0), blk()), isFalse);
  });
}
