import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/seasons.dart';
import 'package:productivitwo_v1/widgets/season_widgets.dart';

StrategicObjective poids() => StrategicObjective(
      id: 'poids',
      title: 'Prendre du muscle',
      domainId: 'sport',
      metric: ObjectiveMetric(label: 'Poids', unit: 'kg', startValue: 80, targetValue: 90),
      readings: [ObjectiveReading(date: '2026-10-30', value: 82)],
    );

void main() {
  test('fin de saison : n semaines pleines, un dimanche', () {
    expect(seasonEndFor('2026-11-02'), '2026-12-13'); // ouverte un lundi
    expect(seasonEndFor('2026-10-30'), '2026-12-13'); // un jeudi : la semaine entamée en plus
    expect(seasonEndFor('2026-11-02', weeks: 4), '2026-11-29');
  });

  test('objectif qui court au-delà de la saison : cible = sa ligne à la fin de la saison', () {
    final livres = StrategicObjective(
      id: 'livres',
      title: 'Lire 12 livres',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2027, 6, 30),
      metric: ObjectiveMetric(label: 'Livres', unit: 'livres', startValue: 0, targetValue: 12),
      readings: [ObjectiveReading(date: '2026-11-01', value: 2)],
    );
    // Ligne 0 → 12 du 1er septembre au 30 juin : un peu moins de 4 au 6 décembre.
    final t = seasonMetricTarget(livres, '2026-12-06')!;
    expect(t, greaterThan(3));
    expect(t, lessThan(4.5));
    expect(goalFor(livres, seasonEnd: '2026-12-06').target, t);
    expect(goalFor(livres).target, 12);
    // Objectif qui finit avant la saison : sa cible.
    expect(seasonMetricTarget(livres, '2027-07-04'), 12);
    // Saison ouverte avec la cible finale : relue sur la ligne.
    final s = withSeasonOpened(const [], [goalFor(livres)], '2026-11-09', weeks: 4).single;
    expect(effectiveSeasonGoal(s, s.goals.single, livres).target, seasonMetricTarget(livres, s.end));
    final v = seasonGoalView(s, s.goals.single, livres, todayYmd: '2026-11-10');
    expect(v.goal.target, seasonMetricTarget(livres, s.end));
    // Cible réglée à la main : intacte.
    final manual = s.goals.single.copyWith(target: 10);
    expect(effectiveSeasonGoal(s, manual, livres).target, 10);
  });

  test('ouvrir, saison en cours, reposer le cap, bilan à voir', () {
    final g = goalFor(poids());
    expect(g.kind, SeasonGoalKind.metric);
    expect(g.from, 82);
    expect(g.target, 90);
    var seasons = withSeasonOpened(const [], [g], '2026-11-02', weeks: 4);
    expect(seasons.single.n, 1);
    expect(currentSeason(seasons, '2026-11-20')!.goals.single.objectiveId, 'poids');
    expect(currentSeason(seasons, '2026-11-30'), isNull);
    expect(unseenBilan(seasons, '2026-11-30')!.n, 1);
    // Reposer le cap en cours de route : l'ancienne est close à hier.
    seasons = withSeasonOpened(withSeasonOpened(const [], [g], '2026-11-02'), [g], '2026-11-10');
    expect(seasons.first.end, '2026-11-09');
    expect(seasons.first.bilanSeen, isTrue);
    expect(seasons.last.n, 2);
    final back = parseSeasons([for (final s in seasons) s.toJson()]);
    expect(back.last.goals.single.target, 90);
    expect(back.last.legacy, isFalse);
  });

  test('une ancienne saison (chasses) est relue mais jamais en cours', () {
    final old = parseSeasons([
      {'n': 1, 'start': '2026-11-01', 'end': '2026-12-13', 'hunts': [{'badgeId': 'a', 'tier': 1}]},
    ]);
    expect(old.single.legacy, isTrue);
    expect(currentSeason(old, '2026-11-20'), isNull);
    expect(unseenBilan(old, '2026-12-20'), isNull);
    expect(old.single.toJson().containsKey('v'), isFalse);
  });

  test('métrique : sur la trajectoire, en retard, atteinte, manquée', () {
    final o = poids();
    final s = withSeasonOpened(const [], [goalFor(o)], '2026-11-02', weeks: 4).single; // 82 → 90 sur 28 j
    // À mi-saison, attendu 86 : 85,5 est dans les 10 % (0,8 kg), 84 est en retard.
    o.readings.add(ObjectiveReading(date: '2026-11-15', value: 85.5));
    var v = seasonGoalView(s, s.goals.single, o, todayYmd: '2026-11-15');
    expect(v.state, SeasonGoalState.onTrack);
    o.readings.last.value = 84;
    v = seasonGoalView(s, s.goals.single, o, todayYmd: '2026-11-15');
    expect(v.state, SeasonGoalState.behind);
    expect(v.label(), startsWith('−'));
    o.readings.add(ObjectiveReading(date: '2026-11-25', value: 90.2));
    expect(seasonGoalView(s, s.goals.single, o, todayYmd: '2026-11-26').state, SeasonGoalState.reached);
    o.readings.removeLast();
    final closed = seasonGoalView(s, s.goals.single, o, todayYmd: '2026-12-02');
    expect(closed.state, SeasonGoalState.missed);
    expect(closed.label(closed: true), '84 / 90 kg');
  });

  test('rythme : semaine au rythme des engagements', () {
    final pompes = Activity(id: 'pompes', domainId: 'sport', name: 'Pompes', role: ActivityRole.generic, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final o = StrategicObjective(id: 'r', title: 'Pompes tous les jours', routineCommitments: [ObjectiveRoutineCommitment(activityId: 'pompes')]);
    final s = withSeasonOpened(const [], [goalFor(o)], '2026-11-02').single;
    expect(s.goals.single.kind, SeasonGoalKind.rhythm);
    final hits = [for (var d = 2; d <= 4; d++) HabitHit(habitId: 'pompes', ts: DateTime(2026, 11, d, 9))];
    final v = seasonGoalView(s, s.goals.single, o, todayYmd: '2026-11-04', activities: [pompes], hits: hits);
    expect(v.state, SeasonGoalState.onTrack);
    expect(v.label(), '100 % du rythme');
  });

  test('badge : réussie avec 2 objectifs sur 3 tenus (figé au bilan)', () {
    expect(seasonHeldNeeded(3), 2);
    expect(seasonHeldNeeded(1), 1);
    expect(seasonHeldNeeded(5), 4);
    const s = Season(n: 1, start: '2026-11-02', end: '2026-12-13', held: 2, total: 3);
    expect(s.won, isTrue);
    expect(wonSeasons([s, const Season(n: 2, start: '2026-12-14', end: '2027-01-24', held: 1, total: 3)]).length, 1);
  });

  testWidgets('Poser le cap : durée, objectifs cochés, lancer', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [Domain(id: 'sport', name: 'Sport')], activities: [], sessions: [], habitProgress: []), () {})..dayStartMin = 0;
    final o = poids();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonCapView(logic: logic, objectives: [o]))));
    await tester.pump();
    expect(find.text('Ton cap pour la suite'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('season-weeks-8')));
    await tester.tap(find.byKey(const ValueKey('season-goal-poids')));
    await tester.pump();
    expect(find.text('90 kg'), findsOneWidget);
    expect(find.text('Lancer la saison · 1 objectif'), findsOneWidget);
    // Lancer écrit dans Firebase (absent en test) : l'ouverture elle-même est testée plus haut (withSeasonOpened).
  });

  test('rythme semaine par semaine, jusqu\'à aujourd\'hui', () {
    final pompes = Activity(id: 'pompes', domainId: 'sport', name: 'Pompes', role: ActivityRole.generic, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final o = StrategicObjective(id: 'r', title: 'Pompes', routineCommitments: [ObjectiveRoutineCommitment(activityId: 'pompes')]);
    final s = withSeasonOpened(const [], [goalFor(o)], '2026-11-02', weeks: 4).single;
    final hits = [
      for (var d = 2; d <= 8; d++) HabitHit(habitId: 'pompes', ts: DateTime(2026, 11, d, 9)), // semaine 1 pleine
      HabitHit(habitId: 'pompes', ts: DateTime(2026, 11, 9, 9)), // semaine 2 : le lundi seulement
    ];
    final w = seasonRhythmWeeks(s, o, activities: [pompes], hits: hits, untilYmd: '2026-11-10');
    expect(w.length, 2);
    expect(w.first, 1.0);
    expect(w.last, closeTo(0.5, 0.01)); // 1 sur 2 attendus à mardi
  });

  testWidgets('Objectif de saison : trajectoire, chiffres, ce qui le fait avancer', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [Domain(id: 'sport', name: 'Sport')], activities: [], sessions: [], habitProgress: []), () {})..dayStartMin = 0;
    final o = poids();
    final today = logic.livedTodayYmd;
    logic.seasons = withSeasonOpened(const [], [goalFor(o)], today);
    final s = logic.seasons.single;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonGoalView2(logic: logic, season: s, goal: s.goals.single, objective: o))));
    await tester.pump();
    expect(find.text('Prendre du muscle'), findsOneWidget);
    expect(find.text('dernier relevé'), findsOneWidget);
    expect(find.textContaining('fin · 90 kg'), findsOneWidget);
  });

  testWidgets('Bilan : objectifs atteints, Garder · Ajuster · Laisser', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {})..dayStartMin = 0;
    final o = poids();
    o.readings.add(ObjectiveReading(date: '2026-10-31', value: 90.5));
    const s = Season(n: 2, start: '2026-10-05', end: '2026-11-01', goals: [SeasonGoal(objectiveId: 'poids', name: 'Prendre du muscle', kind: SeasonGoalKind.metric, from: 82, target: 90, unit: 'kg')]);
    logic.seasons = [s];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SeasonBilanView(logic: logic, season: s, objectives: [o]))));
    await tester.pump();
    expect(find.text('1 objectif sur 1 tenu'), findsOneWidget);
    expect(find.text('atteint'), findsOneWidget);
    expect(find.text('Garder'), findsOneWidget);
    expect(find.text('Lancer la saison 3'), findsOneWidget);
  });
}
