import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/chain_session.dart';

void main() {
  final now = DateTime(2026, 10, 28, 15);

  test('une session compte dès 3 choses, sortie ou pas ; libellé du récap', () {
    ChainRun run(int done, {bool completed = false}) =>
        ChainRun(date: '2026-10-28', startedAt: now, endedAt: now, doneCount: done, total: 8, completed: completed);
    expect(chainRunCounts(run(2, completed: true)), isFalse);
    expect(chainRunCounts(run(3)), isTrue);
    expect(chainCountLine(1), 'Encore 2 choses pour qu\'elle compte');
    expect(chainCountLine(2), 'Encore 1 chose pour qu\'elle compte');
    expect(chainCountLine(4), 'Session comptée · 4 choses');
    final deck = computeBadges(
        activities: const [], habitHits: const [], schedules: const [], projects: const [], objectives: const [], sessions: const [],
        chainRuns: [for (var i = 0; i < 6; i++) run(i < 5 ? 3 : 1)], now: now);
    final b = deck.byId('enchaineur')!;
    expect((b.value, b.level, b.nextTarget), (5, 1, 20));
  });

  test('session en attente : reprenable 45 min dans la même journée vécue, aller-retour JSON', () {
    final pc = PendingChain(
      runId: 'r1', date: '2026-10-28', startedAt: now.subtract(const Duration(hours: 1)), lastActiveAt: now.subtract(const Duration(minutes: 20)),
      doneCount: 4, doneAts: [now.subtract(const Duration(minutes: 30))], deferred: const ['b1//'], dismissed: const {'b2//'}, finishedBlocks: const {'b0'},
      firstBlockId: 'b0', lastBlockId: 'b0', totalAtStart: 7,
    );
    expect(pc.isLive(now, '2026-10-28'), isTrue);
    expect(pc.isLive(now.add(const Duration(minutes: 30)), '2026-10-28'), isFalse); // 50 min d'inactivité
    expect(pc.isLive(now, '2026-10-29'), isFalse); // journée vécue basculée
    final back = PendingChain.from(pc.toJson())!;
    expect((back.runId, back.doneCount, back.totalAtStart), ('r1', 4, 7));
    expect(back.deferred, ['b1//']);
    expect(back.dismissed, {'b2//'});
    expect(back.finishedBlocks, {'b0'});
    expect(back.doneAts.single, now.subtract(const Duration(minutes: 30)));
    expect(PendingChain.from({'date': 'x'}), isNull);
  });

  test('fait pendant la pause : blocs passés faits et routine atteinte dans la fenêtre, pas les blocs déjà épuisés', () {
    final since = now.subtract(const Duration(minutes: 20));
    ScheduleBlock b(String id, DateTime? doneAt) =>
        ScheduleBlock(id: id, startTime: '09:00', durationMin: 30, title: id, category: 'project', status: doneAt == null ? 'pending' : 'done', doneAt: doneAt);
    final blocks = [
      b('in', now.subtract(const Duration(minutes: 10))),
      b('before', now.subtract(const Duration(minutes: 40))),
      b('finished', now.subtract(const Duration(minutes: 5))),
      b('open', null),
    ];
    final eau = Activity(id: 'eau', domainId: 'd', name: 'Eau', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 2, createdAt: DateTime(2026, 1, 1));
    final hits = [
      HabitHit(habitId: 'eau', ts: now.subtract(const Duration(hours: 3))),
      HabitHit(habitId: 'eau', ts: now.subtract(const Duration(minutes: 8))), // 2e hit = cible atteinte dans la fenêtre
      HabitHit(habitId: 'eau', ts: now.subtract(const Duration(minutes: 2))),
    ];
    final r = resumedDoneAts(blocks, hits, [eau], since: since, now: now, dayStartMin: 300, finishedBlocks: {'finished'});
    expect(r, [now.subtract(const Duration(minutes: 10)), now.subtract(const Duration(minutes: 8))]);
  });
}
