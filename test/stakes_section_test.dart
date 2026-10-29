import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/stakes_section.dart';

Stake _routine(String name, List<StakeGain> gains) => Stake(
    StakeGesture(key: 'routine:$name', kind: StakeGestureKind.routine, title: name, costMin: 5,
        activity: Activity(id: name, name: name, domainId: 'd', type: 'habit'), progress: '0 / 1'),
    gains);

void main() {
  final bible = _routine('Lire la Bible', const [
    StakeGain(kind: StakeGainKind.seriesTonight, label: 'série 2 j → se perd ce soir', losesTonight: true, weight: 32, gauge: (done: 2, after: 3, total: 7)),
    StakeGain(kind: StakeGainKind.objective, label: 'Bible · 1 page / jour', weight: 10),
  ]);
  final eau = _routine('Eau', const [StakeGain(kind: StakeGainKind.routine, label: '2 / 6 aujourd’hui', weight: 4)]);
  final board = StakeBoard(top: [bible], rest: [eau], won: const ['Série Café'], lost: const []);

  Future<void> pump(WidgetTester t, void Function(Stake) onRun) => t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: Column(children: [
        StakeScoreboard(board: board, elapsed: .58),
        StakesList(board: board, onRun: onRun),
      ])))));

  testWidgets('tableau : gagnés, en jeu, perdus et la journée', (t) async {
    await pump(t, (_) {});
    expect(find.text('GAGNÉS'), findsOneWidget);
    expect(find.text('3 enjeux'), findsOneWidget);
    expect(find.text('58 % de la journée passée'), findsOneWidget);
    expect(find.text('Série Café'), findsOneWidget);
  });

  testWidgets('une ligne = un geste avec ses gains ; tap = ouvert sur place ; bouton = geste', (t) async {
    final ran = <String>[];
    await pump(t, (s) => ran.add(s.gesture.key));
    expect(find.text('Lire la Bible · 0 / 1'), findsOneWidget);
    expect(find.text('série 2 j → se perd ce soir'), findsOneWidget);
    expect(find.text('CE QUE ÇA RAPPORTE  2'), findsNothing);
    await t.tap(find.text('Lire la Bible · 0 / 1'));
    await t.pumpAndSettle();
    expect(find.text('EN JEU · SE PERD CE SOIR'), findsOneWidget);
    expect(find.text('CE QUE ÇA RAPPORTE  2'), findsOneWidget);
    expect(find.text('2 → 3 / 7'), findsOneWidget);
    await t.tap(find.text('+1 · c’est fait'));
    expect(ran, ['routine:Lire la Bible']);
  });

  testWidgets('le reste est replié derrière « + n autres en jeu », rangé par famille', (t) async {
    await pump(t, (_) {});
    expect(find.text('ROUTINES DU JOUR'), findsNothing);
    await t.tap(find.textContaining('1 autre en jeu'));
    await t.pumpAndSettle();
    expect(find.text('ROUTINES DU JOUR'), findsOneWidget);
    expect(find.text('Eau · 0 / 1'), findsOneWidget);
  });

  test('part de la journée passée, bornée', () {
    expect(dayElapsed(8 * 60), 0);
    expect(dayElapsed(15 * 60), .5);
    expect(dayElapsed(25 * 60), 1);
  });
}
