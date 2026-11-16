import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

void main() {
  test('bilan du soir : journée parfaite (sans braise depuis 2026-11-07)', () {
    final r = Activity(id: 'r', name: 'R', domainId: 'd', type: 'habit');
    final perfect = TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29, 21), routines: [RoutineToday(r, 1, 1)]);
    final partial = TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29, 21), routines: [RoutineToday(r, 0, 1)]);
    expect(isPerfectSoFar(perfect), isTrue);
    expect(isPerfectSoFar(partial), isFalse);
    expect(isPerfectSoFar(TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29))), isFalse);
    final l = buildEveningLedger(
      board: StakeBoard.empty, deck: null, projects: const [], activities: const [], sessions: const [], objectiveDays: const [],
      dayStart: DateTime(2026, 10, 29, 5), now: DateTime(2026, 10, 29, 21), perfectToday: true);
    expect(l.advanced.first.title, 'Journée parfaite');
    expect(l.advanced.first.sub, 'tout est tenu');
  });
}
