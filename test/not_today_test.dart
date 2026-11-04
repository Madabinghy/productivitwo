import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/not_today.dart';

void main() {
  test('message du « Pas aujourd\'hui » : journée parfaite possible, série coupée', () {
    expect(notTodayLine('Pompes', series: 12), 'Pas aujourd\'hui : Pompes · ta journée parfaite reste possible (sans braise), la série de 12 j s\'arrête');
    expect(notTodayLine('Pompes'), contains('pas de série en jeu'));
    expect(notTodayLine('Ménage', daily: false), 'Pas aujourd\'hui : Ménage');
  });

  test('une journée parfaite avec une routine excusée ne forge pas de braise', () {
    const clean = DayScore('2026-11-03', 2, 2, 1, 1);
    const excused = DayScore('2026-11-04', 1, 1, 1, 1, excused: 1);
    expect(clean.perfect, isTrue);
    expect(clean.forgesEmber, isTrue);
    expect(excused.perfect, isTrue);
    expect(excused.forgesEmber, isFalse);
  });
}
