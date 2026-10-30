import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/held_weeks.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';

Activity routine(String id, {String domain = 'sante', HabitFreq freq = HabitFreq.daily, int target = 1}) =>
    Activity(id: id, name: id, domainId: domain, type: 'habit', habitFreq: freq, habitTarget: target, createdAt: DateTime(2026, 9, 1));

/// Hits sur les jours [days] d'octobre 2026 (5 oct. = lundi).
List<HabitHit> hitsOn(String id, Iterable<int> days) => [for (final d in days) HabitHit(habitId: id, ts: DateTime(2026, 10, d, 9))];

void main() {
  test('missingHits : les plus petites cibles d’abord', () {
    expect(missingHits(const [(7, 7), (7, 7)]), 0);
    expect(missingHits(const [(5, 7), (0, 3)]), 3); // seuil 1,6 : 5/7 + 3/3 = 1,71
    expect(missingHits(const []), 0);
  });

  test('cible réduite par les jours gelés', () {
    final a = routine('p');
    expect(weekTargetFor(a, 7), 7);
    expect(weekTargetFor(a, 4), 4);
    expect(weekTargetFor(routine('w', freq: HabitFreq.weekly, target: 3), 4), 2);
  });

  test('semaines tenues, ratées, neutres en veille ; série et braises', () {
    final p = routine('p');
    final hits = [
      ...hitsOn('p', [5, 6, 7, 8, 9, 10]), // semaine du 5 : 6/7 → tenue
      ...hitsOn('p', [12, 13]), // semaine du 12 : 2/7 → ratée
      ...hitsOn('p', [19, 20, 21, 22, 23, 24, 25]), // semaine du 19 : tenue
      // semaine du 26 : en veille (gelée), rien
    ];
    final frozen = {for (var d = 26; d <= 31; d++) '2026-10-$d', '2026-11-01'};
    final w = heldWeeks(activities: [p], hits: hits, objectives: const [], now: DateTime(2026, 11, 4, 20), frozenOf: (_) => frozen);
    expect(w.weeks.map((x) => x.state).toList(), [WeekState.held, WeekState.missed, WeekState.held, WeekState.neutral, WeekState.current]);
    expect(w.weeks[3].rest, isTrue);
    expect(w.current, 1);
    expect(w.longest, 1);
    expect(w.heldSundays, ['2026-10-11', '2026-10-25']);
    final l = emberLedger(perfectYmds: const [], heldWeekYmds: w.heldSundays, spends: const [], reached: const {}, todayYmd: '2026-11-04');
    expect(l.stock, 2);
    expect(l.history.first.week, isTrue);
  });

  test('seules les routines des objectifs qui couvrent la semaine comptent', () {
    final p = routine('p'), l = routine('l');
    final o = StrategicObjective(id: 'o', title: 'Forme', startDate: DateTime(2026, 10, 1), routineCommitments: [ObjectiveRoutineCommitment(activityId: 'p')]);
    final hits = hitsOn('p', [5, 6, 7, 8, 9, 10, 11]);
    final w = heldWeeks(activities: [p, l], hits: hits, objectives: [o], now: DateTime(2026, 10, 13, 12));
    expect(w.weeks.first.state, WeekState.held); // Lecture n'est pas engagée
    final sans = heldWeeks(activities: [p, l], hits: hits, objectives: const [], now: DateTime(2026, 10, 13, 12));
    expect(sans.weeks.first.state, WeekState.missed);
  });

  test('le dimanche, les routines engagées portent « semaine tenue ce soir »', () {
    final p = routine('p');
    final hits = hitsOn('p', [26, 27, 28, 29, 30]); // 5/7, il en faut 6
    final deck = computeBadges(activities: [p], habitHits: hits, schedules: const [], projects: const [], objectives: const [], sessions: const [], now: DateTime(2026, 11, 1, 17));
    expect(deck.weeks.missing, 1);
    expect(deck.byId('semaines-tenues'), isNotNull);
    final board = buildStakeBoard(
      deck: deck,
      facts: TodayFacts(ymd: '2026-11-01', now: DateTime(2026, 11, 1, 17), routines: [RoutineToday(p, 0, 1)]),
    );
    final gains = [for (final s in [...board.top, ...board.rest]) ...s.gains];
    expect(gains.any((g) => g.kind == StakeGainKind.week), isTrue);
  });
}
