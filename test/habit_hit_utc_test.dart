import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  test('un hit écrit par le serveur (UTC) est relu à l’heure locale', () {
    final h = HabitHit.from({'id': 'h1', 'habitId': 'eau', 'ts': '2026-11-06T04:30:00.000Z'});
    expect(h.ts.isUtc, isFalse);
    expect(h.ts.toUtc(), DateTime.utc(2026, 11, 6, 4, 30));
  });
}
