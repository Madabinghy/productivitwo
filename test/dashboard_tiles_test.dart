import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/dashboard_tiles.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/dashboard_tiles.dart';

ScheduleBlock _b(String id, String start, int dur, {String status = 'pending', String? title}) =>
    ScheduleBlock(id: id, startTime: start, durationMin: dur, title: title ?? id, category: 'project', status: status);

void main() {
  final today = DateTime(2026, 10, 29);

  test('PROGRAMME : blocs vivants, faits, en cours et ensuite', () {
    final t = programTile([
      _b('Café', '07:00', 30, status: 'done'),
      _b('Contenu', '14:00', 120),
      _b('Séance CM', '16:30', 60),
      _b('Sauté', '10:00', 30, status: 'skipped'),
    ], 14 * 60 + 20)!;
    expect(t.value, '3 blocs · 1 fait');
    expect(t.strip.map((p) => p.mark), [TileMark.on, TileMark.current, TileMark.off]);
    expect(t.sub, 'en cours : Contenu jusqu’à 16:00 · ensuite : Séance CM 16:30');
    expect(programTile(const [], 600), isNull);
  });

  test('ROUTINES et OBJECTIFS', () {
    final r = routinesTile(done: 9, total: 18, toDoNow: ['Lire la Bible', 'Lecture', 'Pompes'], momentLabel: 'cet après-midi', seriesRunning: 3)!;
    expect(r.value, '9 / 18');
    expect(r.badge, '🔥 3');
    expect(r.sub, '3 à faire cet après-midi · Lire la Bible, Lecture…');
    final o = objectivesTile([('90 kg', .57), ('Bible', 1.0), ('Budget', 0.0), ('Lecture', null)], readingsDue: 1)!;
    expect(o.value, '2 / 4');
    expect(o.sub, '1 relevé à noter · Budget à 0 %, 90 kg à 57 %');
  });

  test('ACTIONS : visées aujourd’hui, faites, la première ouverte en tête', () {
    final p = Project(id: 'p', title: 'Pro', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
      ProjectTask(id: 't', title: 'T', startDate: DateTime(2026, 10, 1), actions: [
        TaskAction(id: 'a', title: 'Envoyer le devis', focusDate: today),
        TaskAction(id: 'b', title: 'Relire', focusDate: today, done: true),
        TaskAction(id: 'c', title: 'Plus tard', focusDate: DateTime(2026, 11, 2)),
      ]),
    ]);
    final t = actionsTile(projects: [p], activities: const [], today: today)!;
    expect(t.value, '2 visées');
    expect(t.sub, '1 faite · Envoyer le devis en tête');
  });

  test('BADGES et écran « Badges en jeu » : palier ce soir, série à sauver, proches', () {
    final def = BadgeDef(id: 'serie-L', family: BadgeFamily.routines, name: 'Lecture', symbol: 'flame', tiers: kRoutineTiers, unit: 'j', subjectId: 'L');
    final far = BadgeDef(id: 'actions', family: BadgeFamily.routines, name: 'Actions', symbol: 'x', tiers: const [500], unit: '', subjectId: 'x');
    final deck = BadgeDeck([BadgeState(def: def, level: 0, value: 2), BadgeState(def: far, level: 0, value: 305)]);
    final g = StakeGesture(key: 'routine:L', kind: StakeGestureKind.routine, title: 'Lecture', costMin: 5);
    final g2 = StakeGesture(key: 'routine:B', kind: StakeGestureKind.routine, title: 'Bible', costMin: 5);
    final board = StakeBoard(top: [
      Stake(g, const [StakeGain(kind: StakeGainKind.tierTonight, label: 'palier 3 j ce soir', weight: 50, sourceId: 'serie-L')]),
      Stake(g2, const [StakeGain(kind: StakeGainKind.seriesTonight, label: 'série 2 j → se perd ce soir', losesTonight: true, weight: 32, sourceId: 'serie-B')]),
    ]);
    final t = badgesTile(deck, board)!;
    expect(t.value, 'Lecture 3 j');
    expect(t.sub, 'palier ce soir · 1 série à sauver');
    final d = badgesInPlay(board, deck);
    expect(d.losing.length, 1);
    expect(d.tiers.length, 1);
    expect(d.near.map((b) => b.def.id), ['actions']); // Lecture est déjà en jeu
  });

  testWidgets('les tuiles s’affichent et ouvrent leur vue', (t) async {
    var opened = '';
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DashboardTiles(
      program: programTile([_b('Contenu', '14:00', 120)], 14 * 60 + 20),
      routines: routinesTile(done: 1, total: 2, toDoNow: const ['Lecture'], momentLabel: 'ce soir'),
      onRoutines: () => opened = 'routines',
    )))));
    expect(find.text('TON TABLEAU DE BORD'), findsOneWidget);
    expect(find.text('PROGRAMME'), findsOneWidget);
    await t.tap(find.text('ROUTINES'));
    expect(opened, 'routines');
  });
}
