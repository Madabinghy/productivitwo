import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart' show euros;
import 'package:productivitwo_v1/widgets/life_view.dart';

void main() {
  testWidgets('Organisation : tuiles par nature, sans modes', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day, 0, 1);
    final st = AppState(
      domains: [Domain(id: 'sl', name: 'Sommeil'), Domain(id: 'sp', name: 'Sport'), Domain(id: 'b', name: 'Business'), Domain(id: 'i', name: 'Intendance')],
      activities: [
        Activity(id: 'run', domainId: 'sp', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 7, createdAt: DateTime(2026)),
        Activity(id: 'w', domainId: 'b', name: 'Contenu', role: ActivityRole.generic, type: 'time', goalMin: 30, createdAt: DateTime(2026)),
      ],
      sessions: [Session(activityId: 'run', startAt: t0, endAt: t0.add(const Duration(minutes: 40)))],
      habitProgress: [],
    );
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    var opened = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeView(
          logic: logic,
          sync: FirestoreSync(),
          projects: const [],
          onOpenDomain: (d) async {
            opened = d.name;
            return null;
          },
          onOpenSleep: () => opened = 'sleep',
          onManageDomains: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Organisation'), findsOneWidget);
    expect(find.text('Guérilla'), findsNothing);
    expect(find.text('MES MODES'), findsNothing);
    expect(find.byKey(const ValueKey('life-objectives')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-hours-card')), findsOneWidget);
    expect(find.text('TES 7 DERNIERS JOURS'), findsOneWidget);
    expect(find.text('PAS DE SAISON EN COURS'), findsOneWidget);
    expect(find.text('SOMMEIL'), findsOneWidget);
    expect(find.text('SPORT'), findsOneWidget);
    expect(find.text('1 séance'), findsOneWidget);
    expect(find.text('BUSINESS'), findsOneWidget);
    await tester.tap(find.text('BUSINESS'));
    expect(opened, 'Business');
    await tester.tap(find.text('SOMMEIL'));
    expect(opened, 'sleep');
  });

  testWidgets('Ma vie : la tuile Finances montre le solde du compte', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'f', name: 'Finances')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await logic.recordBalance(184260);
    await logic.logExpense(amount: 1260, envelopeId: 'courses');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('FINANCES'), findsOneWidget);
    expect(find.text(euros(183000)), findsOneWidget);
    expect(find.textContaining('sur ton compte'), findsOneWidget);
  });

  for (final nature in ['money', 'work']) {
    testWidgets('changer la nature d\'un domaine ne fait pas disparaître sa tuile ($nature)', (tester) async {
      SharedPreferences.setMockInitialValues({'life_natures': '{"s":"$nature"}'});
      tester.view.physicalSize = const Size(720, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final t0 = DateTime(now.year, now.month, now.day, 0, 1);
      final st = AppState(
        domains: [Domain(id: 'f', name: 'Finances'), Domain(id: 's', name: 'Spiritualité')],
        activities: [Activity(id: 'g', domainId: 's', name: 'GDS', role: ActivityRole.generic, type: 'time', goalMin: 45, createdAt: DateTime(2026))],
        sessions: [Session(activityId: 'g', startAt: t0, endAt: t0.add(const Duration(minutes: 50)))],
        habitProgress: [],
      );
      final logic = AppLogic(st, () {})..dayStartMin = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {})),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('SPIRITUALITÉ'), findsOneWidget);
      expect(find.text('FINANCES'), findsOneWidget);
      if (nature == 'work') expect(find.textContaining('sur le rythme'), findsOneWidget);
    });
  }

  testWidgets('deux domaines de sport devinés : une seule tuile Sport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'm', name: 'Musculation'), Domain(id: 'sp', name: 'Sport')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {})),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('SPORT'), findsOneWidget);
  });
}
