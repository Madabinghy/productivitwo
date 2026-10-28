import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

Activity _r(String id) => Activity(id: id, name: id, domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
ScheduleBlock _b(String id, String status, {String? activityId, String kind = 'normal'}) =>
    ScheduleBlock(id: id, startTime: '09:00', durationMin: 30, title: 'Bloc $id', category: 'project', status: status, activityId: activityId, kind: kind);
BadgeState _state(String id, {int value = 0, List<int> tiers = const [7], String? subject}) =>
    BadgeState(def: BadgeDef(id: id, family: BadgeFamily.days, name: id, symbol: 'x', tiers: tiers, subjectId: subject), level: 0, value: value);

void main() {
  final now = DateTime(2026, 10, 28, 10, 20);
  final routines = [
    RoutineToday(_r('pompes'), 0, 1),
    RoutineToday(_r('lecture'), 1, 2),
    RoutineToday(_r('cafe'), 1, 1),
    RoutineToday(_r('eau'), 1, 1),
    RoutineToday(_r('lit'), 1, 1),
  ];
  final blocks = [_b('a', 'done'), _b('b', 'done'), _b('c', 'pending'), _b('d', 'pending'), _b('e', 'pending', activityId: 'cuisine'), _b('g', 'skipped'), _b('m', 'pending', kind: 'mirror')];
  final f = TodayFacts(ymd: '2026-10-28', now: now, routines: routines, blocks: blocks);

  test('solidNeed : 80 % arrondi au-dessus', () {
    expect(solidNeed(18), 15);
    expect(solidNeed(8), 7);
    expect(solidNeed(5), 4);
    expect(solidNeed(0), 0);
  });

  test('journée parfaite : nomme les routines manquantes (les plus avancées d\'abord) et les blocs à faire', () {
    final t = badgeToday(_state('journee-parfaite', tiers: const [1]), f);
    expect(t.stake, TodayStake.reachable);
    expect(t.items.map((i) => i.title).toList(), ['lecture', 'pompes', 'Bloc c', 'Bloc d', 'Bloc e']);
    expect(t.chip, contains('5 choses'));
    final saved = badgeToday(_state('journee-parfaite', tiers: const [1]),
        TodayFacts(ymd: '2026-10-28', now: now, routines: [RoutineToday(_r('x'), 1, 1)], blocks: [_b('a', 'done')]));
    expect(saved.stake, TodayStake.saved);
  });

  test('semaine solide : marge avant 80 %, en jeu seulement si une suite court', () {
    // 5 routines → 4 suffisent, 3 atteintes → 1 manque ; 5 blocs comptés → 4 suffisent, 2 faits → 2 sur 3 à venir.
    final t = badgeToday(_state('semaine-solide', value: 2), f);
    expect(t.stake, TodayStake.atRisk);
    expect(t.chip, 'en jeu · 1 routine, 2 blocs sur 3');
    expect(t.items.first.title, 'lecture');
    expect(t.items.where((i) => i.kind == GapKind.block).length, 3);
    expect(t.notes.first, contains('Tu peux encore en manquer 1'));
    expect(t.gauges.first, (label: 'Routines', done: 3, need: 4, total: 5));
    final fresh = badgeToday(_state('semaine-solide', value: 0), f);
    expect(fresh.stake, TodayStake.reachable);
  });

  test('semaine solide : les blocs sautés / supprimés ne comptent pas (comme scoreDay), tenue quand les deux seuils sont passés', () {
    final skipped = TodayFacts(ymd: '2026-10-28', now: now, routines: routines, blocks: [_b('a', 'done'), _b('b', 'skipped'), _b('c', 'skipped'), _b('d', 'pending'), _b('e', 'deleted')]);
    final t = badgeToday(_state('semaine-solide', value: 3), skipped);
    expect(t.gauges.last, (label: 'Blocs', done: 1, need: 2, total: 2));
    expect(t.stake, TodayStake.atRisk);
    final held = TodayFacts(ymd: '2026-10-28', now: now, routines: routines.map((r) => RoutineToday(r.activity, 1, 1)).toList(), blocks: [_b('a', 'done'), _b('b', 'done'), _b('c', 'done'), _b('d', 'done'), _b('e', 'pending')]);
    expect(badgeToday(_state('semaine-solide', value: 3), held).stake, TodayStake.saved);
  });

  test('journée neutre : rien à tenir', () {
    final t = badgeToday(_state('semaine-solide'), TodayFacts(ymd: '2026-10-28', now: now));
    expect(t.stake, TodayStake.none);
  });

  test('série : en jeu tant que pas cochée, le bloc qui la porte est rappelé', () {
    final cuisine = RoutineToday(_r('cuisine'), 0, 1);
    final ff = TodayFacts(ymd: '2026-10-28', now: now, routines: [cuisine], blocks: blocks);
    final t = badgeToday(_state('serie-cuisine', value: 2, tiers: const [3, 7], subject: 'cuisine'), ff);
    expect(t.stake, TodayStake.atRisk);
    expect(t.items.length, 2);
    expect(t.items[1].block?.id, 'e');
    expect(t.notes.last, contains('palier 3 j'));
    final done = badgeToday(_state('serie-cuisine', value: 2, subject: 'cuisine'),
        TodayFacts(ymd: '2026-10-28', now: now, routines: [RoutineToday(_r('cuisine'), 1, 1)]));
    expect(done.stake, TodayStake.saved);
    expect(badgeToday(_state('serie-zzz', subject: 'zzz'), ff).stake, TodayStake.none);
  });

  test('marée haute : pas pointé = en jeu, pointé ≥ 4 = tenu, < 4 = perdu aujourd\'hui', () {
    MoodMark m(int v) => MoodMark(at: now, ymd: '2026-10-28', kind: kMoodElan, value: v);
    expect(badgeToday(_state('maree-haute', value: 6), f).stake, TodayStake.atRisk);
    expect(badgeToday(_state('maree-haute', value: 6), f).notes.last, contains('7ᵉ jour'));
    expect(badgeToday(_state('maree-haute', value: 6), TodayFacts(ymd: '2026-10-28', now: now, elanMarks: [m(4)])).stake, TodayStake.saved);
    expect(badgeToday(_state('maree-haute', value: 6), TodayFacts(ymd: '2026-10-28', now: now, elanMarks: [m(3)])).stake, TodayStake.lostToday);
    expect(badgeToday(_state('barometre', tiers: const [30]), f).items.single.kind, GapKind.elan);
  });

  test('badgesInPlay : seules les suites en jeu', () {
    final deck = BadgeDeck([
      _state('semaine-solide', value: 2),
      _state('maree-haute', value: 6),
      _state('journee-parfaite', tiers: const [1]),
      _state('serie-lecture', value: 2, subject: 'lecture'),
      _state('serie-cafe', value: 2, subject: 'cafe'),
    ]);
    expect(badgesInPlay(deck, f).map((e) => e.$1.def.id).toList(), ['semaine-solide', 'maree-haute', 'serie-lecture']);
  });
}
