import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/collection_badges.dart';
import 'package:productivitwo_v1/widgets/collection_badge_view.dart';
import 'package:productivitwo_v1/widgets/card_reveal.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';

BadgeState st(String id, BadgeFamily f, List<int> tiers, int level) =>
    BadgeState(def: BadgeDef(id: id, family: f, name: id, symbol: 'sun', tiers: tiers), level: level, value: level == 0 ? 0 : tiers[level - 1]);

void main() {
  test('points : bronze 1 · argent 2 · or 3 · légendaire 5, séries comprises', () {
    final deck = BadgeDeck([
      st('a', BadgeFamily.discipline, const [1, 5, 15], 1), // bronze 1
      st('b', BadgeFamily.discipline, const [1, 5, 15], 3), // légendaire 5
      st('c', BadgeFamily.days, const [1], 1), // or 3
      st('serie', BadgeFamily.routines, const [3, 7, 21, 66, 100], 3), // argent 2
      st('d', BadgeFamily.days, const [5, 20], 0),
    ]);
    expect(collectionPoints(deck), 11);
    final all = collectionBadges(deck);
    final collector = all.firstWhere((b) => b.id == 'collector');
    expect(collector.level, 1);
    expect(collector.next, 25);
    expect(all.firstWhere((b) => b.id == 'gold-case').value, 2);
    expect(all.firstWhere((b) => b.id == 'legend').level, 1);
    expect(all.any((b) => b.id == 'family-routines'), isFalse);
  });

  test('famille au complet : argent quand tout est gagné, or quand tout est en or', () {
    final none = collectionBadges(BadgeDeck([st('a', BadgeFamily.discipline, const [1, 5, 15], 1), st('b', BadgeFamily.discipline, const [1, 5], 0)]))
        .firstWhere((b) => b.id == 'family-discipline');
    expect(none.level, 0);
    expect(none.missing, ['b']);
    expect(none.figure, '1 / 2');
    final silver = collectionBadges(BadgeDeck([st('a', BadgeFamily.discipline, const [1, 5, 15], 1), st('b', BadgeFamily.discipline, const [1], 1)]))
        .firstWhere((b) => b.id == 'family-discipline');
    expect(silver.level, 1);
    expect(silver.metal, CardRarity.argent);
    expect(silver.figure, '1 / 2 or');
    expect(silver.missing, ['a']);
    final gold = collectionBadges(BadgeDeck([st('a', BadgeFamily.discipline, const [1, 5, 15], 3), st('b', BadgeFamily.discipline, const [1], 1)]))
        .firstWhere((b) => b.id == 'family-discipline');
    expect(gold.level, 2);
    expect(gold.metal, CardRarity.or);
    expect(gold.complete, isTrue);
  });

  test('étagère et prochain badge', () {
    final all = collectionBadges(BadgeDeck([st('a', BadgeFamily.discipline, const [1, 5, 15], 3), st('b', BadgeFamily.days, const [1, 5], 0)]));
    expect(shelfOrder(all).first.acquired, isTrue);
    expect(nextCollectionBadge(all), isNotNull);
    expect(roman(3), 'III');
  });

  testWidgets('la plaque : nom, palier, chiffre', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CollectionPlaque(badge: CollectionBadge(id: 'collector', name: 'Collectionneur', symbol: 'cards', tiers: kCollectorTiers, value: 52, level: 3, unit: 'pts'), width: 150)),
    ));
    expect(find.text('COLLECTIONNEUR'), findsOneWidget);
    expect(find.text('Palier III'), findsOneWidget);
    expect(find.text('52 pts'), findsOneWidget);
  });

  testWidgets('un badge tombe : écusson, nom avec palier, sur l’étagère', (tester) async {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: CollectionDropScreen(badges: [CollectionBadge(id: 'collector', name: 'Collectionneur', symbol: 'cards', tiers: kCollectorTiers, value: 50, level: 3, unit: 'pts')]),
    ));
    expect(find.text('Collectionneur III'), findsOneWidget);
    expect(find.text('Sur l’étagère'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('une carte retournée dit ce qu’elle rapporte', (tester) async {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final b = st('sniper', BadgeFamily.discipline, const [1, 5, 15], 2);
    await tester.pumpWidget(MaterialApp(home: CardRevealScreen(cards: [NewCard(b, CardRarity.bronze)], points: 43)));
    await tester.tap(find.text('Retourner'));
    await tester.pumpAndSettle();
    expect(find.text('+1 pt · bronze → argent'), findsOneWidget);
    expect(find.text('Collectionneur III · 43 / 50 pts'), findsOneWidget);
  });

  test('elle compte pour : collectionneur, famille, écrin, légende', () {
    final card = st('a', BadgeFamily.discipline, const [1, 5, 15], 3);
    final deck = BadgeDeck([card, st('b', BadgeFamily.discipline, const [1, 5], 0)]);
    final feeds = cardFeeds(card, deck);
    expect(feeds.map((f) => f.$1.id).toList(), ['collector', 'family-discipline', 'gold-case', 'legend']);
    expect(feeds.first.$2, '+5 pts');
    expect(feeds[1].$2, '1 des 2');
    final todo = cardFeeds(deck.badges[1], deck);
    expect(todo.map((f) => f.$2).toList(), ['bronze = +1 pt', 'il la faut pour le compléter']);
  });

  testWidgets('une pochette vide : numéro et nom', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BadgeCardView(state: st('Plein jour', BadgeFamily.days, const [1], 0), width: 110, pocket: 9))));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Plein jour'), findsOneWidget);
  });

  testWidgets('ouvrir sa collection : tout retourner montre la grille', (tester) async {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cards = [for (var i = 0; i < 5; i++) NewCard(st('c$i', BadgeFamily.days, const [1], 1), CardRarity.none)];
    await tester.pumpWidget(MaterialApp(home: CardRevealScreen(cards: cards, points: 15, pack: true)));
    expect(find.text('TA COLLECTION · 1 / 5'), findsOneWidget);
    await tester.tap(find.text('Tout retourner'));
    await tester.pumpAndSettle();
    expect(find.text('5 cartes · 15 pts'), findsOneWidget);
    expect(find.text('Ranger dans l’album'), findsOneWidget);
  });

  test('feuille d’un badge : les cartes qu’il concerne', () {
    final deck = BadgeDeck([
      st('a', BadgeFamily.discipline, const [1, 5, 15], 3),
      st('b', BadgeFamily.discipline, const [1, 5], 0),
      st('c', BadgeFamily.days, const [1, 5], 1),
    ]);
    final all = {for (final b in collectionBadges(deck)) b.id: b};
    expect(cardsOfCollection(all['family-discipline']!, deck).map((c) => c.def.id), ['a', 'b']);
    expect(cardsOfCollection(all['collector']!, deck).map((c) => c.def.id), ['a', 'c']);
    expect(cardsOfCollection(all['legend']!, deck).map((c) => c.def.id), ['a']);
  });
}
