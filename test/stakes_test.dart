import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

Activity _habit(String id) => Activity(id: id, name: id, domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
Activity _time(String id) => Activity(id: id, name: id, domainId: 'd', type: 'time');
BadgeState _serie(String id, {required int value, int level = 0}) => BadgeState(
    def: BadgeDef(id: 'serie-$id', family: BadgeFamily.routines, name: id, symbol: 'flame', tiers: kRoutineTiers, unit: 'j', subjectId: id),
    level: level,
    value: value);

void main() {
  // Jeudi 29 oct. 2026, 16:40.
  final now = DateTime(2026, 10, 29, 16, 40);
  final bible = _habit('Lire la Bible'), lecture = _habit('Lecture'), pompes = _habit('Pompes'), tractions = _habit('Tractions');
  final cuisiner = _habit('Cuisiner'), cafe = _habit('Café'), eau = _habit('Eau');
  final courir = _time('Courir');
  final routines = [
    RoutineToday(bible, 0, 1),
    RoutineToday(lecture, 0, 1),
    RoutineToday(pompes, 0, 8),
    RoutineToday(tractions, 0, 4),
    RoutineToday(cuisiner, 0, 1),
    RoutineToday(cafe, 1, 1),
    RoutineToday(eau, 2, 6),
  ];
  final objBible = StrategicObjective(id: 'o-bible', title: 'Lire une page de la Bible par jour', routineCommitments: [ObjectiveRoutineCommitment(activityId: bible.id)]);
  final objKg = StrategicObjective(id: 'o-kg', title: 'Atteindre 90kg', timeCommitments: [ObjectiveTimeCommitment(activityId: courir.id, weeklyMin: 120)]);
  final days = [
    ObjectiveDay(objective: objBible, times: const [], routines: [bible], blocks: const [], nextActions: const []),
    ObjectiveDay(
        objective: objKg,
        times: [ObjectiveTimeToday(activity: courir, activityId: courir.id, weeklyMin: 120, doneTodayMin: 0, doneWeekMin: 37)],
        routines: const [],
        blocks: const [],
        nextActions: const []),
  ];
  final facts = TodayFacts(ymd: '2026-10-29', now: now, routines: routines, objectiveDays: days, objectives: [objBible, objKg]);
  final deck = BadgeDeck([
    _serie(bible.id, value: 2, level: 1), // série 2 j (palier 3 j déjà obtenu un jour), se perd ce soir
    _serie(lecture.id, value: 2), // palier 3 j ce soir
    _serie(pompes.id, value: 3, level: 1),
    _serie(tractions.id, value: 3, level: 1),
    _serie(cuisiner.id, value: 3, level: 1), // chassé
    _serie(cafe.id, value: 4, level: 1), // tenue aujourd'hui
    _serie(eau.id, value: 0), // pas de série : jamais en jeu à ce titre
  ]);
  final hunts = [const BadgeHunt(badgeId: 'serie-Cuisiner', tier: 2, since: '2026-10-20')];
  // Séance mardi 3 nov. (dans 5 j), prépa 2 / 5.
  final prep = ProjectTask(id: 'prep', title: '📝 Préparer — Séance du 3 nov', startDate: DateTime(2026, 10, 29), endDate: DateTime(2026, 11, 2), interventionRole: 'prep', actions: [
    TaskAction(id: 'p1', title: 'Relire le bilan', done: true),
    TaskAction(id: 'p2', title: 'Faire la fiche', done: true),
    TaskAction(id: 'p3', title: 'Préparer les supports', estimatedMin: 45),
    TaskAction(id: 'p4', title: 'Faire le Kahoot'),
    TaskAction(id: 'p5', title: 'Imprimer'),
  ]);
  final seance = ProjectTask(id: 'seance', title: '🎯 Mar 3 nov — Séance', startDate: DateTime(2026, 11, 3), endDate: DateTime(2026, 11, 3), isMilestone: true, interventionRole: 'session', groupLabel: 'S3');
  prep.groupLabel = 'S3';
  final maths = Project(id: 'maths', title: '5e — Mathématiques', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [prep, seance]);
  final visee = TaskAction(id: 'v1', title: 'Envoyer le devis', estimatedMin: 15, focusDate: DateTime(2026, 10, 29));
  final pro = Project(id: 'pro', title: 'Pro', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
    ProjectTask(id: 't', title: 'Devis', startDate: DateTime(2026, 10, 1), actions: [visee]),
  ]);

  StakeBoard board({int top = kStakesTop}) => buildStakeBoard(
        deck: deck,
        facts: facts,
        hunts: hunts,
        projects: [maths, pro],
        activities: [bible, lecture, pompes, tractions, cuisiner, cafe, eau, courir],
        top: top,
      );

  test('un geste = une ligne, avec tous ses gains (série + objectif pour Lire la Bible)', () {
    final b = board(top: 99);
    final bibleStake = [...b.top, ...b.rest].firstWhere((s) => s.gesture.key == 'routine:${bible.id}');
    expect(bibleStake.gains.map((g) => g.kind).toSet(), {StakeGainKind.seriesTonight, StakeGainKind.objective});
    expect(bibleStake.losesTonight, isTrue);
    expect(bibleStake.family, 'multi');
    expect([...b.top, ...b.rest].where((s) => s.gesture.key == 'routine:${bible.id}').length, 1);
  });

  test('palier ce soir, chasse, objectif en retard, séance, action visée : tous présents', () {
    final all = [...board(top: 99).top, ...board(top: 99).rest];
    final byKey = {for (final s in all) s.gesture.key: s};
    expect(byKey['routine:${lecture.id}']!.gains.single.kind, StakeGainKind.tierTonight);
    expect(byKey['routine:${lecture.id}']!.gains.single.label, 'palier 3 j ce soir');
    expect(byKey['routine:${cuisiner.id}']!.gains.single.weight, greaterThan(byKey['routine:${pompes.id}']!.gains.single.weight)); // chassée
    final run = byKey['activity:${courir.id}']!;
    expect(run.gains.single.kind, StakeGainKind.objective);
    expect(run.gains.single.label, contains('−32 min')); // 120 × 4 / 7 = 69 − 37
    expect(run.gesture.costMin, 32);
    final p3 = byKey['action:p3']!;
    expect(p3.gains.single.kind, StakeGainKind.session);
    expect(p3.gains.single.label, contains('prépa 2 / 5'));
    expect(byKey['action:v1']!.gains.single.kind, StakeGainKind.focus);
    // Eau : pas de série, rien d'autre → seulement « routine du jour » (bas de liste).
    expect(byKey['routine:${eau.id}']!.gains.single.kind, StakeGainKind.routine);
  });

  test('ordre : ce qui se perd ce soir d\'abord ; coupe à 5 ; deux séries « simples » au plus', () {
    final b = board();
    expect(b.top.length, 5);
    expect(b.top.first.losesTonight, isTrue);
    final simpleSeries = b.top.where((s) => s.family == 'series').length;
    expect(simpleSeries, lessThanOrEqualTo(kStakesFamilyCap));
    // En tête : Lecture (se perd ce soir + palier ce soir), puis Lire la Bible (série + objectif) et Cuisiner (série chassée).
    expect(b.top.first.gesture.key, 'routine:${lecture.id}');
    expect(b.top.take(3).map((x) => x.gesture.key).toSet(), {'routine:${lecture.id}', 'routine:${bible.id}', 'routine:${cuisiner.id}'});
    expect(b.top.take(3).every((x) => x.losesTonight), isTrue);
    // Une seule des deux séries simples Pompes / Tractions passe : la coupe à 5 et le plafond font le reste.
    expect(b.top.where((x) => x.gesture.key == 'routine:${pompes.id}' || x.gesture.key == 'routine:${tractions.id}').length, lessThanOrEqualTo(2));
    expect(b.inPlay, b.top.length + b.rest.length);
  });

  test('gagné / perdu : série tenue aujourd\'hui comptée, série à 0 jamais', () {
    final b = board();
    expect(b.won, contains('Série ${cafe.name}'));
    expect(b.won.any((w) => w.contains(eau.name)), isFalse);
    expect(b.lost, isEmpty);
  });

  test('sans deck (pas encore calculé) : objectifs, séances, visées et routines quand même', () {
    final b = buildStakeBoard(deck: null, facts: facts, projects: [maths, pro], activities: [courir]);
    final keys = [...b.top, ...b.rest].map((s) => s.gesture.key).toSet();
    expect(keys, containsAll(['activity:${courir.id}', 'action:p3', 'action:v1', 'routine:${bible.id}']));
  });

  test('rythme de la journée : tenus face à l’heure', () {
    expect(stakesPace(10, 29, .4).label, 'en retard de 2');
    expect(stakesPace(14, 29, .4).label, 'en avance de 2');
    expect(stakesPace(12, 29, .4).label, 'dans le rythme');
    expect(stakesPace(0, 0, .5).label, '');
  });
}
