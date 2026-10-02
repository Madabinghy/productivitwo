import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/streak_logic.dart';

void main() {
  final today = DateTime(2026, 10, 2); // vendredi
  DateTime d(int daysAgo) => today.subtract(Duration(days: daysAgo));
  bool Function(DateTime) reachedExcept(Set<int> missedDaysAgo, {int since = 60}) =>
      (day) {
        final ago = today.difference(day).inDays;
        return ago <= since && !missedDaysAgo.contains(ago);
      };

  test('série simple, aujourd\'hui compte si fait', () {
    final r = computeStreak(today: today, reached: reachedExcept({}, since: 9));
    expect(r.streak, 10);
    expect(r.jokerAvailable, isTrue);
    expect(r.jokerDay, isNull);
  });

  test('aujourd\'hui pas encore fait : on part d\'hier, pas de joker consommé', () {
    final r = computeStreak(today: today, reached: reachedExcept({0}, since: 9));
    expect(r.streak, 9);
    expect(r.jokerAvailable, isTrue);
  });

  test('un jour raté couvert par le joker : la série tient, étiquette posée', () {
    // mardi (il y a 3 jours) raté
    final r = computeStreak(today: today, reached: reachedExcept({3}, since: 9));
    expect(r.streak, 9);
    expect(r.jokerDay, d(3));
    expect(r.jokerAvailable, isFalse);
  });

  test('deux ratés à moins de 7 jours : la série casse au second', () {
    final r = computeStreak(today: today, reached: reachedExcept({2, 5}, since: 20));
    expect(r.streak, 4); // auj., hier, il y a 3 et 4 j ; il y a 2 j couvert ; il y a 5 j casse
    expect(r.jokerDay, d(2));
  });

  test('deux ratés à 7 jours ou plus d\'écart : deux jokers, la série tient', () {
    final r = computeStreak(today: today, reached: reachedExcept({3, 10}, since: 20));
    expect(r.streak, 19);
    expect(r.jokerDay, d(3));
    expect(r.jokerAvailable, isFalse);
  });

  test('joker consommé il y a 8 jours : de nouveau disponible', () {
    final r = computeStreak(today: today, reached: reachedExcept({8}, since: 20));
    expect(r.streak, 20);
    expect(r.jokerDay, isNull);
    expect(r.jokerAvailable, isTrue);
  });

  test('série vide : un raté hier sans rien derrière ne compte pas comme joker', () {
    final r = computeStreak(today: today, reached: (_) => false);
    expect(r.streak, 0);
    expect(r.jokerDay, isNull);
    expect(r.jokerAvailable, isTrue);
  });

  test('jour gelé (ancien gel) enjambé sans consommer le joker', () {
    final r = computeStreak(
        today: today,
        reached: reachedExcept({4}, since: 9),
        frozen: (day) => today.difference(day).inDays == 4);
    expect(r.streak, 9);
    expect(r.jokerAvailable, isTrue);
  });
}
