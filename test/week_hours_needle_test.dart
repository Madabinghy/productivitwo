import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/widgets/week_hours_card.dart';

/// L'aiguille met une minute à changer de cible (demande user 2026-11-20).
void main() {
  WeekHours hours({HoursKind now = HoursKind.free, int active = 480, int leaving = 180}) => WeekHours(
        activeMin: active,
        basicMin: 0,
        sleepMin: 600,
        prevActiveMin: 0,
        leavingMin: leaving,
        dayActive: const [],
        days: const [],
        nowKind: now,
      );

  double needleOf(WidgetTester t) {
    final paint = t.widget<CustomPaint>(find.descendant(of: find.byType(WeekHoursGauge), matching: find.byType(CustomPaint)));
    return (paint.painter as dynamic).needleAt as double;
  }

  Future<void> show(WidgetTester t, WeekHours h) =>
      t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: WeekHoursGauge(h: h, size: 200)))));

  testWidgets('sans chrono puis chrono actif : l\'aiguille glisse en une minute de « si rien » à « à fond »', (t) async {
    final idle = hours();
    await show(t, idle);
    final low = gaugeLayout(idle).idleAt;
    // Le premier dessin est en place, sans glissement.
    expect(needleOf(t), closeTo(low, 1e-9));

    final working = hours(now: HoursKind.active);
    final high = gaugeLayout(working).fullAt;
    await show(t, working);
    await t.pump();
    expect(needleOf(t), closeTo(low, 1e-6));
    await t.pump(kNeedleTravel ~/ 2);
    // À mi-chemin à la moitié du trajet (la courbe est approchée : à 5 % près).
    expect(needleOf(t), closeTo((low + high) / 2, (high - low) * .05));
    await t.pump(kNeedleTravel ~/ 2);
    expect(needleOf(t), closeTo(high, 1e-9));

    // Le chrono s'arrête : elle redescend, dans le même temps.
    await show(t, idle);
    await t.pump();
    await t.pump(kNeedleTravel - const Duration(seconds: 1));
    expect(needleOf(t), greaterThan(low));
    await t.pump(const Duration(seconds: 1));
    expect(needleOf(t), closeTo(low, 1e-9));
  });

  testWidgets('une minute de plus pendant le trajet : l\'aiguille continue, elle ne repart pas de zéro', (t) async {
    await show(t, hours());
    await show(t, hours(now: HoursKind.active));
    await t.pump();
    await t.pump(kNeedleTravel * (2 / 3));
    // La minute tourne : le vert a gagné une minute, la cible a à peine bougé.
    final later = hours(now: HoursKind.active, active: 481);
    await show(t, later);
    await t.pump(kNeedleTravel * (1 / 3));
    expect(needleOf(t), closeTo(gaugeLayout(later).fullAt, 1e-9));
    // Arrivée : une dérive ne relance rien.
    await show(t, hours(now: HoursKind.active, active: 482));
    await t.pump();
    expect(needleOf(t), closeTo(gaugeLayout(hours(now: HoursKind.active, active: 482)).fullAt, 1e-9));
  });

  testWidgets('animations coupées : l\'aiguille est tout de suite en place', (t) async {
    Future<void> still(WeekHours h) => t.pumpWidget(MaterialApp(
        home: MediaQuery(data: const MediaQueryData(disableAnimations: true), child: Center(child: WeekHoursGauge(h: h, size: 200)))));
    await still(hours());
    final working = hours(now: HoursKind.active);
    await still(working);
    await t.pump();
    expect(needleOf(t), closeTo(gaugeLayout(working).fullAt, 1e-9));
  });
}
