import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/widgets/week_hours_card.dart';

/// L'aiguille met [kNeedleTravel] (une minute) à monter ou redescendre dans le vert, et fait un tour entier
/// ([kNeedleSpin]) quand on change de mode (demande user 2026-11-21).
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

  testWidgets('sans chrono puis chrono actif : l\'aiguille glisse de « si rien » à « à fond »', (t) async {
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

  testWidgets('une seconde jauge ouverte en cours de route reprend la MÊME aiguille (tuile puis feuille)', (t) async {
    List<double> needles() => [
          for (final p in t.widgetList<CustomPaint>(find.descendant(of: find.byType(WeekHoursGauge), matching: find.byType(CustomPaint))))
            (p.painter as dynamic).needleAt as double,
        ];
    Future<void> both(WeekHours h, {required bool sheet}) => t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Column(children: [
          WeekHoursGauge(key: const ValueKey('tile'), h: h, size: 90),
          if (sheet) WeekHoursGauge(key: const ValueKey('sheet'), h: h, size: 300),
        ]))));
    final idle = hours();
    final working = hours(now: HoursKind.active);
    final low = gaugeLayout(idle).idleAt, high = gaugeLayout(working).fullAt;
    await both(idle, sheet: false);
    await both(working, sheet: false);
    await t.pump(kNeedleTravel ~/ 2);
    final mid = needleOf(t);
    expect(mid, closeTo((low + high) / 2, (high - low) * .05));

    // La feuille s'ouvre à mi-trajet : son aiguille n'est pas déjà arrivée, elle est là où en est celle de la tuile.
    await both(working, sheet: true);
    expect(needles(), [closeTo(mid, 1e-9), closeTo(mid, 1e-9)]);
    await t.pump(kNeedleTravel ~/ 4);
    final later = needles();
    expect(later[0], greaterThan(mid));
    expect(later[1], closeTo(later[0], 1e-9));
    await t.pump(kNeedleTravel ~/ 4);
    expect(needles(), [closeTo(high, 1e-9), closeTo(high, 1e-9)]);

    // La feuille se ferme pendant un nouveau trajet : la tuile continue sans à-coup.
    await both(idle, sheet: true);
    await t.pump(kNeedleTravel ~/ 2);
    final back = needles().first;
    await both(idle, sheet: false);
    expect(needleOf(t), closeTo(back, 1e-9));
    await t.pump(kNeedleTravel ~/ 2);
    expect(needleOf(t), closeTo(low, 1e-9));
  });

  testWidgets('plus aucune jauge à l\'écran : la suivante repart en place, sans glissement', (t) async {
    await show(t, hours());
    await show(t, hours(now: HoursKind.active));
    await t.pump(kNeedleTravel ~/ 3);
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    final idle = hours();
    await show(t, idle);
    expect(needleOf(t), closeTo(gaugeLayout(idle).idleAt, 1e-9));
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('onglet caché pendant le trajet : rien ne tourne, et au retour l\'aiguille est là où elle en serait', (t) async {
    Future<void> tab(WeekHours h, {required bool shown}) => t.pumpWidget(MaterialApp(
        home: Scaffold(body: TickerMode(enabled: shown, child: Center(child: WeekHoursGauge(h: h, size: 200))))));
    final idle = hours();
    final working = hours(now: HoursKind.active);
    final low = gaugeLayout(idle).idleAt, high = gaugeLayout(working).fullAt;
    await tab(idle, shown: true);
    await tab(working, shown: false);
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
    await t.pump(kNeedleTravel ~/ 2);
    await tab(working, shown: true);
    expect(needleOf(t), closeTo((low + high) / 2, (high - low) * .05));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pump(kNeedleTravel ~/ 2);
    expect(needleOf(t), closeTo(high, 1e-9));
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  test('needleSpins : un tour dès qu\'on entre dans la détente, le sommeil ou un besoin, ou qu\'on en sort', () {
    expect(needleSpins(HoursKind.free, HoursKind.active), isFalse);
    expect(needleSpins(HoursKind.active, HoursKind.free), isFalse);
    expect(needleSpins(HoursKind.active, HoursKind.active), isFalse);
    expect(needleSpins(HoursKind.free, HoursKind.leisure), isTrue);
    expect(needleSpins(HoursKind.active, HoursKind.sleep), isTrue);
    expect(needleSpins(HoursKind.basic, HoursKind.free), isTrue);
    expect(needleSpins(HoursKind.leisure, HoursKind.sleep), isTrue);
    expect(needleSpins(HoursKind.sleep, HoursKind.sleep), isFalse);
  });

  testWidgets('un chrono de détente démarre : l\'aiguille fait un tour entier puis se pose dessus', (t) async {
    final idle = hours();
    await show(t, idle);
    final low = gaugeLayout(idle).idleAt;
    final chill = hours(now: HoursKind.leisure);
    final on = gaugeLayout(chill).marks[HoursKind.leisure]!;
    await show(t, chill);
    await t.pump();
    expect(HoursNeedle.ping, isNotNull);
    // Elle part d'où elle était et tourne dans le sens des aiguilles d'une montre, au-delà du cadran.
    var last = needleOf(t), far = last;
    for (var i = 0; i < 18; i++) {
      await t.pump(kNeedleSpin ~/ 20);
      final a = needleOf(t);
      far = math.max(far, a);
      last = a;
    }
    // Un tour entier au moins, et un petit dépassement avant de revenir.
    expect(far, greaterThan(on));
    await t.pump(kNeedleSpin ~/ 10);
    expect(needleOf(t), closeTo(on, 1e-9));
    expect(HoursNeedle.ping, isNull);
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);

    // Le chrono de détente s'arrête : un tour encore (bien plus court que la minute du vert), puis « si rien ».
    await show(t, idle);
    await t.pump();
    await t.pump(kNeedleSpin);
    expect(needleOf(t), closeTo(low, 1e-9));
  });

  testWidgets('le tour fait au moins 360° quelle que soit la place d\'arrivée', (t) async {
    final chill = hours(now: HoursKind.leisure);
    await show(t, chill);
    final from = gaugeLayout(chill).marks[HoursKind.leisure]!;
    final sleep = hours(now: HoursKind.sleep);
    final to = gaugeLayout(sleep).marks[HoursKind.sleep]!;
    await show(t, sleep);
    await t.pump();
    final start = needleOf(t);
    // Le départ est la place d'avant, à un nombre entier de tours près ; l'arrivée est au moins un tour plus loin.
    final turns = (from - start) / (2 * math.pi);
    expect(turns, closeTo(turns.roundToDouble(), 1e-6));
    expect(to - start, greaterThanOrEqualTo(2 * math.pi - 1e-9));
    await t.pump(kNeedleSpin);
    expect(needleOf(t), closeTo(to, 1e-9));
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
