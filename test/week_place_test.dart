import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/week_place.dart';
import 'package:productivitwo_v1/utils/week_spread.dart';

void main() {
  test('pieceSpecOf : travail en 1h30, fond chaque jour, corps en séances', () {
    final w = pieceSpecOf(PlanFamily.work, 480);
    expect(w.minutes, 90);
    expect(w.count, 5);
    expect(pieceSpecOf(PlanFamily.work, 60).minutes, 60);
    final f = pieceSpecOf(PlanFamily.fond, 7 * 40);
    expect(f.count, 7);
    expect(f.minutes, 45);
    final b = pieceSpecOf(PlanFamily.body, 135);
    expect(b.count, 3);
    expect(b.minutes, 45);
    expect(pieceSpecOf(PlanFamily.daily, 100).count, 0);
    expect(pieceSpecOf(PlanFamily.base, 600).count, 0);
  });

  test('les fantômes ne comptent pas', () {
    final days = [
      [const WeekPiece('a', 90), const WeekPiece('a', 90, ghost: true)],
      <WeekPiece>[],
    ];
    expect(placedCount(days, 'a'), 1);
    expect(dayLoad(days[0]), 90);
    expect(fitsDay(120, days[0], 30), isTrue);
    expect(fitsDay(120, days[0], 45), isFalse);
    expect(remainingPieces({'a': const PieceSpec(3, 90)}, days), {'a': 2});
    expect(remainingPieces({'a': const PieceSpec(1, 90)}, days), isEmpty);
  });

  test('ghostsFromSpread découpe et ne dépasse pas le reste', () {
    final g = ghostsFromSpread(
      [
        {'a': 120},
        {'a': 90, 'b': 45},
        {'a': 90},
      ],
      {'a': const PieceSpec(5, 90), 'b': const PieceSpec(2, 45)},
      {'a': 2, 'b': 1},
      reasons: {'1|b': 'corps'},
    );
    expect(g[0].map((p) => p.id), ['a']);
    expect(g[1].map((p) => p.id), ['a', 'b']);
    expect(g[2], isEmpty);
    expect(g.expand((d) => d).every((p) => p.ghost), isTrue);
    expect(g[1].last.reason, 'corps');
    expect(g[0].first.kept().ghost, isFalse);
  });
}
