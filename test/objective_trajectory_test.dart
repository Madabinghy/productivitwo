import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';

StrategicObjective _obj({ObjectiveMetric? metric, List<ObjectiveReading>? readings, int every = 7}) =>
    StrategicObjective(
      id: 'o1',
      title: '100 clients',
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 12, 10), // 70 jours
      metric: metric,
      readings: readings,
      checkInEvery: every,
      timeCommitments: [ObjectiveTimeCommitment(activityId: 'a1', weeklyMin: 300)],
    );

Session _s(String id, DateTime start, int min, {String act = 'a1'}) =>
    Session(id: id, activityId: act, startAt: start, endAt: start.add(Duration(minutes: min)));

void main() {
  test('sans relevé, l\'ancienneté se compte depuis le départ (première saisie)', () {
    final o = _obj(metric: ObjectiveMetric(label: 'clients', startValue: 10, targetValue: 100));
    final t = computeObjectiveTrajectory(o, const [], DateTime(2026, 10, 9));
    expect(t.daysSinceReading, 8);
    expect(t.readingDue, isTrue);
    expect(t.result!.latestValue, isNull);
    final t2 = computeObjectiveTrajectory(o, const [], DateTime(2026, 10, 3));
    expect(t2.daysSinceReading, 2);
    expect(t2.readingDue, isFalse);
    expect(computeObjectiveTrajectory(_obj(), const [], DateTime(2026, 10, 9)).daysSinceReading, isNull);
  });

  test('moyens : attendu linéaire, fait = minutes des activités engagées depuis le début', () {
    final o = _obj();
    final now = DateTime(2026, 10, 15, 12); // 2 semaines
    final t = computeObjectiveTrajectory(o, [
      _s('1', DateTime(2026, 10, 2, 9), 120),
      _s('2', DateTime(2026, 10, 9, 9), 180),
      _s('3', DateTime(2026, 9, 30, 9), 60), // avant le début : ignorée
      _s('4', DateTime(2026, 10, 10, 9), 60, act: 'autre'), // pas engagée
    ], now);
    expect(t.means.doneMin, 300);
    expect(t.means.expectedMin, 621); // 300 × 14,5 j / 7
    expect(t.means.totalMin, 3000); // 300 × 10 semaines
    expect(t.means.status, TrajectoryStatus.behind);
    expect(t.timePct, closeTo(14.5 / 70, 0.001));
    expect(t.result, isNull);
    expect(t.readingDue, isFalse); // pas de métrique
  });

  test('résultat : attendu sur la droite start → target, statut et écart', () {
    final m = ObjectiveMetric(label: 'Clients', unit: 'clients', startValue: 20, targetValue: 100);
    final now = DateTime(2026, 11, 5); // 35 j sur 70 → attendu 60
    final behind = computeObjectiveTrajectory(
        _obj(metric: m, readings: [ObjectiveReading(date: '2026-11-04', value: 40)]), [], now);
    expect(behind.result!.expectedValue, closeTo(60, 0.01));
    expect(behind.result!.latestValue, 40);
    expect(behind.result!.status, TrajectoryStatus.behind);
    expect(behind.result!.delta, closeTo(-20, 0.01));
    expect(behind.result!.pct, closeTo(0.25, 0.001));
    expect(behind.result!.expectedPct, closeTo(0.5, 0.001));
    expect(behind.daysSinceReading, 1);

    final ahead = computeObjectiveTrajectory(
        _obj(metric: m, readings: [ObjectiveReading(date: '2026-11-05', value: 75)]), [], now);
    expect(ahead.result!.status, TrajectoryStatus.ahead);

    final none = computeObjectiveTrajectory(_obj(metric: m), [], now);
    expect(none.result!.status, TrajectoryStatus.unknown);
    expect(none.result!.latestValue, isNull);
  });

  test('métrique décroissante : écart signé dans le sens du progrès', () {
    final m = ObjectiveMetric(label: 'Poids', unit: 'kg', startValue: 90, targetValue: 80);
    final now = DateTime(2026, 11, 5); // attendu 85
    final t = computeObjectiveTrajectory(
        _obj(metric: m, readings: [ObjectiveReading(date: '2026-11-05', value: 83)]), [], now);
    expect(t.result!.expectedValue, closeTo(85, 0.01));
    expect(t.result!.delta, closeTo(2, 0.01)); // 2 kg d'avance
    expect(t.result!.status, TrajectoryStatus.ahead);
  });

  test('relevé dû : depuis le dernier relevé, sinon depuis le début ; dernier du jour gagne', () {
    final m = ObjectiveMetric(label: 'x', targetValue: 10);
    expect(isReadingDue(_obj(metric: m), DateTime(2026, 10, 7)), isFalse); // 6 j
    expect(isReadingDue(_obj(metric: m), DateTime(2026, 10, 8)), isTrue); // 7 j
    final withReading = _obj(metric: m, readings: [ObjectiveReading(date: '2026-10-20', value: 3)]);
    expect(isReadingDue(withReading, DateTime(2026, 10, 24)), isFalse);
    expect(isReadingDue(withReading, DateTime(2026, 10, 27)), isTrue);
    expect(isReadingDue(_obj(metric: m, every: 3), DateTime(2026, 10, 4)), isTrue);

    final r1 = ObjectiveReading(date: '2026-10-20', value: 3, createdAt: DateTime(2026, 10, 20, 9));
    final r2 = ObjectiveReading(date: '2026-10-20', value: 5, createdAt: DateTime(2026, 10, 20, 18));
    expect(latestReading(_obj(metric: m, readings: [r2, r1]))!.value, 5);
    final up = upsertReading([r1], ObjectiveReading(date: '2026-10-20', value: 7));
    expect(up.length, 1);
    expect(up.single.value, 7);
  });

  test('courbe attendue : bornée en points, finit sur la cible', () {
    final m = ObjectiveMetric(label: 'x', startValue: 0, targetValue: 100);
    final pts = expectedCurve(m, DateTime(2026, 1, 1), DateTime(2026, 12, 31), maxPoints: 30);
    expect(pts.length, lessThanOrEqualTo(32));
    expect(pts.first.value, 0);
    expect(pts.last.value, 100);
    expect(pts.last.date, DateTime(2026, 12, 31));
  });

  test('modèle : aller-retour JSON', () {
    final o = _obj(
        metric: ObjectiveMetric(label: 'MRR', unit: '€', startValue: 100, targetValue: 500),
        readings: [ObjectiveReading(date: '2026-10-10', value: 150, note: 'premier client')]);
    final back = StrategicObjective.from(o.toJson());
    expect(back.metric!.targetValue, 500);
    expect(back.metric!.unit, '€');
    expect(back.readings.single.note, 'premier client');
    expect(back.checkInEvery, 7);
    expect(StrategicObjective.from({'id': 'z', 'title': 't'}).metric, isNull);
  });
}
