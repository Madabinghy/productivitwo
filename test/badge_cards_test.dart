import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';
import 'package:productivitwo_v1/widgets/card_reveal.dart';

void main() {
  BadgeState st(List<int> tiers, int level, num value, {BadgeFamily f = BadgeFamily.discipline, String unitLong = ''}) =>
      BadgeState(def: BadgeDef(id: 'x$level$value', family: f, name: 'Sniper', symbol: 'crosshair', tiers: tiers, unitLong: unitLong), level: level, value: value);

  test('rareté : 5 paliers = bronze, bronze, argent, or, légendaire', () {
    expect([for (var l = 1; l <= 5; l++) rarityOf(st(const [3, 7, 21, 66, 100], l, 0))],
        [CardRarity.bronze, CardRarity.bronze, CardRarity.argent, CardRarity.or, CardRarity.legend]);
    expect([for (var l = 1; l <= 3; l++) rarityOf(st(const [1, 5, 15], l, 0))], [CardRarity.bronze, CardRarity.argent, CardRarity.legend]);
    expect(rarityOf(st(const [1], 1, 1)), CardRarity.or);
    expect(rarityOf(st(const [1, 5, 15], 0, 3)), CardRarity.none);
    expect(rarityLadder(st(const [5, 20, 50, 100], 0, 0).def), [CardRarity.bronze, CardRarity.argent, CardRarity.or, CardRarity.legend]);
  });

  test('faces, indice, ordre de l’album', () {
    final won = st(const [1, 5, 15], 2, 6);
    final started = st(const [1, 5, 15], 0, 0.5);
    final hidden = st(const [1, 5, 15], 0, 0, unitLong: 'sessions sans cible manquée');
    expect(faceOf(won), CardFace.won);
    expect(faceOf(started), CardFace.started);
    expect(faceOf(hidden), CardFace.hidden);
    expect(cardHint(hidden), '1 sessions sans cible manquée');
    expect(albumOrder([hidden, started, won]).map(faceOf).toList(), [CardFace.won, CardFace.started, CardFace.hidden]);
    final album = cardAlbum(BadgeDeck([won, started, hidden, st(const [3, 7], 2, 7, f: BadgeFamily.routines)]));
    expect(album.won, 1);
    expect(album.total, 3);
    expect(album.byRarity[CardRarity.argent], 1);
  });

  testWidgets('la carte : gagnée, commencée, de dos', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          BadgeCardView(state: st(const [1, 5, 15], 3, 15), width: 120),
          BadgeCardView(state: st(const [1, 5, 15], 0, 0.5), width: 120, footer: '0 / 1'),
          BadgeCardView(state: st(const [1, 5, 15], 0, 0, unitLong: 'sessions'), width: 120),
        ]),
      ),
    ));
    expect(find.text('LÉGENDAIRE'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('cartes à retourner : nouvelles et montées, la plus belle en dernier', () {
    final sniper = BadgeState(def: const BadgeDef(id: 'sniper', family: BadgeFamily.discipline, name: 'Sniper', symbol: 'crosshair', tiers: [1, 5, 15]), level: 2, value: 6);
    final watch = BadgeState(def: const BadgeDef(id: 'watch', family: BadgeFamily.days, name: 'Montre', symbol: 'watch', tiers: [5, 20, 50, 100]), level: 1, value: 6);
    final old = BadgeState(def: const BadgeDef(id: 'old', family: BadgeFamily.days, name: 'Vieux', symbol: 'sun', tiers: [1]), level: 1, value: 1);
    final deck = BadgeDeck([sniper, watch, old]);
    final cards = newCards(deck, {'sniper': 1, 'old': 1});
    expect(cards.map((c) => c.badge.def.id).toList(), ['watch', 'sniper']);
    expect(newCardLine(cards.first), 'Nouvelle carte');
    expect(newCardLine(cards.last), 'Passe en argent');
    expect(newCards(deck, seenOf(deck)), isEmpty);
  });

  testWidgets('révélation : de dos, retourner, la carte apparaît', (tester) async {
    tester.view.physicalSize = const Size(780, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final b = BadgeState(def: const BadgeDef(id: 'sniper', family: BadgeFamily.discipline, name: 'Sniper', symbol: 'crosshair', tiers: [1, 5, 15]), level: 1, value: 1);
    await tester.pumpWidget(MaterialApp(home: CardRevealScreen(cards: [NewCard(b, CardRarity.none)])));
    expect(find.text('Retourner'), findsOneWidget);
    await tester.tap(find.text('Retourner'));
    await tester.pumpAndSettle();
    expect(find.text('Carte bronze · Sniper'), findsOneWidget);
    expect(find.text('Fermer'), findsOneWidget);
  });

  test('récolte : les cartes qui ont avancé, paliers d’abord', () {
    const def = BadgeDef(id: 'serie', family: BadgeFamily.routines, name: 'Pompes', symbol: 'flame', tiers: [3, 7, 21], unit: 'j');
    const watch = BadgeDef(id: 'watch', family: BadgeFamily.days, name: 'Montre', symbol: 'watch', tiers: [5, 20]);
    const still = BadgeDef(id: 'still', family: BadgeFamily.days, name: 'Rien', symbol: 'sun', tiers: [5]);
    final deck = BadgeDeck([
      const BadgeState(def: def, level: 2, value: 8),
      const BadgeState(def: watch, level: 1, value: 9),
      const BadgeState(def: still, level: 0, value: 2),
    ]);
    final items = harvestOf(deck, {'serie': 7, 'watch': 6, 'still': 2}, {'serie': 2, 'watch': 0, 'still': 0});
    expect(items.map((h) => h.badge.def.id).toList(), ['watch', 'serie']);
    expect(harvestLabel(items.first), 'BRONZE');
    expect(harvestLabel(items.last), '+1 j');
  });
}
