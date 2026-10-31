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

  test('Montre suisse : 7 jours glissants, le week-end compte encore le lundi', () {
    final courir = Activity(id: 'c', name: 'Courir', domainId: 'd', type: 'time', goalMin: 10, createdAt: DateTime(2026, 9, 1));
    // 70 min le samedi 24 oct. : couvre la fenêtre jusqu'au vendredi 30 inclus.
    final sessions = [_s('c', DateTime(2026, 10, 24, 8), 70)];
    final minutes = minutesByActivityDay(sessions, DateTime(2026, 11, 2));
    final mon = paceOn(DateTime(2026, 10, 26), activities: [courir], minutes: minutes).single;
    expect((mon.doneMin, mon.expectedMin, mon.onPace, mon.pastMin, mon.todayMin), (70, 70, true, 70, 0));
    final fri = paceOn(DateTime(2026, 10, 30), activities: [courir], minutes: minutes).single;
    expect((fri.onPace, fri.leavingMin, fri.tomorrowNeedMin), (true, 70, 70));
    // Samedi 31 : le samedi 24 est sorti.
    final sat = paceOn(DateTime(2026, 10, 31), activities: [courir], minutes: minutes).single;
    expect((sat.doneMin, sat.missingMin), (0, 70));
    final h = watchDays(ymds: ['2026-10-26', '2026-10-30', '2026-10-31'], activities: [courir], sessions: sessions, now: DateTime(2026, 11, 2));
    expect(h.won, ['2026-10-26', '2026-10-30']);
    // Domaine en veille ce jour-là : neutre.
    final frozen = watchDays(ymds: ['2026-10-31'], activities: [courir], sessions: sessions, now: DateTime(2026, 11, 2), frozenOf: (_) => {'2026-10-31'});
    expect((frozen.won.length, frozen.neutral), (0, 1));
  });

  test('Montre suisse : jours gelés et jours avant la création ne réclament rien', () {
    final lire = Activity(id: 'l', name: 'Lire', domainId: 'd', type: 'time', goalMin: 20, createdAt: DateTime(2026, 10, 28));
    final minutes = minutesByActivityDay([_s('l', DateTime(2026, 10, 28, 8), 40), _s('l', DateTime(2026, 10, 30, 8), 15)], DateTime(2026, 11, 2));
    // Créée le 28 : fenêtre comptée sur 28, 29, 30 → 60 min attendues ; le 29 gelé → 40.
    final p = paceOn(DateTime(2026, 10, 30), activities: [lire], minutes: minutes).single;
    expect((p.expectedMin, p.doneMin, p.todayMin, p.missingMin), (60, 55, 15, 5));
    final f = paceOn(DateTime(2026, 10, 30), activities: [lire], minutes: minutes, frozenOf: (_) => {'2026-10-29'}).single;
    expect((f.expectedMin, f.onPace, f.aheadMin), (40, true, 15));
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

  test('Montre suisse : plus de 3 activités en retard = aucune ligne d’enjeu', () {
    final acts = [for (var i = 0; i < 5; i++) Activity(id: 'a$i', name: 'A$i', domainId: 'd', type: 'time', goalMin: 10)];
    final facts = TodayFacts(ymd: '2026-10-30', now: DateTime(2026, 10, 30, 18), pace: [for (final a in acts) ActivityPace(a, 0, 30)]);
    final deck = BadgeDeck([
      BadgeState(def: const BadgeDef(id: 'montre-suisse', family: BadgeFamily.days, name: 'Montre suisse', symbol: 'watch', tiers: kHalfDayTiers, unit: 'j'), level: 0, value: 2),
    ]);
    final board = buildStakeBoard(deck: deck, facts: facts, activities: acts);
    expect(board.top.length + board.rest.length, 0);
    expect(board.watchOutOfReach, 5);
    final few = TodayFacts(ymd: '2026-10-30', now: DateTime(2026, 10, 30, 18), pace: [ActivityPace(acts[0], 0, 30), ActivityPace(acts[1], 40, 30)]);
    final b2 = buildStakeBoard(deck: deck, facts: few, activities: acts);
    expect(b2.top.length + b2.rest.length, 1);
  });

  test('cible du jour = 7 × minimum − 6 jours passés', () {
    final a = Activity(id: 'm', domainId: 'd', name: 'Bain de mer', goalMin: 10);
    final p = ActivityPace(a, 49, 70, todayMin: 23);
    expect(p.pastMin, 26);
    expect(p.dayTargetMin, 44);
    expect(p.missingMin, 21);
    expect(ActivityPace(a, 75, 70, todayMin: 0).dayTargetMin, 0);
  });
}
