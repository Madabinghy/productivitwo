import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_scope.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/sniper_scope.dart';

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

  group('tuile du mode : la miniature du viseur', () {
    final lecture = Activity(id: 'lec', domainId: 'd', name: 'Lecture', goalMin: 30);
    Stake timed(Activity a, int min, {bool loses = false}) => Stake(
          StakeGesture(key: 'activity:${a.id}', kind: StakeGestureKind.activity, title: a.name, costMin: min, activity: a),
          [StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse', weight: 10, losesTonight: loses)],
        );
    Future<void> pump(WidgetTester t, SniperPlan plan, {bool pending = false, VoidCallback? onTap}) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                  width: 104,
                  height: 104,
                  child: SniperModeTile(plan: plan, freeMin: plan.budgetMin, label: 'Sniper · détail', pending: pending, onTap: onTap ?? () {})),
            ),
          ),
        ));

    testWidgets('les minutes visées au centre de la lunette, un tap lance le Sniper', (t) async {
      var ran = 0;
      final plan = planSniper(stakes: [timed(lecture, 12), timed(Activity(id: 'k', domainId: 'd', name: 'Kingdom', goalMin: 20), 8, loses: true)], budgetMin: 52);
      await pump(t, plan, onTap: () => ran++);
      expect(find.byKey(const Key('mode-tile-scope')), findsOneWidget);
      expect(find.text('${plan.totalMin}'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      expect(find.byTooltip('Sniper · détail'), findsOneWidget);
      await t.tap(find.byKey(const Key('mode-tile')));
      expect(ran, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('rien à viser : la lunette vide, sans chiffre', (t) async {
      await pump(t, const SniperPlan(budgetMin: 45), pending: true);
      expect(find.byKey(const Key('mode-tile-scope')), findsOneWidget);
      expect(find.text('min'), findsNothing);
      expect(t.takeException(), isNull);
    });

    test('la couleur d’une cible = ce qui se perd ce soir d’abord, sinon son enjeu le plus lourd', () {
      final losing = sniperTargetOf(timed(lecture, 12, loses: true))!;
      expect(sniperTargetColor(losing), const Color(0xFFFFB3AB));
      expect(sniperTargetColor(sniperTargetOf(timed(lecture, 12))!), const Color(0xFF9FF0C1));
    });
  });
}
