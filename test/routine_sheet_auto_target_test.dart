import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';

/// Fiche routine : l'interrupteur « Cible automatique » (routine quotidienne sans cap).
void main() {
  Activity routine({int? cap, HabitFreq freq = HabitFreq.daily}) => Activity(
      id: 'r', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: freq, habitTarget: 20, finalTarget: cap, createdAt: DateTime(2026, 1, 1));

  Future<AppLogic> open(WidgetTester tester, Activity a) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(domains: [Domain(id: 'd', name: 'Sport')], activities: [a], sessions: [], habitProgress: []);
    final logic = AppLogic(state, () {});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RoutineDetailSheet(logic: logic, st: state, habitId: 'r', day: DateTime(2026, 11, 20))),
    ));
    await tester.pump();
    return logic;
  }

  testWidgets('allumer la cible automatique, puis lire la règle', (tester) async {
    final a = routine();
    await open(tester, a);
    final sw = find.byKey(const ValueKey('routine-auto-target'));
    expect(sw, findsOneWidget);
    expect(a.autoTarget, isFalse);
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    expect(a.autoTarget, isTrue);
    expect(find.textContaining('120 % sur 7 jours'), findsOneWidget);
  });

  testWidgets('le dernier changement est dit sous l\'interrupteur', (tester) async {
    final a = routine()
      ..autoTarget = true
      ..keepTargetUntil('2026-11-19');
    a.habitTarget = 22;
    await open(tester, a);
    expect(find.textContaining('Dernier changement : 20 → 22 depuis le 20 nov.'), findsOneWidget);
  });

  testWidgets('pas d\'interrupteur avec un cap ni pour une routine hebdomadaire', (tester) async {
    await open(tester, routine(cap: 50));
    expect(find.byKey(const ValueKey('routine-auto-target')), findsNothing);
    await open(tester, routine(freq: HabitFreq.weekly));
    expect(find.byKey(const ValueKey('routine-auto-target')), findsNothing);
  });
}
