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
}
