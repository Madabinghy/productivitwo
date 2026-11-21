import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/offensive_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoupAlarm.enabled = false;
  });
  tearDown(() => CoupAlarm.enabled = true);

  testWidgets('Deep work sur une activité : « Tout Kingdom » en tête des fronts, choisi d’office', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final kin = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30);
    final today = DateTime.now();
    final site = Project(id: 'site', title: 'Site vitrine', startDate: today.subtract(const Duration(days: 10)), createdBy: 'u', linkedActivityId: 'kin', tasks: [
      ProjectTask(id: 't', title: 'Écrire', startDate: today.subtract(const Duration(days: 5)), actions: [
        TaskAction(id: 'a1', title: 'Rédiger l’accueil', estimatedMin: 20),
        TaskAction(id: 'a2', title: 'Page contact', estimatedMin: 15),
      ]),
    ]);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [kin], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})
      ..dayStartMin = 0
      ..currentProjects = [site];
    await tester.pumpWidget(MaterialApp(home: OffensiveScreen(logic: logic, activityId: 'kin', deepWork: true)));
    await tester.pump();
    expect(find.byKey(const ValueKey('offensive-front-activity')), findsOneWidget);
    expect(find.text('Tout Kingdom'), findsOneWidget);
    expect(find.text('Lancer l’offensive · 2 actions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
