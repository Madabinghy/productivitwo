import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show focusToday;
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

  testWidgets('Rond ↗ : Pour aujourd’hui par défaut, le projet du moment, du plus pressant, et Projets', (tester) async {
    tester.view.physicalSize = const Size(800, 3400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final kin = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30, ownActions: [
      TaskAction(id: 'o1', title: 'Ranger le bureau', focusDate: focusToday()),
    ]);
    final today = DateTime.now();
    final site = Project(id: 'site', title: 'Site vitrine', startDate: today.subtract(const Duration(days: 10)), createdBy: 'u', tasks: [
      ProjectTask(id: 't', title: 'Écrire', startDate: today.subtract(const Duration(days: 5)), actions: [
        TaskAction(id: 'a1', title: 'Rédiger l’accueil', estimatedMin: 20),
      ]),
    ]);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [kin], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})
      ..dayStartMin = 0
      ..currentProjects = [site];
    var toProjects = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showOffensiveScreen(ctx, logic, onChooseProject: () => toProjects++),
            child: const Text('ouvrir'),
          ),
        ),
      );
    })));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    // « Pour aujourd'hui » contient l'action visée sans projet : choisie d'office.
    expect(find.byKey(const ValueKey('offensive-front-today')), findsOneWidget);
    expect(find.text('Pour aujourd’hui · 1 action'), findsOneWidget);
    expect(find.text('Lancer l’offensive · 1 action'), findsOneWidget);
    expect(find.byKey(const ValueKey('offensive-front-moment')), findsOneWidget);
    expect(find.byKey(const ValueKey('offensive-front-pressing')), findsOneWidget);
    expect(find.text('Tout mélanger'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('offensive-front-pressing')));
    await tester.pump();
    expect(find.text('Lancer l’offensive · 1 action'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('offensive-choose-project')));
    await tester.pumpAndSettle();
    expect(toProjects, 1);
    expect(find.text('ouvrir'), findsOneWidget);
  });
}
