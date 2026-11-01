import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';

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
}
