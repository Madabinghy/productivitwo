import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart';

void main() {
  testWidgets('fiche d’un badge : le +1 de la section AUJOURD’HUI met la fiche à jour', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final eau = Activity(id: 'eau', name: 'Boire de l’eau', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 7, createdAt: DateTime(2026, 9, 1));
    var count = 0;
    TodayFacts facts() => TodayFacts(ymd: '2026-11-03', now: DateTime(2026, 11, 3, 9), routines: [RoutineToday(eau, count, 7)]);
    final b = BadgeState(def: const BadgeDef(id: 'metronome', family: BadgeFamily.days, name: 'Métronome', symbol: 'metronome', tiers: [5, 20, 50, 100]), level: 0, value: 3);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showBadgeSheet(context, b,
                facts: facts(), factsOf: facts, actions: BadgeTodayActions(routinePlus: (_) => count++)),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 / 7'), findsWidgets);
    await tester.tap(find.text('+1').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 7'), findsWidgets);
  });
}
