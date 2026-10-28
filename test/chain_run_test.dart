import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  final now = DateTime(2026, 10, 26, 20);
  ChainRun run(int day, {bool completed = true, int done = 5, String? first, String? last, String? pFirst, String? pLast}) => ChainRun(
        date: '2026-10-${day.toString().padLeft(2, '0')}',
        startedAt: DateTime(2026, 10, day, 8),
        endedAt: DateTime(2026, 10, day, 18),
        doneCount: done,
        total: 6,
        completed: completed,
        firstBlockId: first,
        lastBlockId: last,
        programFirstBlockId: pFirst,
        programLastBlockId: pLast,
      );

  test('fullDay : menée au bout, du premier au dernier bloc du programme', () {
    expect(run(1, first: 'a', last: 'z', pFirst: 'a', pLast: 'z').fullDay, isTrue);
    expect(run(1, completed: false, first: 'a', last: 'z', pFirst: 'a', pLast: 'z').fullDay, isFalse);
    expect(run(1, first: 'b', last: 'z', pFirst: 'a', pLast: 'z').fullDay, isFalse);
    expect(run(1, first: 'a', last: 'y', pFirst: 'a', pLast: 'z').fullDay, isFalse);
    expect(run(1).fullDay, isFalse);
  });

  test('aller-retour JSON', () {
    final r = run(3, first: 'a', last: 'z', pFirst: 'a', pLast: 'z');
    final back = ChainRun.from(r.toJson());
    expect(back.id, r.id);
    expect(back.completed, isTrue);
    expect(back.fullDay, isTrue);
    expect(back.doneCount, 5);
  });

  test('Enchaîneur au 5e session de 3 choses et plus (sortie ou pas) ; Plein jour à la première journée entière', () {
    final runs = [
      // 12 sessions : la 3e n'a que 2 choses (ne compte pas), la 5e est sortie avant la fin (compte quand même).
      for (var d = 1; d <= 12; d++) run(d, completed: d != 5, done: d == 3 ? 2 : 5),
      run(14, first: 'a', last: 'z', pFirst: 'a', pLast: 'z'),
    ];
    final deck = computeBadges(
      activities: const [],
      habitHits: const [],
      schedules: const [],
      projects: const [],
      objectives: const [],
      sessions: const [],
      chainRuns: runs,
      now: now,
    );
    final e = deck.byId('enchaineur')!;
    expect(e.def.measured, isTrue);
    expect(e.value, 12); // 13 sessions, une seule sous 3 choses
    expect(e.level, 1); // palier 5 ; 20 et 50 restent
    expect(e.obtained, DateTime(2026, 10, 6)); // 5e comptée : jours 1, 2, 4, 5, 6
    expect(e.nextTarget, 20);
    final p = deck.byId('plein-jour')!;
    expect(p.level, 1);
    expect(p.obtained, DateTime(2026, 10, 14));
    final none = computeBadges(activities: const [], habitHits: const [], schedules: const [], projects: const [], objectives: const [], sessions: const [], now: now);
    expect(none.byId('enchaineur')!.value, 0);
    expect(none.byId('plein-jour')!.level, 0);
  });
}
