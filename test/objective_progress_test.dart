import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';

void main() {
  final o = StrategicObjective(
    id: 'o1',
    title: 'Sport',
    timeCommitments: [ObjectiveTimeCommitment(activityId: 'a1', weeklyMin: 700)],
  );
  final a = Activity(id: 'a1', name: 'Course', domainId: 'd1');
  Session s(DateTime start, int min) =>
      Session(id: start.toIso8601String(), activityId: 'a1', startAt: start, endAt: start.add(Duration(minutes: min)));

  test('weekElapsed = part de la semaine écoulée, jour courant compris', () {
    final mon = computeObjectiveProgress(o, [a], const [], const [], DateTime(2026, 10, 19, 10)); // lundi
    expect(mon.weekElapsed, closeTo(1 / 7, 1e-9));
    final tue = computeObjectiveProgress(o, [a], const [], const [], DateTime(2026, 10, 20, 10)); // mardi
    expect(tue.weekElapsed, closeTo(2 / 7, 1e-9));
    final sun = computeObjectiveProgress(o, [a], const [], const [], DateTime(2026, 10, 25, 23)); // dimanche
    expect(sun.weekElapsed, closeTo(1, 1e-9));
  });

  test('onTrack = 70 % de l\'attendu au prorata de la semaine', () {
    final now = DateTime(2026, 10, 21, 18); // mercredi : attendu 300 min, seuil 210
    final ok = computeObjectiveProgress(o, [a], [s(DateTime(2026, 10, 19, 9), 210)], const [], now);
    expect(ok.items.single.onTrack, isTrue);
    expect(ok.items.single.pct, closeTo(0.3, 1e-9));
    final ko = computeObjectiveProgress(o, [a], [s(DateTime(2026, 10, 19, 9), 200)], const [], now);
    expect(ko.items.single.onTrack, isFalse);
  });
}
