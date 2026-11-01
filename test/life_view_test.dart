import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/life_view.dart';

void main() {
  testWidgets('Ma vie : modes, tuiles par nature', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final st = AppState(
      domains: [Domain(id: 'sl', name: 'Sommeil'), Domain(id: 'sp', name: 'Sport'), Domain(id: 'b', name: 'Business'), Domain(id: 'i', name: 'Intendance')],
      activities: [
        Activity(id: 'run', domainId: 'sp', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 7, createdAt: DateTime(2026)),
        Activity(id: 'w', domainId: 'b', name: 'Contenu', role: ActivityRole.generic, type: 'time', goalMin: 30, createdAt: DateTime(2026)),
      ],
      sessions: [Session(activityId: 'run', startAt: now.subtract(const Duration(minutes: 50)), endAt: now.subtract(const Duration(minutes: 10)))],
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
    expect(find.text('Ma vie'), findsOneWidget);
    expect(find.text('Guérilla'), findsOneWidget);
    expect(find.text('SOMMEIL'), findsOneWidget);
    expect(find.text('SPORT'), findsOneWidget);
    expect(find.text('1 séance'), findsOneWidget);
    expect(find.text('BUSINESS'), findsOneWidget);
    await tester.tap(find.text('BUSINESS'));
    expect(opened, 'Business');
    await tester.tap(find.text('SOMMEIL'));
    expect(opened, 'sleep');
  });
}
