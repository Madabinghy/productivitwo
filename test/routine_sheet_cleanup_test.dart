import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/acquired.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';

/// Fiche routine allégée : plus de bloc « Série · n jours » ni d'interrupteur « Routine acquise ».
void main() {
  Future<void> open(WidgetTester tester, {bool acquired = false}) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final a = Activity(id: 'r', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 20, createdAt: DateTime(2026, 1, 1));
    final state = AppState(domains: [Domain(id: 'd', name: 'Sport')], activities: [a], sessions: [], habitProgress: []);
    final logic = AppLogic(state, () {});
    if (acquired) logic.acquired = {'r': const Acquired('2026-11-01')};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RoutineDetailSheet(logic: logic, st: state, habitId: 'r', day: DateTime(2026, 11, 20))),
    ));
    await tester.pump();
  }

  testWidgets('ni bloc de série ni interrupteur « Routine acquise »', (tester) async {
    await open(tester);
    expect(find.textContaining('Série ·'), findsNothing);
    expect(find.text('Routine acquise'), findsNothing);
    expect(find.byKey(const Key('routine-release')), findsNothing);
  });

  testWidgets('une routine déjà acquise peut être remise active', (tester) async {
    await open(tester, acquired: true);
    expect(find.byKey(const Key('routine-acquired')), findsOneWidget);
    expect(find.byKey(const Key('routine-release')), findsOneWidget);
  });
}
