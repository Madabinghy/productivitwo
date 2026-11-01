import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/sleep_sheet.dart';

/// Feuille Sommeil : cette nuit, 14 nuits, coucher, ce soir, une nuit en détail.
void main() {
  testWidgets('SleepSheet : nuits chronométrées, ce soir, une nuit en détail', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sleep = Activity(id: 's', domainId: 'd', name: 'Sommeil', type: 'time', goalMin: 450);
    final sessions = <Session>[
      for (var k = 1; k <= 12; k++)
        Session(
          activityId: 's',
          startAt: today.subtract(Duration(days: k)).add(Duration(hours: 23, minutes: (k * 13) % 70)),
          endAt: today.subtract(Duration(days: k - 1)).add(const Duration(hours: 6, minutes: 30)),
        ),
    ];
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [sleep], sessions: sessions, habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 5 * 60;
    Session? edited;
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SleepSheet(
          logic: logic,
          onOpenActivity: () {},
          onEditSession: (_, s) async => edited = s,
          onDeleteSession: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Sommeil'), findsOneWidget);
    expect(find.text('14 NUITS'), findsOneWidget);
    expect(find.text('TON COUCHER'), findsOneWidget);
    expect(find.text('Je vais me coucher'), findsOneWidget);
    expect(find.textContaining('dette sur 7 nuits'), findsOneWidget);
    await tester.tap(find.text('Corriger une nuit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NUIT DU'), findsOneWidget);
    await tester.tap(find.text('Modifier les heures'));
    await tester.pump();
    expect(edited, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
