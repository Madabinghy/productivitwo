import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/workouts.dart';

const bench = Exercise(id: 'bench', name: 'Développé couché', gear: 'banc');
const pushups = Exercise(id: 'push', name: 'Pompes', kind: ExerciseKind.bodyweight, restSec: 60);
const plank = Exercise(id: 'plank', name: 'Gainage', kind: ExerciseKind.duration, restSec: 45);

SetLog s(String ex, int reps, {double? kg, int? sec, int at = 0, int? rest}) =>
    SetLog(exerciseId: ex, reps: reps, weightKg: kg, seconds: sec, at: at, restSec: rest);

Workout w(String id, String ymd, int start, List<SetLog> sets, {String templateId = 'haut'}) =>
    Workout(id: id, templateId: templateId, name: 'Haut du corps', ymd: ymd, startAt: start, endAt: start + 52 * 60000, sets: sets);

void main() {
  final monday = w('w1', '2026-10-27', 1000, [
    s('bench', 10, kg: 40), s('bench', 10, kg: 40), s('bench', 10, kg: 40), s('bench', 9, kg: 40),
    s('push', 22), s('push', 18), s('push', 15),
    s('plank', 0, sec: 45), s('plank', 0, sec: 40),
  ]);
  final thursday = w('w2', '2026-10-30', 5000, [
    s('bench', 10, kg: 40), s('bench', 10, kg: 40), s('bench', 10, kg: 40), s('bench', 10, kg: 40),
  ]);

  test('aller-retour JSON : exercices, séances types, séances', () {
    final gym = Gym(
      exercises: {bench.id: bench, pushups.id: pushups},
      templates: {
        'haut': const WorkoutTemplate(id: 'haut', name: 'Haut du corps', place: kPlaceHome, items: [TemplateItem(exerciseId: 'bench', sets: 4, reps: 10, weightKg: 42.5)]),
      },
    );
    final back = parseGym(gym.toJson());
    expect(back.exercises['bench']!.gear, 'banc');
    expect(back.exercises['push']!.kind, ExerciseKind.bodyweight);
    expect(back.exercises['push']!.restSec, 60);
    expect(back.templates['haut']!.place, kPlaceHome);
    expect(back.templates['haut']!.items.single.weightKg, 42.5);
    final wk = Workout.fromJson(monday.toJson())!;
    expect(wk.sets.length, 9);
    expect(wk.sets.last.seconds, 40);
    expect(parseGym(null).exercises, isEmpty);
  });

  test('un nom déjà connu retrouve son exercice, sans accents ni casse', () {
    final gym = Gym(exercises: {bench.id: bench});
    expect(exerciseByName(gym, 'developpe  COUCHÉ')?.id, 'bench');
    expect(exerciseByName(gym, 'Squat'), isNull);
  });

  test('la dernière fois : séries de l\'exercice et dernière séance de la séance type', () {
    expect(lastSetsOf('bench', [monday, thursday]).length, 4);
    expect(lastSetsOf('bench', [monday, thursday]).last.reps, 10);
    expect(lastSetsOf('push', [monday, thursday]).length, 3);
    expect(lastSetsOf('bench', [monday, thursday], beforeMs: 5000).last.reps, 9);
    expect(lastWorkoutOf('haut', [monday, thursday])!.id, 'w2');
  });

  test('poids proposé : toutes les séries faites → un pas de plus, sinon le même', () {
    const item = TemplateItem(exerciseId: 'bench', sets: 4, reps: 10, weightKg: 40);
    expect(suggestedWeight(bench, item, lastSetsOf('bench', [monday])), 40);
    expect(suggestedWeight(bench, item, lastSetsOf('bench', [monday, thursday])), 42.5);
    expect(suggestedWeight(bench, item, const []), 40);
    expect(suggestedWeight(pushups, const TemplateItem(exerciseId: 'push'), const []), isNull);
    final p = plannedSet(bench, item, lastSetsOf('bench', [monday, thursday]), 0);
    expect(p.weightKg, 42.5);
    expect(p.reps, 10);
    final d = plannedSet(plank, const TemplateItem(exerciseId: 'plank', sets: 3, reps: 45), const [], 0);
    expect(d.seconds, 45);
    expect(d.reps, 0);
  });

  test('mesures : volume, répétitions, repos moyen, meilleure série, record', () {
    expect(volumeOf(monday.sets), 40 * 39);
    expect(repsOf(monday.sets), 39 + 55);
    expect(avgRestSec([s('bench', 10, rest: 90), s('bench', 10, rest: 100), s('bench', 10)]), 95);
    expect(avgRestSec(const []), isNull);
    expect(bestSet(monday.sets.where((x) => x.exerciseId == 'bench'))!.reps, 10);
    expect(isRecord(s('bench', 10, kg: 42.5), [monday, thursday], beforeMs: 9000), isTrue);
    expect(isRecord(s('bench', 10, kg: 40), [monday, thursday], beforeMs: 9000), isFalse);
    expect(isRecord(s('squat', 10, kg: 60), [monday], beforeMs: 9000), isFalse, reason: 'la première fois n\'est pas un record');
    expect(isRecord(s('push', 25), [monday], beforeMs: 9000), isTrue);
  });

  test('écart avec la fois d\'avant, en une étiquette', () {
    expect(compareExercise([s('b', 10, kg: 42.5)], [s('b', 10, kg: 40)]).label, '+2,5 kg');
    expect(compareExercise([s('b', 12), s('b', 12)], [s('b', 12), s('b', 10)]).label, '+2 reps');
    expect(compareExercise([s('b', 10)], [s('b', 10)]).kind, DeltaKind.same);
    expect(compareExercise([s('p', 0, sec: 30)], [s('p', 0, sec: 40)]).label, '−10 s');
    expect(compareExercise([s('b', 10)], const []).kind, DeltaKind.first);
  });

  test('bilan d\'une séance face à la même séance type', () {
    final friday = w('w3', '2026-10-31', 9000, [
      s('bench', 10, kg: 42.5), s('bench', 10, kg: 42.5), s('bench', 10, kg: 42.5), s('bench', 10, kg: 42.5),
      s('push', 25, rest: 60), s('push', 19, rest: 62), s('push', 16, rest: 61),
    ]);
    final sum = summarize(friday, [monday, thursday, friday]);
    expect(sum.volume, 1700);
    expect(sum.volumeDeltaPct, 6);
    expect(sum.records, 2);
    expect(sum.byExercise['bench']!.label, '+2,5 kg');
    expect(sum.byExercise['push']!.label, '+5 reps');
    expect(sum.avgRest, 61);
    expect(sum.durationMin, 52);
  });

  test('semaine, mois : séances par période et par séance type', () {
    final legs = Workout(id: 'w4', templateId: 'jambes', name: 'Jambes', ymd: '2026-10-29', startAt: 3000, sets: [s('squat', 8, kg: 60)]);
    final empty = Workout(id: 'w5', name: 'Vide', ymd: '2026-10-29', startAt: 3500);
    final week = workoutsBetween([monday, thursday, legs, empty], '2026-10-27', '2026-11-02');
    expect(week.map((x) => x.id), ['w1', 'w4', 'w2']);
    expect(countByName(week).first.key, 'Haut du corps');
    expect(countByName(week).first.value, 2);
  });

  test('libellés', () {
    expect(kgLabel(42.5), '42,5');
    expect(kgLabel(40), '40');
    expect(restLabel(45), '45 s');
    expect(restLabel(90), '1 min 30');
    expect(restLabel(120), '2 min');
    expect(setLabel(s('b', 10, kg: 42.5)), '10 × 42,5 kg');
    expect(setLabel(s('p', 22)), '22');
    expect(setLabel(s('g', 0, sec: 45)), '45 s');
    expect(itemLabel(bench, const TemplateItem(exerciseId: 'bench', sets: 4, reps: 10, weightKg: 42.5)), '4 × 10 à 42,5 kg · repos 1 min 30');
    expect(itemLabel(pushups, const TemplateItem(exerciseId: 'push', sets: 3)), '3 × max · poids du corps · repos 1 min');
  });

  test('lot 3 : historique d\'un exercice, courbes, refaire, période', () {
    final h = exerciseHistory('bench', [thursday, monday]);
    expect(h.map((x) => x.workout.id), ['w1', 'w2']);
    expect(h.last.topKg, 40);
    expect(curveValue(h.first, ExerciseCurve.volume), 40 * 39);
    expect(curveValue(h.first, ExerciseCurve.rest), isNull);
    expect(curveValue(exerciseHistory('plank', [monday]).single, ExerciseCurve.reps), 85);
    expect(setsLine(h.first.sets), '10, 10, 10, 9 à 40 kg');
    expect(setsLine([s('p', 22), s('p', 18)]), '22, 18');
    final items = itemsFromWorkout(monday);
    expect(items.map((i) => i.exerciseId), ['bench', 'push', 'plank']);
    expect(items.first.sets, 4);
    expect(items.first.weightKg, 40);
    expect(items.last.reps, 45);
    final p = periodSummary([monday, thursday]);
    expect(p.count, 2);
    expect(p.minutes, 104);
    expect(volumeLabel(14200), '14 200 kg');
    expect(volumeLabel(980), '980 kg');
  });
}
