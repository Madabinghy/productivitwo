import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/sniper_scope.dart';

void main() {
  test('lunette du viseur : le tour = le temps libre, un arc par cible, le reste est de l’air', () {
    final s = aimScope(costs: [12, 15, 8], freeMin: 60, pauseMin: 2);
    expect(s.ticks, 60);
    expect(s.arcs.length, 3);
    expect(s.arcs[0].start, 0);
    expect(s.arcs[0].sweep, closeTo(72, 1e-9)); // 12 min sur 60 = 72°
    expect(s.arcs[1].start, closeTo(84, 1e-9)); // après la pause de 2 min (12°)
    expect(s.arcs[1].sweep, closeTo(90, 1e-9));
    expect(s.arcs[2].end, closeTo(234, 1e-9)); // 39 min visées, pauses comprises
    expect(s.airStart, closeTo(234, 1e-9));
    expect(s.airSweep, closeTo(126, 1e-9)); // 21 min d'air
  });

  test('lunette du viseur : une cible d’une minute reste lisible, rien ne dépasse le tour', () {
    final small = aimScope(costs: [1, 12], freeMin: 120, pauseMin: 2);
    expect(small.arcs[0].sweep, kScopeMinArc);
    expect(small.ticks, 24); // au-delà de 90 min, un trait par 5 minutes
    final full = aimScope(costs: [1, 1, 1, 1, 30], freeMin: 34, pauseMin: 0);
    expect(full.arcs.last.end, lessThanOrEqualTo(360.0001));
    expect(full.airSweep, 0);
    final over = aimScope(costs: [40, 30], freeMin: 20, pauseMin: 2);
    expect(over.arcs.last.end, closeTo(360, 1e-6)); // le visé dépasse le libre : le tour = le visé
    final empty = aimScope(costs: [], freeMin: 45);
    expect(empty.arcs, isEmpty);
    expect(empty.airSweep, 360);
  });

  test('carton : pile au centre, plus l’écart est grand plus l’impact s’éloigne', () {
    expect(impactRadius(0), lessThan(kCardBull));
    expect(impactRadius(1), closeTo(.39, 1e-9));
    expect(impactRadius(-2), closeTo(.59, 1e-9));
    expect(impactRadius(4), closeTo(.90, 1e-9));
    expect(impactRadius(12), 1.0);
    final radii = [for (var g = 0; g <= 6; g++) impactRadius(g)];
    for (var i = 1; i < radii.length; i++) {
      expect(radii[i], greaterThanOrEqualTo(radii[i - 1]));
    }
  });

  test('carton : un impact par cible touchée, numéroté comme les tirs, mini-tir à part', () {
    final card = shotCard([
      (hit: true, gapMin: 0, mini: false),
      (hit: false, gapMin: 0, mini: false),
      (hit: true, gapMin: 2, mini: false),
      (hit: true, gapMin: 0, mini: true),
    ]);
    expect(card.map((i) => i.number), [1, 3, 4]);
    expect(card[1].radius, closeTo(.59, 1e-9));
    expect(card[2].mini, isTrue);
    expect(card.map((i) => i.angle).toSet().length, 3);
    // Les deux tirs pile se font face dans le centre ; un seul tir pile est en plein milieu.
    expect(card[0].radius, lessThan(kCardBull));
    expect((card[0].angle - card[2].angle).abs(), closeTo(180, 1e-9));
    expect(shotCard([(hit: true, gapMin: 0, mini: false)]).single.radius, 0);
    expect(shotCard([]), isEmpty);
  });
}
