import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  final now = DateTime(2026, 10, 26, 10);
  BadgeState s(String id, List<int> tiers, int level, num value, {String? subject, String unit = 'j', String unitLong = 'jours'}) =>
      BadgeState(def: BadgeDef(id: id, family: id.startsWith('serie-') ? BadgeFamily.routines : BadgeFamily.actions, name: id, symbol: 'flame', tiers: tiers, unit: unit, unitLong: unitLong, subjectId: subject), level: level, value: value);

  test('lecture et écriture des chasses dans data/meta', () {
    final raw = [
      {'badgeId': 'serie-med', 'tier': 4, 'since': '2026-10-20', 'targetDate': '2026-11-20'},
      {'badgeId': 'actions', 'tier': 5, 'since': '2026-10-21'},
      {'tier': 1},
      'x',
    ];
    final hunts = parseBadgeHunts(raw);
    expect(hunts.length, 2);
    expect(hunts.first.targetDate, '2026-11-20');
    expect(hunts.last.targetDate, isNull);
    expect(hunts.first.toJson(), raw.first);
    expect(parseBadgeHunts(null), isEmpty);
  });

  test('vues : reste, progression, rythme, attrapée', () {
    final deck = BadgeDeck([s('serie-med', kRoutineTiers, 3, 34, subject: 'med'), s('actions', kActionTiers, 3, 142, unit: 'actions', unitLong: 'actions')]);
    final views = huntViews([
      const BadgeHunt(badgeId: 'serie-med', tier: 4, since: '2026-10-20', targetDate: '2026-11-27'),
      const BadgeHunt(badgeId: 'actions', tier: 4, since: '2026-10-20', targetDate: '2026-11-25'),
      const BadgeHunt(badgeId: 'inconnu', tier: 1, since: '2026-10-20'),
      const BadgeHunt(badgeId: 'serie-med', tier: 9, since: '2026-10-20'),
    ], deck);
    expect(views.length, 2);
    final serie = views.first;
    expect(serie.tierValue, 66);
    expect(serie.remaining, 32);
    expect(serie.progress, closeTo(34 / 66, 1e-9));
    expect(serie.daysLeft(now), 32);
    expect(serie.paceLabel(now), '32 jours à tenir · d’ici 32 jours');
    expect(serie.caught, isFalse);
    final actions = views.last;
    expect(actions.tierValue, 250);
    expect(actions.remaining, 108);
    expect(actions.paceLabel(now), 'encore 108 actions · 4 par jour · d’ici 30 jours');
    expect(actions.lever().kind, LeverKind.action);
    expect(serie.lever(todayReached: false).text, 'Coche « serie-med » aujourd’hui');
    expect(serie.lever(todayReached: true).activityId, 'med');
  });

  test('attrapée quand le palier visé est atteint', () {
    final deck = BadgeDeck([s('serie-med', kRoutineTiers, 4, 70, subject: 'med')]);
    final caught = caughtHunts([const BadgeHunt(badgeId: 'serie-med', tier: 4, since: '2026-10-01')], deck);
    expect(caught.length, 1);
    expect(caughtHunts([const BadgeHunt(badgeId: 'serie-med', tier: 5, since: '2026-10-01')], deck), isEmpty);
    final h = newHunt(deck.badges.first, 5, now, targetDate: DateTime(2026, 12, 1));
    expect(h.since, '2026-10-26');
    expect(h.targetDate, '2026-12-01');
  });
}
