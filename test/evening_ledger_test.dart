import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/stakes_section.dart';

void main() {
  // Jeudi 29 oct. 2026, 21:10 ; journée vécue depuis 05:00.
  final now = DateTime(2026, 10, 29, 21, 10);
  final dayStart = DateTime(2026, 10, 29, 5);
  final lecture = BadgeDef(id: 'serie-L', family: BadgeFamily.routines, name: 'Lecture', symbol: 'flame', tiers: kRoutineTiers, unit: 'j', subjectId: 'L');
  final cafe = BadgeDef(id: 'serie-C', family: BadgeFamily.routines, name: 'Café', symbol: 'flame', tiers: kRoutineTiers, unit: 'j', subjectId: 'C');
  final deck = BadgeDeck([
    BadgeState(def: lecture, level: 1, value: 3, tierDates: [DateTime(2026, 10, 29, 20, 5)]),
    BadgeState(def: cafe, level: 1, value: 4, tierDates: [DateTime(2026, 10, 20)]),
  ]);
  final contenu = Activity(id: 'contenu', name: 'Contenu', domainId: 'd', type: 'time');
  final courir = Activity(id: 'courir', name: 'Courir', domainId: 'd', type: 'time');
  final salle = Activity(id: 'salle', name: 'Salle', domainId: 'd', type: 'time');
  final maths = Project(id: 'm', title: '5e — Maths', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
    ProjectTask(id: 't', title: 'Prépa', startDate: DateTime(2026, 10, 1), actions: [
      TaskAction(id: 'a', title: 'Préparer les supports', done: true, doneAt: DateTime(2026, 10, 29, 15)),
      TaskAction(id: 'b', title: 'Remplir la fiche', done: true, doneAt: DateTime(2026, 10, 29, 16)),
      TaskAction(id: 'c', title: 'Hier', done: true, doneAt: DateTime(2026, 10, 28, 16)),
    ]),
  ]);
  final objKg = StrategicObjective(id: 'kg', title: 'Atteindre 90 kg');
  final objGym = StrategicObjective(id: 'gym', title: 'Aller à la salle');
  final days = [
    ObjectiveDay(objective: objKg, times: [ObjectiveTimeToday(activity: courir, activityId: 'courir', weeklyMin: 120, doneTodayMin: 30, doneWeekMin: 67)], routines: const [], blocks: const [], nextActions: const []),
    ObjectiveDay(objective: objGym, times: [ObjectiveTimeToday(activity: salle, activityId: 'salle', weeklyMin: 120, doneTodayMin: 0, doneWeekMin: 0)], routines: const [], blocks: const [], nextActions: const []),
  ];
  final hygiene = StakeGesture(key: 'routine:h', kind: StakeGestureKind.routine, title: 'Hygiène du soir', costMin: 5);
  final board = StakeBoard(top: [Stake(hygiene, const [StakeGain(kind: StakeGainKind.routine, label: '0 / 1', weight: 4)])], won: const ['Série Café'], lost: const ['Budget']);
  final ledger = buildEveningLedger(
    board: board,
    deck: deck,
    projects: [maths],
    activities: [contenu, courir, salle],
    sessions: [
      Session(activityId: 'contenu', startAt: DateTime(2026, 10, 29, 14), endAt: DateTime(2026, 10, 29, 15, 52)),
      Session(activityId: 'courir', startAt: DateTime(2026, 10, 29, 18), endAt: DateTime(2026, 10, 29, 18, 30)),
      Session(activityId: 'courir', startAt: DateTime(2026, 10, 28, 18), endAt: DateTime(2026, 10, 28, 18, 30)),
    ],
    objectiveDays: days,
    dayStart: dayStart,
    now: now,
  );

  test('le soir commence à 19 h sur la journée vécue', () {
    expect(isEvening(18 * 60 + 59), isFalse);
    expect(isEvening(19 * 60), isTrue);
    expect(isEvening(24 * 60 + 30), isTrue);
  });

  test('AVANCÉ : palier du jour, séries tenues, actions par projet, temps', () {
    final titles = ledger.advanced.map((l) => '${l.figure}|${l.title}|${l.sub}').toList();
    expect(titles.first, '🏅|Lecture · palier 3 j|nouveau badge · prochain : 7 j');
    expect(titles, contains('✓|Série Café|tenu aujourd’hui'));
    expect(titles, contains('+2|5e — Maths|Préparer les supports, Remplir la fiche'));
    expect(titles.any((t) => t.startsWith('1h52|Contenu')), isTrue);
    expect(titles.any((t) => t.startsWith('30 min|Courir|Atteindre 90 kg')), isTrue);
  });

  test('LAISSÉ FILER, encore possible, demain en jeu', () {
    expect(ledger.slipped.map((l) => l.title), ['Budget', 'Salle · Aller à la salle']);
    expect(ledger.stillPossible, ['Hygiène du soir']);
    expect(ledger.tomorrow, contains('Café 5 / 7 j'));
    expect(ledger.won, 2);
    expect(ledger.lost, 1);
  });

  testWidgets('la carte du soir', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: EveningLedgerCard(ledger: ledger)))));
    expect(find.text('AVANCÉ AUJOURD’HUI'), findsOneWidget);
    expect(find.text('LAISSÉ FILER'), findsOneWidget);
    expect(find.text('ENCORE'), findsOneWidget);
    expect(find.textContaining('Encore possible ce soir'), findsOneWidget);
  });

  testWidgets('sur la page : carte du soir compacte et touchable', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: EveningLedgerCard(ledger: ledger, compact: true, onTap: () => tapped = true))));
    expect(find.text('AVANCÉ AUJOURD’HUI'), findsNothing);
    expect(find.text('GAGNÉS'), findsOneWidget);
    await t.tap(find.text('GAGNÉS'));
    expect(tapped, isTrue);
  });
}
