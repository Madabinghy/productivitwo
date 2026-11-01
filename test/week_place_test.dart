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

  test('perDay répartit le surplus sur les premiers jours', () {
    expect(perDay(10, 4), [3, 3, 2, 2]);
    expect(perDay(3, 3), [1, 1, 1]);
    expect(perDay(2, 5), [1, 1, 0, 0, 0]);
    expect(perDay(4, 0), isEmpty);
  });

  test('firstFreeStart saute les blocs et arrondit au quart d\'heure', () {
    final busy = [(480, 540), (545, 600), (720, 780)];
    expect(firstFreeStart(busy, 480, 1320, 60), 600);
    expect(firstFreeStart(busy, 480, 1320, 150), 780);
    expect(firstFreeStart(busy, 610, 1320, 30), 615);
    expect(firstFreeStart(busy, 1300, 1320, 30), isNull);
    expect(overlapsAny(busy, 590, 30), isTrue);
    expect(overlapsAny(busy, 600, 120), isFalse);
    const p = WeekPiece('a', 45, start: 600, proposed: true);
    expect(p.end, 645);
    expect(p.at(660).proposed, isFalse);
  });
}
