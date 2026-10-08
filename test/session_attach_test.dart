import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

ScheduleBlock _b(String id, String start, int dur,
        {String? taskId, String? activityId, String status = 'pending'}) =>
    ScheduleBlock(
        id: id,
        startTime: start,
        durationMin: dur,
        title: id,
        status: status,
        category: 'project',
        taskId: taskId,
        activityId: activityId);

void main() {
  final day = DateTime(2026, 10, 7);
  final blocks = [
    _b('free', '08:00', 60), // bloc libre : rattachable (il prendra l'activité du chrono)
    _b('corr', '09:00', 45, taskId: 't1'),
    _b('kahoot', '10:00', 60, taskId: 't2'),
    _b('old', '09:30', 30, taskId: 't3', status: 'deleted'),
    _b('act', '14:00', 60, activityId: 'a1'),
  ];
  final acts = {'a1': Activity(id: 'a1', domainId: 'd', name: 'Prépa', habitTarget: 1)};

  test('blockCandidatesForSession : chevauchement d\'abord, blocs retirés en fin de liste', () {
    final s = Session(
        activityId: 'a1', startAt: DateTime(2026, 10, 7, 9, 10), endAt: DateTime(2026, 10, 7, 11, 10));
    final c = blockCandidatesForSession(s, blocks, day, activityOf: (id) => acts[id]);
    expect(c.map((x) => x.block.id).toList(), ['kahoot', 'corr', 'free', 'act', 'old']);
    expect(c[0].overlapMin, 60);
    expect(c[1].overlapMin, 35);
    expect(c[2].overlapMin, 0);
    expect(c[3].overlapMin, 0);
    expect(c[4].overlapMin, 30); // retiré du programme : proposé, mais en dernier
  });

  test('attachSessionToBlock marche aussi sur une session terminée', () {
    final s = Session(
        activityId: 'a1', startAt: DateTime(2026, 10, 7, 9, 0), endAt: DateTime(2026, 10, 7, 11, 0));
    expect(attachSessionToBlock(s, blocks[1]), AttachResult.session);
    expect(s.taskId, 't1');
    expect(s.endAt, DateTime(2026, 10, 7, 11, 0));
  });
}
