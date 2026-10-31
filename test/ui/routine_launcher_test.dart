import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routine_launcher_sheet.dart';

/// Lanceur de routines (FAB) : Focus = à faire par domaine, Tout = les faites aussi,
/// l'anneau « + » compte une occurrence, la ligne ouvre le compteur.
void main() {
  testWidgets('RoutineLauncher : Focus sans les faites, anneau = +1, ligne = compteur', (tester) async {
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
    expect(find.text('Focus · 2'), findsOneWidget);
    expect(find.text('Café'), findsNothing); // faite : seulement dans Tout
    expect(find.text('MUSCULATION'), findsOneWidget);
    // L'anneau des Pompes (rien de fait : « + ») compte une occurrence tout de suite.
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(logic.state.habitHits.where((h) => h.habitId == 'Pompes').length, 1);
    // Tap sur la ligne = le compteur.
    await tester.tap(find.text('Pompes'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 20'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('2 / 20'), findsOneWidget);
    Navigator.of(tester.element(find.text('2 / 20'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tout'));
    await tester.pumpAndSettle();
    expect(find.text('Café'), findsOneWidget); // la faite, à sa place dans Santé
    expect(tester.takeException(), isNull);
  });

  testWidgets('RoutineLauncher : une routine faite garde − / + sur sa ligne', (tester) async {
    final cafe = Activity(id: 'Café', domainId: 's', name: 'Café', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [Domain(id: 's', name: 'Santé')], activities: [cafe], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.incHabit('Café', 1, logic.livedToday);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RoutineLauncher(logic: logic, sync: FirestoreSync(), onNew: () {}, onChrono: (_) {}, onTimer: (_) {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir toutes les routines'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await tester.pumpAndSettle();
    expect(logic.state.habitHits.where((h) => h.habitId == 'Café').length, 2);
    await tester.tap(find.byIcon(Icons.remove_rounded).last);
    await tester.pumpAndSettle();
    expect(logic.state.habitHits.where((h) => h.habitId == 'Café').length, 1);
    expect(tester.takeException(), isNull);
  });
}
