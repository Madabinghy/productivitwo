import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routine_launcher_sheet.dart';

/// Lanceur de routines (FAB) : à faire par domaine, « Faites · n » replié,
/// l'anneau ouvre le compteur et + compte une occurrence.
void main() {
  testWidgets('RoutineLauncher : faites repliées, anneau = compteur', (tester) async {
    Activity r(String id, String dom, {int target = 1}) => Activity(
        id: id, domainId: dom, name: id, role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: target, createdAt: DateTime(2026, 1, 1));
    final st = AppState(
        domains: [Domain(id: 's', name: 'Santé'), Domain(id: 'm', name: 'Musculation')],
        activities: [r('Lecture', 's'), r('Café', 's'), r('Pompes', 'm', target: 20)],
        sessions: [],
        habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.incHabit('Café', 1, logic.livedToday);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutineLauncher(logic: logic, sync: FirestoreSync(), onNew: () {}, onChrono: (_) {}, onTimer: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Faites · 1'), findsOneWidget);
    expect(find.text('MUSCULATION'), findsOneWidget);
    // L'anneau des Pompes (rien de fait : « + ») ouvre le compteur.
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('0 / 20'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('1 / 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
