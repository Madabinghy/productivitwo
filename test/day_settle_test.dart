import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/day_settle.dart';

void main() {
  final date = DateTime(2026, 10, 26); // programme du 26 (journée vécue 5 h → 5 h)
  final now = DateTime(2026, 10, 27, 5, 1); // juste après la bascule suivante
  ScheduleBlock b(String id, String start, int dur, {String? activityId, String? taskId, String status = 'pending', bool noAutoWin = false}) =>
      ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, category: 'personal', activityId: activityId, taskId: taskId, status: status, noAutoWin: noAutoWin);

  test('Sommeil 22:00 → 05:00 couvert par le chrono est réglé à la bascule ; les autres cas non', () {
    final blocks = [
      b('sommeil', '22:00', 420, activityId: 'dodo'),
      b('muscu', '18:00', 60, activityId: 'muscu'), // 20 min seulement : < 60 %
      b('lecture', '21:00', 30, activityId: 'lire'), // 25 min : ≥ 60 %
      b('decoche', '09:00', 60, activityId: 'lire', noAutoWin: true),
      b('libre', '12:00', 60), // sans source
      b('deja', '07:00', 30, activityId: 'lire', status: 'done'),
    ];
    final sessions = [
      Session(activityId: 'dodo', startAt: DateTime(2026, 10, 26, 22, 40), endAt: DateTime(2026, 10, 27, 6, 30)),
      Session(activityId: 'muscu', startAt: DateTime(2026, 10, 26, 18, 10), endAt: DateTime(2026, 10, 26, 18, 30)),
      Session(activityId: 'lire', startAt: DateTime(2026, 10, 26, 21), endAt: DateTime(2026, 10, 26, 21, 25)),
      Session(activityId: 'lire', startAt: DateTime(2026, 10, 26, 9), endAt: DateTime(2026, 10, 26, 10)),
    ];
    final settled = blocksSettledByChrono(blocks: blocks, sessions: sessions, date: date, now: now);
    expect(settled.map((x) => x.id).toList(), ['sommeil', 'lecture']);
  });

  test('un chrono encore ouvert compte jusqu\'à maintenant ; plancher 10 min', () {
    final blocks = [b('court', '23:50', 10, activityId: 'x'), b('mini', '23:00', 5, activityId: 'y')];
    final sessions = [
      Session(activityId: 'x', startAt: DateTime(2026, 10, 26, 23, 50)), // ouverte → couvre le bloc entier
      Session(activityId: 'y', startAt: DateTime(2026, 10, 26, 23), endAt: DateTime(2026, 10, 26, 23, 5)), // 5 min < plancher
    ];
    final settled = blocksSettledByChrono(blocks: blocks, sessions: sessions, date: date, now: now);
    expect(settled.map((x) => x.id).toList(), ['court']);
  });
}
