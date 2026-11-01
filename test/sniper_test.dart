import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

void main() {
  final lecture = Activity(id: 'lec', domainId: 'd', name: 'Lecture', goalMin: 30);
  final pompes = Activity(id: 'pom', domainId: 'd', name: 'Pompes', goalMin: 0);

  Stake timed(Activity a, int min, {bool loses = false, int w = 10, StakeGainKind k = StakeGainKind.halfDay}) => Stake(
        StakeGesture(key: 'activity:${a.id}', kind: StakeGestureKind.activity, title: a.name, costMin: min, activity: a),
        [StakeGain(kind: k, label: 'Montre suisse', weight: w, losesTonight: loses)],
      );
  Stake routine(Activity a, {bool loses = false, String label = 'Métronome · la dernière', int w = 22}) => Stake(
        StakeGesture(key: 'routine:${a.id}', kind: StakeGestureKind.routine, title: a.name, costMin: 5, activity: a),
        [StakeGain(kind: StakeGainKind.halfDay, label: label, weight: w, losesTonight: loses)],
      );
  Stake action(String id, int? est, {int w = 24}) => Stake(
        StakeGesture(key: 'action:$id', kind: StakeGestureKind.action, title: id, costMin: est ?? 45, action: TaskAction(id: id, title: id, estimatedMin: est)),
        [StakeGain(kind: StakeGainKind.focus, label: 'Parole tenue', weight: w)],
      );

  test('durée exacte : activité = le manque, action = estimé × facteur, routine = +n', () {
    expect(sniperTargetOf(timed(lecture, 37))!.minutes, 37);
    expect(sniperTargetOf(action('a', 12), factor: 1.2)!.minutes, 15);
    expect(sniperTargetOf(action('b', null))!.minutes, 45);
    final r = sniperTargetOf(routine(pompes), routineLeft: {'pom': 3})!;
    expect(r.minutes, 0);
    expect(r.delta, 3);
    expect(r.durLabel, '+3');
  });

  test('un bloc ou une routine sans autre enjeu ne sont pas des cibles', () {
    final b = Stake(StakeGesture(key: 'block:x', kind: StakeGestureKind.block, title: 'x', costMin: 30), [const StakeGain(kind: StakeGainKind.hunt, label: 'h', weight: 20)]);
    expect(sniperTargetOf(b), isNull);
    final plain = Stake(StakeGesture(key: 'routine:pom', kind: StakeGestureKind.routine, title: 'Pompes', costMin: 5, activity: pompes),
        [const StakeGain(kind: StakeGainKind.routine, label: '0 / 1', weight: 4)]);
    expect(sniperTargetOf(plain), isNull);
  });

  test('ordre : se perd ce soir, palier ce soir, puis gain par minute', () {
    final plan = planSniper(stakes: [
      timed(lecture, 37, w: 22),
      routine(pompes, label: 'Métronome · palier 20 ce soir'),
      action('devis', 15, w: 32),
      timed(Activity(id: 'r', domainId: 'd', name: 'Rédiger', goalMin: 20), 23, loses: true),
    ], budgetMin: 300);
    expect(plan.aimed.map((t) => t.title).toList(), ['Rédiger', 'Pompes', 'devis', 'Lecture']);
  });

  test('budget : ce qui ne tient plus passe hors de portée, pauses comprises', () {
    final plan = planSniper(stakes: [timed(lecture, 37, w: 30), action('devis', 15, w: 10), action('long', 90)], budgetMin: 50, untilMin: 18 * 60);
    expect(plan.aimed.map((t) => t.title), ['Lecture']);
    expect(plan.outOfReach.map((m) => m.reason), containsAll(['ne tient plus avant 18:00', 'plus d’une heure · pour l’Offensive']));
    final fits = planSniper(stakes: [timed(lecture, 37, w: 30), action('devis', 10, w: 10)], budgetMin: 49);
    expect(fits.aimed.length, 2);
    expect(fits.totalMin, 49);
  });

  test('temps libre : jusqu’au prochain bloc à faire, hors blocs de temps', () {
    final blocks = [
      ScheduleBlock(id: 'a', startTime: '14:00', durationMin: 60, title: 'passé'),
      ScheduleBlock(id: 'b', startTime: '16:00', durationMin: 90, title: 'Petites choses', timeBlock: 'small'),
      ScheduleBlock(id: 'c', startTime: '18:00', durationMin: 60, title: 'Cours CM'),
    ];
    final b = sniperBudget(blocks: blocks, nowMin: 15 * 60 + 50, endMin: 22 * 60);
    expect(b.minutes, 130);
    expect(b.until?.id, 'c');
    final none = sniperBudget(blocks: const [], nowMin: 20 * 60, endMin: 22 * 60);
    expect(none.minutes, 120);
    expect(none.until, isNull);
  });

  test('précision et badge', () {
    expect(sniperPrecision(94, 96), 98);
    expect(sniperPrecision(37, 37), 100);
    ChainRun run(int done, int total) => ChainRun(date: '2026-11-01', startedAt: DateTime(2026), endedAt: DateTime(2026), doneCount: done, total: total, completed: true, kind: kSniperKind);
    expect(sniperCounts(run(3, 3)), isTrue);
    expect(sniperCounts(run(4, 5)), isFalse);
    expect(sniperCounts(run(2, 2)), isFalse);
  });

  test('écarter retire vraiment la cible ; un hors de portée n’entre que si on l’ajoute', () {
    final stakes = [timed(lecture, 30, w: 30), timed(Activity(id: 'b', domainId: 'd', name: 'B', goalMin: 10), 30, w: 20), timed(Activity(id: 'c', domainId: 'd', name: 'C', goalMin: 10), 30, w: 10)];
    final base = planSniper(stakes: stakes, budgetMin: 64);
    expect(base.aimed.map((t) => t.title), ['Lecture', 'B']);
    expect(base.totalMin, 62);
    final ex = adjustPlan(base, excluded: {'activity:lec'});
    expect(ex.aimed.map((t) => t.title), ['B']);
    expect(ex.totalMin, 30);
    final c = base.outOfReach.single.target;
    expect(fitsPlan(ex, c), isTrue);
    final added = adjustPlan(base, excluded: {'activity:lec'}, added: {c.key});
    expect(added.aimed.map((t) => t.title), ['B', 'C']);
    expect(added.outOfReach, isEmpty);
    expect(fitsPlan(base, c), isFalse);
  });

  test('ajuster le tir : mini-tirs de routine, minutes d’une activité, ordre stable', () {
    final r = sniperTargetOf(routine(pompes), routineLeft: {'pom': 20})!;
    expect(sniperStep(r), 5);
    expect(stepAmount(r, up: true), isNull);
    expect(stepAmount(r, up: false), 15);
    final mini = r.withAmount(10);
    expect(mini.isMini, isTrue);
    expect(mini.leftAfter, 10);
    expect(mini.durLabel, '+10');
    expect(stepAmount(mini, up: true), 15);
    final eau = sniperTargetOf(routine(Activity(id: 'eau', domainId: 'd', name: 'Eau', goalMin: 0)), routineLeft: {'eau': 6})!;
    expect(sniperStep(eau), 1);
    expect(stepAmount(eau.withAmount(1), up: false), isNull);
    final cuisiner = sniperTargetOf(timed(lecture, 37))!;
    expect(stepAmount(cuisiner, up: false), 35);
    expect(stepAmount(cuisiner, up: true), 40);
    expect(cuisiner.withAmount(40).isMini, isFalse);
    expect(cuisiner.withAmount(20).isMini, isTrue);
    expect(stepAmount(cuisiner.withAmount(60), up: true), isNull);
    expect(stepAmount(sniperTargetOf(action('a', 12))!.withAmount(5), up: false), isNull);
    expect(sniperTargetOf(action('a', 12))!.withAmount(5).isMini, isFalse);

    final base = planSniper(stakes: [timed(lecture, 30, w: 30), routine(pompes, w: 22)], budgetMin: 60, routineLeft: {'pom': 20});
    final order = base.aimed.map((t) => t.key).toList();
    final adj = adjustPlan(base, amounts: {'activity:lec': 10, 'routine:pom': 5});
    expect(adj.aimed.map((t) => t.key).toList(), order);
    expect(adj.aimed.firstWhere((t) => t.key == 'activity:lec').minutes, 10);
    expect(adj.aimed.firstWhere((t) => t.key == 'routine:pom').delta, 5);
    expect(adj.totalMin, 10 + 1 + kSniperPauseMin);
    final big = adj.aimed.firstWhere((t) => t.key == 'activity:lec').withAmount(60);
    expect(fitsPlan(adj, big), isFalse);
    expect(fitsPlan(adj, big.withAmount(55)), isTrue);
  });

  test('badge Sniper : 3 cibles pleines, les mini-tirs ne comptent pas parmi elles', () {
    ChainRun r(int done, int total, int? full) => ChainRun(date: '2026-11-01', startedAt: DateTime(2026), endedAt: DateTime(2026), doneCount: done, total: total, completed: true, kind: kSniperKind, fullCount: full);
    expect(sniperCounts(r(4, 4, 3)), isTrue);
    expect(sniperCounts(r(4, 4, 2)), isFalse);
    expect(sniperCounts(r(3, 3, null)), isTrue);
    expect(sniperCountLine(4, 4, full: 3), 'dont 3 pleines · session comptée');
    expect(sniperCountLine(4, 4, full: 2), 'dont 2 pleines · il faut 3 cibles pleines');
    expect(ChainRun.from(r(4, 4, 2).toJson()).fullCount, 2);
  });

  test('réordonner : l’ordre posé à la main fait foi, les nouvelles cibles viennent après', () {
    final b = Activity(id: 'b', domainId: 'd', name: 'B', goalMin: 10);
    final c = Activity(id: 'c', domainId: 'd', name: 'C', goalMin: 10);
    final base = planSniper(stakes: [timed(lecture, 10, w: 30), timed(b, 10, w: 20), timed(c, 10, w: 10)], budgetMin: 25);
    expect(base.aimed.map((t) => t.title), ['Lecture', 'B']);
    final mine = adjustPlan(base, order: ['activity:b', 'activity:lec']);
    expect(mine.aimed.map((t) => t.title), ['B', 'Lecture']);
    expect(mine.totalMin, base.totalMin);
    final more = adjustPlan(base, excluded: {'activity:lec'}, added: {'activity:c'}, order: ['activity:b']);
    expect(more.aimed.map((t) => t.title), ['B', 'C']);
    expect(adjustPlan(base).aimed.map((t) => t.title), ['Lecture', 'B']);
  });

  test('routine à minuteur : on règle la durée, pas les coches', () {
    final louanges = Activity(id: 'lou', domainId: 'd', name: 'Louanges', goalMin: 0, timerMin: 15);
    final t = sniperTargetOf(routine(louanges), routineLeft: {'lou': 1})!;
    expect(t.timedRoutine, isTrue);
    expect(t.amount, 15);
    expect(stepAmount(t, up: false), 10);
    expect(stepAmount(t, up: true), 20);
    final short = t.withAmount(10);
    expect(short.minutes, 10);
    expect(short.delta, 1);
    expect(short.isMini, isFalse);
    expect(short.durLabel, '10 min');
  });
}
