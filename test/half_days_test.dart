import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/half_days.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

Session _s(String act, DateTime start, int min) => Session(activityId: act, startAt: start, endAt: start.add(Duration(minutes: min)));

void main() {
  test('demi-journées : neutre enjambé, manqué casse la suite, paliers', () {
    final h = halfDaysFrom([
      for (var i = 1; i <= 5; i++) ('2026-10-0$i', true),
      ('2026-10-06', null),
      ('2026-10-07', false),
      ('2026-10-08', true),
      ('2026-10-09', true),
    ]);
    expect(h.won.length, 7);
    expect(h.longest, 5);
    expect(h.current, 2);
    expect(h.neutral, 1);
    expect(h.tierDates.first, DateTime(2026, 10, 5));
  });

  test('Montre suisse : attendu = minimum × jour de la semaine', () {
    final courir = Activity(id: 'c', name: 'Courir', domainId: 'd', type: 'time', goalMin: 30, createdAt: DateTime(2026, 9, 1));
    // Lundi 26 → mercredi 28 oct. : 30 + 30 le lundi et le mardi, rien le mercredi.
    final sessions = [_s('c', DateTime(2026, 10, 26, 8), 30), _s('c', DateTime(2026, 10, 27, 8), 30)];
    final minutes = minutesByActivityDay(sessions, DateTime(2026, 10, 30));
    final tue = paceOn(DateTime(2026, 10, 27), activities: [courir], minutes: minutes, windowDays: 7).single;
    expect((tue.doneMin, tue.expectedMin, tue.onPace), (60, 60, true));
    final wed = paceOn(DateTime(2026, 10, 28), activities: [courir], minutes: minutes, windowDays: 7).single;
    expect((wed.doneMin, wed.expectedMin, wed.missingMin), (60, 90, 30));
    final h = watchDays(ymds: ['2026-10-26', '2026-10-27', '2026-10-28'], activities: [courir], sessions: sessions, now: DateTime(2026, 10, 30), windowDays: 7);
    expect(h.won, ['2026-10-26', '2026-10-27']);
    // Domaine en veille ce jour-là : neutre.
    final frozen = watchDays(
        ymds: ['2026-10-28'], activities: [courir], sessions: sessions, now: DateTime(2026, 10, 30), windowDays: 7, frozenOf: (_) => {'2026-10-28'});
    expect((frozen.won.length, frozen.neutral), (0, 1));
  });

  test('Métronome : toutes les routines dues, hors acquises et veille', () {
    final a = Activity(id: 'a', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
    final b = Activity(id: 'b', name: 'Lecture', domainId: 'e', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
    final h = metronomeDays(
      ymds: ['2026-10-27', '2026-10-28'],
      activities: [a, b],
      reachedDaysByRoutine: {
        'a': {'2026-10-27', '2026-10-28'},
        'b': {'2026-10-27'},
      },
      frozenOf: (x) => x.domainId == 'e' ? {'2026-10-28'} : const {},
    );
    expect(h.won, ['2026-10-27', '2026-10-28']);
  });

  test('enjeux du soir : la dernière routine porte « Métronome · la dernière »', () {
    final a = Activity(id: 'a', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
    final b = Activity(id: 'b', name: 'Lecture', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
    final facts = TodayFacts(ymd: '2026-10-30', now: DateTime(2026, 10, 30, 18), routines: [RoutineToday(a, 1, 1), RoutineToday(b, 0, 1)]);
    final deck = BadgeDeck([
      BadgeState(def: const BadgeDef(id: 'metronome', family: BadgeFamily.days, name: 'Métronome', symbol: 'metronome', tiers: kHalfDayTiers, unit: 'j'), level: 0, value: 4),
    ]);
    final board = buildStakeBoard(deck: deck, facts: facts, activities: [a, b]);
    final s = [...board.top, ...board.rest].singleWhere((s) => s.gesture.activity?.id == 'b');
    expect(s.gains.any((g) => g.kind == StakeGainKind.halfDay && g.label.startsWith('Métronome · la dernière')), isTrue);
    expect(s.gains.firstWhere((g) => g.kind == StakeGainKind.halfDay).label, contains('palier 5'));
    expect(badgeToday(deck.byId('metronome')!, facts).chip, '1 / 2 routines');
  });
}
