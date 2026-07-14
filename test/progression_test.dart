import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/progression.dart';

Activity _routine({
  int palier = 3,
  int? cap = 50,
  String? stepUpdatedWeek,
  DateTime? createdAt,
}) =>
    Activity(
      id: 'r1',
      name: 'Pompes',
      domainId: 'd1',
      type: 'habit',
      habitFreq: HabitFreq.daily,
      habitTarget: palier,
      finalTarget: cap,
      stepUpdatedWeek: stepUpdatedWeek,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      unit: 'pompes',
    );

/// [n] hits par jour sur [days] jours de la semaine ÉCOULÉE (lun 6 → dim 12
/// pour un now dans la semaine du lundi 13 juillet 2026).
List<HabitHit> _weekHits(int days, int perDay, {int hour = 18}) => [
      for (var d = 0; d < days; d++)
        for (var i = 0; i < perDay; i++)
          HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 6 + d, hour, i)),
    ];

void main() {
  // Mardi 14 juillet 2026 — semaine évaluante = lundi 13 ; semaine écoulée =
  // lundi 6 → dimanche 12.
  final now = DateTime(2026, 7, 14, 9, 0);

  group('paliers ×1,5', () {
    test('montée : 3 → 5 → 8 → 12 → 18 → 27 → 41 → 50 (cap)', () {
      final seq = <int>[3];
      while (seq.last < 50) {
        seq.add(nextStepUp(seq.last, 50));
      }
      expect(seq, [3, 5, 8, 12, 18, 27, 41, 50]);
    });

    test('montée : toujours au moins +1, jamais au-delà du cap', () {
      expect(nextStepUp(1, 50), 2);
      expect(nextStepUp(49, 50), 50);
      expect(nextStepUp(50, 50), 50);
    });

    test('descente : ÷1,5 arrondi, plancher 1', () {
      expect(nextStepDown(8), 5);
      expect(nextStepDown(3), 2);
      expect(nextStepDown(2), 1);
      expect(nextStepDown(1), 1);
    });
  });

  group('weeklyStepDecision', () {
    test('palier tenu ≥ 5 j/7 → palier suivant', () {
      final d = weeklyStepDecision(_routine(), _weekHits(6, 3), now);
      expect(d, isNotNull);
      expect(d!.verdict, 'up');
      expect(d.newTarget, 5);
      expect(d.daysMet, 6);
    });

    test('tenu ≤ 1 j/7 → on redescend ; jamais sous 1', () {
      final d = weeklyStepDecision(_routine(palier: 8), _weekHits(1, 8), now);
      expect(d!.verdict, 'down');
      expect(d.newTarget, 5);
      final d1 = weeklyStepDecision(_routine(palier: 1), _weekHits(0, 0), now);
      expect(d1!.verdict, 'hold'); // palier 1 : rien sous le plancher
      expect(d1.newTarget, 1);
    });

    test('semaine moyenne (2-4 j/7) → on garde le palier', () {
      final d = weeklyStepDecision(_routine(), _weekHits(3, 3), now);
      expect(d!.verdict, 'hold');
      expect(d.newTarget, 3);
    });

    test('les jours sous le palier ne comptent pas comme tenus', () {
      // 6 jours mais 2 pompes/j pour un palier de 3 : rien n'est tenu.
      final d = weeklyStepDecision(_routine(), _weekHits(6, 2), now);
      expect(d!.verdict, 'down');
    });

    test('déjà évaluée cette semaine → null (une éval/semaine)', () {
      final a = _routine(stepUpdatedWeek: '2026-07-13');
      expect(weeklyStepDecision(a, _weekHits(6, 3), now), isNull);
    });

    test('au cap, plus de montée ; sans cap, pas de progression', () {
      final d =
          weeklyStepDecision(_routine(palier: 50), _weekHits(6, 50), now);
      expect(d!.verdict, 'hold');
      expect(weeklyStepDecision(_routine(cap: null), _weekHits(6, 3), now),
          isNull);
    });

    test('routine créée en cours de semaine écoulée → null (données partielles)',
        () {
      final a = _routine(createdAt: DateTime(2026, 7, 9));
      expect(weeklyStepDecision(a, _weekHits(6, 3), now), isNull);
    });

    test('hit nocturne (< 5 h) = journée vécue de la veille', () {
      // 4 jours pleins (lun 6 → jeu 9) + les 3 hits du « vendredi 10 » faits
      // à 0h30 le samedi 11 : ils comptent pour le vendredi → 5 jours tenus.
      final hits = [
        ..._weekHits(4, 3),
        for (var i = 0; i < 3; i++)
          HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 11, 0, 30 + i)),
      ];
      final d = weeklyStepDecision(_routine(), hits, now);
      expect(d!.daysMet, 5);
      expect(d.verdict, 'up');
    });

    test('les hits hors semaine écoulée sont ignorés', () {
      // 6 jours tenus… mais la semaine COURANTE (13+) — la décision ne les
      // voit pas : semaine écoulée vide → down impossible (palier 3 → 2).
      final hits = [
        for (var d = 0; d < 2; d++)
          for (var i = 0; i < 3; i++)
            HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 13 + d, 18, i)),
      ];
      final d = weeklyStepDecision(_routine(), hits, now);
      expect(d!.daysMet, 0);
      expect(d.verdict, 'down');
      expect(d.newTarget, 2);
    });
  });

  test('palierLabel : fait complet avec unité', () {
    expect(palierLabel(_routine()), 'Palier : 3 pompes/j — cap 50');
    expect(palierLabel(_routine(cap: null)), '');
  });
}
