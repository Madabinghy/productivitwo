import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart';

/// Feuille Journée parfaite : la vue Routines ne garde que les routines
/// quotidiennes pas encore atteintes.
void main() {
  testWidgets('RoutinesDayView(onlyMissing) : seulement ce qui manque', (tester) async {
    Activity r(String id) => Activity(
        id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [r('Lecture'), r('Pompes')], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.incHabit('Pompes', 1, logic.livedToday);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RoutinesDayView(logic: logic, onlyMissing: true, onChanged: () => changes++))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Lecture'), findsWidgets);
    expect(find.textContaining('Pompes'), findsNothing);
    expect(find.text('LA JOURNÉE PAR MOMENTS'), findsNothing);
    expect(changes, 0);
  });
}
