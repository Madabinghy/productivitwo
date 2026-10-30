import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/seasons.dart';

BadgeState badge(String id, List<int> tiers, {int level = 0, num value = 0, List<DateTime?> dates = const []}) => BadgeState(
      def: BadgeDef(id: id, family: BadgeFamily.discipline, name: id, symbol: 'flame', tiers: tiers, unit: 'j'),
      level: level,
      value: value,
      tierDates: dates.isEmpty ? List.filled(tiers.length, null) : dates,
    );

void main() {
  test('fin de saison : six semaines pleines, un dimanche', () {
    expect(seasonEndFor('2026-11-02'), '2026-12-13'); // ouverte un lundi
    expect(seasonEndFor('2026-10-30'), '2026-12-13'); // un jeudi : la semaine entamée en plus
  });

  test('ouvrir, saison en cours, bilan à voir', () {
    var seasons = withSeasonOpened(const [], const [SeasonHunt(badgeId: 'a', tier: 1)], '2026-11-02');
    expect(seasons.single.n, 1);
    expect(currentSeason(seasons, '2026-11-20')!.n, 1);
    expect(currentSeason(seasons, '2026-12-14'), isNull);
    expect(unseenBilan(seasons, '2026-12-14')!.n, 1);
    seasons = withSeasonOpened(seasons, const [], '2026-12-14');
    expect(seasons.first.bilanSeen, isTrue);
    expect(seasons.last.n, 2);
    final back = parseSeasons([for (final s in seasons) s.toJson()]);
    expect(back.last.start, '2026-12-14');
    expect(back.first.bilanSeen, isTrue);
  });

  test('chasses : attrapée pendant la saison, lâchée, à pousser, manquée', () {
    const s = Season(n: 1, start: '2026-11-02', end: '2026-12-13', hunts: [
      SeasonHunt(badgeId: 'a', tier: 1),
      SeasonHunt(badgeId: 'b', tier: 2),
      SeasonHunt(badgeId: 'c', tier: 1),
    ], dropped: {'c'});
    final deck = BadgeDeck([
      badge('a', [3, 7], level: 1, value: 3, dates: [DateTime(2026, 11, 10), null]),
      badge('b', [3, 7], level: 1, value: 4, dates: [DateTime(2026, 10, 1), null]),
      badge('c', [5], value: 1),
    ]);
    final v = seasonViews(s, deck, '2026-11-30');
    expect(v[0].state, SeasonHuntState.caught);
    expect(v[1].state, SeasonHuntState.push); // 4 / 7 à 70 % du temps
    expect(v[2].state, SeasonHuntState.dropped);
    expect(seasonViews(s, deck, '2026-12-14')[1].state, SeasonHuntState.missed);
    expect(caughtCount(v), 1);
  });

  test('un palier obtenu avant la saison ne compte pas', () {
    const s = Season(n: 1, start: '2026-11-02', end: '2026-12-13', hunts: [SeasonHunt(badgeId: 'a', tier: 1)]);
    final deck = BadgeDeck([badge('a', [3], level: 1, value: 3, dates: [DateTime(2026, 10, 20)])]);
    expect(seasonViews(s, deck, '2026-11-05').single.state, isNot(SeasonHuntState.caught));
  });

  test('badge Saisons : saisons closes avec au moins deux chasses', () {
    final a = Activity(id: 'p', name: 'Pompes', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1));
    final hits = [for (var d = 1; d <= 25; d++) HabitHit(habitId: 'p', ts: DateTime(2026, 10, d, 9))];
    final seasons = [
      const Season(n: 1, start: '2026-10-01', end: '2026-10-26', hunts: [SeasonHunt(badgeId: 'serie-p', tier: 2), SeasonHunt(badgeId: 'serie-p', tier: 3)]),
    ];
    final deck = computeBadges(
      activities: [a],
      habitHits: hits,
      schedules: const [],
      projects: const [],
      objectives: const [],
      sessions: const [],
      now: DateTime(2026, 10, 30, 12),
      seasons: seasons,
    );
    final b = deck.byId('saisons')!;
    expect(b.value, 1); // série 7 j le 7 oct., 21 j le 21 oct. : deux chasses attrapées
    expect(b.level, 1);
  });

  test('propositions : prochain palier, à portée en six semaines', () {
    final deck = BadgeDeck([
      badge('serie-x', [3, 7, 21, 66, 100], level: 3, value: 34),
      badge('serie-y', [3, 7, 21, 66, 100], level: 2, value: 1),
      badge('reprise', [1, 5, 15], level: 1, value: 2),
      badge('deep-work', [3, 10, 30], level: 0, value: 0),
    ]);
    final picks = seasonPicks(deck);
    final ids = picks.map((p) => p.badge.def.id).toList();
    expect(ids, contains('serie-x')); // 66 j : encore 32 j
    expect(ids, contains('reprise'));
    expect(ids, isNot(contains('deep-work'))); // trop loin (0 %)
    expect(picks.firstWhere((p) => p.badge.def.id == 'serie-x').tier, 4);
  });

  test('propositions : toutes les routines, et les paliers tenables en six semaines', () {
    final deck = BadgeDeck([
      for (var i = 0; i < 9; i++) badge('serie-r$i', [3, 7, 21, 66, 100], level: 1, value: 4),
    ]);
    final picks = seasonPicks(deck);
    expect(picks.length, 9); // plus de coupe à quatre par groupe
    final p = picks.first;
    expect(p.tiers, [2, 3]); // 7 j et 21 j tiennent en 42 jours, pas 66
    expect(p.nextTier(2), 3);
    expect(p.nextTier(3), 2);
    expect(p.labelOf(3), 'serie-r0 · série 21 j');
  });
}
