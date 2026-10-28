import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/activity_fiche_sheet.dart';
import 'package:productivitwo_v1/widgets/domain_page.dart';

/// Page domaine et fiche activité : s'ouvrent sans exception de layout sur un
/// écran étroit, avec une activité qui a des sessions et des actions propres.
void main() {
  final dom = Domain(id: 'd', name: 'Organisation');
  final act = Activity(
      id: 'prep', domainId: 'd', name: 'Préparation', role: ActivityRole.generic, type: 'time', goalMin: 15, createdAt: DateTime(2026, 1, 1), timerMin: 25)
    ..ownActions.add(TaskAction(title: 'Relire les notes du chapitre 3', estimatedMin: 20));
  final habit = Activity(
      id: 'cafe', domainId: 'd', name: 'Café', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
  final now = DateTime.now();
  final st = AppState(
    domains: [dom],
    activities: [act, habit],
    sessions: [
      Session(activityId: 'prep', startAt: now.subtract(const Duration(hours: 3)), endAt: now.subtract(const Duration(hours: 2, minutes: 22))),
      Session(activityId: 'prep', startAt: now.subtract(const Duration(days: 1, hours: 2)), endAt: now.subtract(const Duration(days: 1, hours: 1))),
    ],
    habitProgress: [],
  );
  final logic = AppLogic(st, () {});

  Widget host(Future<void> Function(BuildContext ctx) open) => MaterialApp(
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: SizedBox(width: 360, child: TextButton(onPressed: () => open(ctx), child: const Text('open')))))),
      );

  testWidgets('fiche activité : ouverture, sections repliées, aucune exception', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host((ctx) => showActivityFiche(ctx, logic: logic, sync: FirestoreSync(), activity: act, onLaunchTimed: (_, __) {})));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Préparation'), findsOneWidget);
    expect(find.text('Chrono'), findsOneWidget);
    // La tendance est en tête (sous CETTE SEMAINE), toujours visible.
    expect(find.textContaining('TENDANCE · 12 SEMAINES'), findsOneWidget);
    // Fait défiler jusqu'en bas (DERNIERS CHRONOS apparaît) et déplie Déroulés et Réglages.
    var sawSessions = false;
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('DERNIERS CHRONOS').evaluate().isNotEmpty) sawSessions = true;
      final f = find.text('afficher ▾');
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'après dépliage $i');
      }
    }
    expect(sawSessions, isTrue);
    expect(find.text('replier ▴'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page domaine : temps et routines, aucune exception', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(host((ctx) => showDomainPage(ctx,
        logic: logic, sync: FirestoreSync(), domain: dom, onCreate: ({String? domainId, required bool isHabit}) async {}, onOpenActivity: (_) async => false)));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('ACTIVITÉ DU MOMENT'), findsOneWidget);
    expect(find.textContaining('À RATTRAPER'), findsOneWidget);
    await tester.tap(find.text('Routines'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Café'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
