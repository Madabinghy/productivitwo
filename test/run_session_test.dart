import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;
import 'package:productivitwo_v1/utils/run_session.dart';

void main() {
  final started = DateTime(2026, 10, 30, 15, 30);
  PendingRun run({int done = 2, DateTime? last, String kind = kGuerillaKind, Map<String, dynamic> extra = const {}}) => PendingRun(
        kind: kind,
        runId: 'r1',
        date: '2026-10-30',
        startedAt: started,
        lastActiveAt: last ?? DateTime(2026, 10, 30, 15, 42),
        done: done,
        extra: extra,
      );

  test('reprenable : même journée vécue, 45 min d\'inactivité au plus', () {
    final p = run();
    expect(p.isLive(DateTime(2026, 10, 30, 16, 20), '2026-10-30'), isTrue);
    expect(p.isLive(DateTime(2026, 10, 30, 16, 28), '2026-10-30'), isFalse);
    expect(p.isLive(DateTime(2026, 10, 30, 16), '2026-10-31'), isFalse);
    // Format sans tirets (`livedYmd`) : c'était le bug du 2026-10-30, toute session semblait expirée.
    expect(p.isLive(DateTime(2026, 10, 30, 16), '20261030'), isTrue);
  });

  test('aller-retour JSON avec l\'état propre au mode', () {
    final p = run(extra: {'passed': ['r:eau', 'a:x'], 'bodyBefore': 2, 'doneTitles': ['Boire de l\'eau']});
    final back = PendingRun.from(p.toJson())!;
    expect(back.kind, kGuerillaKind);
    expect(back.done, 2);
    expect(back.strings('passed'), ['r:eau', 'a:x']);
    expect(back.intOf('bodyBefore'), 2);
    expect(PendingRun.from({'kind': 'guerilla'}), isNull);
  });

  test('close telle quelle : ses coups comptent, rien sans coup', () {
    final r = expiredRunOf(run(done: 3, extra: {'bodyBefore': 2}))!;
    expect(r.id, 'r1');
    expect(r.kind, kGuerillaKind);
    expect(r.doneCount, 3);
    expect(r.bodyBefore, 2);
    expect(r.endedAt, DateTime(2026, 10, 30, 15, 42));
    expect(expiredRunOf(run(done: 0)), isNull);
    expect(expiredRunOf(run(kind: kOffensiveKind, done: 4, extra: {'total': 2}))!.total, 2);
    expect(pendingRunLabel(run(), name: 'Guérilla'), 'Guérilla en cours · 2 coups');
  });
}
