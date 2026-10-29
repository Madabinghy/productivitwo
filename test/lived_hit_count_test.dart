import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';

void main() {
  test('livedHitCount : hits depuis la bascule de la journée vécue', () {
    final hits = [
      HabitHit(habitId: 'eau', ts: DateTime(2026, 10, 29, 1)), // nuit → veille
      HabitHit(habitId: 'eau', ts: DateTime(2026, 10, 29, 9)),
      HabitHit(habitId: 'eau', ts: DateTime(2026, 10, 29, 14)),
      HabitHit(habitId: 'lecture', ts: DateTime(2026, 10, 29, 10)),
    ];
    expect(livedHitCount(hits, 'eau', DateTime(2026, 10, 29, 15), 300), 2);
    expect(livedHitCount(hits.take(1).toList(), 'eau', DateTime(2026, 10, 29, 2), 300), 1);
  });
}
