import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  final day = DateTime(2026, 9, 30);
  final end = day.add(const Duration(days: 1));
  Session s(int h, int min, {String act = 'A', String? task, String? action}) => Session(
      activityId: act,
      startAt: day.add(Duration(hours: h)),
      endAt: day.add(Duration(hours: h, minutes: min)),
      taskId: task,
      actionId: action);
  final sessions = [
    s(9, 29, task: 't1', action: 'a1'), // travail réel sur la tâche t1 / action a1
    s(11, 40), // activité A sans tâche
    s(14, 20, task: 't2'),
  ];
  ScheduleBlock blk({String? task, String? action, String? act}) =>
      ScheduleBlock(startTime: '08:00', durationMin: 60, title: 'b', taskId: task, actionId: action, activityId: act);

  test('bloc ciblant une action : seules les sessions de cette action comptent', () {
    expect(loggedMinForBlock(blk(task: 't1', action: 'a1', act: 'A'), sessions, day, end), 29);
    expect(loggedMinForBlock(blk(task: 't1', action: 'a9', act: 'A'), sessions, day, end), 0);
  });

  test('bloc de tâche : sessions de la tâche, pas le total de l\'activité', () {
    expect(loggedMinForBlock(blk(task: 't2', act: 'A'), sessions, day, end), 20);
    expect(loggedMinForBlock(blk(task: 't3', act: 'A'), sessions, day, end), 0);
  });

  test('bloc d\'activité sans tâche : total de l\'activité', () {
    expect(loggedMinForBlock(blk(act: 'A'), sessions, day, end), 89);
    expect(loggedMinForBlock(blk(), sessions, day, end), 0);
  });

  test('currentBlockAt et shiftedStartAfter', () {
    final blocks = [
      ScheduleBlock(startTime: '09:00', durationMin: 60, title: 'x'),
      ScheduleBlock(startTime: '10:00', durationMin: 30, title: 'y', status: 'done'),
    ];
    expect(currentBlockAt(blocks, 9 * 60 + 30)!.title, 'x');
    expect(currentBlockAt(blocks, 10 * 60 + 10), isNull);
    expect(shiftedStartAfter(10 * 60 + 1, 45), '10:15');
    expect(shiftedStartAfter(23 * 60 + 30, 45), isNull);
  });
}
