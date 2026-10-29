import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/widgets/action_focus_screen.dart';

class _Replaces extends NavigatorObserver {
  int count = 0;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => count++;
}

void main() {
  test('BlockFocus.remainingMin suit la journée vécue (bloc de la nuit compris)', () {
    final act = Activity(id: 'a', domainId: 'd', name: 'A', role: ActivityRole.generic, type: 'time', createdAt: DateTime(2026, 1, 1));
    final night = ScheduleBlock(id: 'n', startTime: '01:30', durationMin: 60, title: 'A', activityId: 'a')..dayOffset = 1;
    final bf = BlockFocus(block: night, activity: act, queue: const [], ymd: '2026-10-30');
    expect(bf.remainingMin(DateTime(2026, 10, 31, 1, 57), dayStartMin: 300), 33);
    final late = ScheduleBlock(id: 'l', startTime: '23:30', durationMin: 60, title: 'A', activityId: 'a');
    final bf2 = BlockFocus(block: late, activity: act, queue: const [], ymd: '2026-10-30');
    expect(bf2.remainingMin(DateTime(2026, 10, 31, 0, 10), dayStartMin: 300), 20);
    expect(bf2.remainingMin(DateTime(2026, 10, 31, 1, 57), dayStartMin: 300), 0);
  });

  testWidgets('focus d\'un bloc d\'activité : file → commencer → suivante → enchaîner', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.now();
    final dom = Domain(id: 'd', name: 'Travail');
    final act = Activity(id: 'ens', domainId: 'd', name: 'Enseignement', role: ActivityRole.generic, type: 'time', goalMin: 60, createdAt: DateTime(2026, 1, 1),
        ownActions: [TaskAction(id: 'own', title: 'Ranger le bureau', estimatedMin: 10)]);
    final copies = TaskAction(id: 'a1', title: 'Corriger les copies', estimatedMin: 45);
    final p1 = Project(id: 'p1', title: '5e — Maths', domainId: 'd', startDate: now.subtract(const Duration(days: 30)), createdBy: 'u', linkedActivityId: 'ens', tasks: [
      ProjectTask(id: 't1', title: 'Corriger les DM', startDate: now.subtract(const Duration(days: 3)), endDate: now.subtract(const Duration(days: 2)), actions: [copies]),
    ]);
    final fiche = TaskAction(id: 'a2', title: 'Remplir la fiche', estimatedMin: 15, linkedActivityId: 'ens');
    final p2 = Project(id: 'p2', title: 'Techno', domainId: 'd', startDate: now.subtract(const Duration(days: 30)), createdBy: 'u', tasks: [
      ProjectTask(id: 't2', title: 'Clôturer', startDate: now.subtract(const Duration(days: 3)), actions: [fiche]),
    ]);
    final block = ScheduleBlock(id: 'b', startTime: '00:00', durationMin: 24 * 60, title: 'Enseignement', category: 'project', activityId: 'ens');
    final queue = blockQueue(activity: act, projects: [p1, p2], today: now);
    expect(queue.map((e) => e.id).toList(), ['a1', 'a2', 'own']);

    final st = AppState(domains: [dom], activities: [act], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final replaces = _Replaces();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [replaces],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showBlockFocusScreen(ctx, logic: logic, block: block, activity: act, queue: queue, ymd: '2026-10-29', sync: FirestoreSync()),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bloc Enseignement'), findsOneWidget);
    expect(find.text('LA FILE DU BLOC · 3'), findsOneWidget);
    expect(find.textContaining('bloc · reste'), findsOneWidget);
    expect(find.text('Commencer · Corriger les copies'), findsOneWidget);

    // Choisir la 2e de la file → la page passe dessus.
    await tester.tap(find.text('Remplir la fiche').first);
    await tester.pumpAndSettle();
    expect(find.text('Commencer · Remplir la fiche'), findsOneWidget);
    expect(find.text('LA FILE DU BLOC · 3'), findsOneWidget); // toujours sur la file, même page
    expect(replaces.count, 0);

    // Commencer → chrono ciblé sur l'activité du bloc ; « Suivante » disponible.
    await tester.tap(find.text('Commencer · Remplir la fiche'));
    await tester.pump();
    expect(st.sessions.where((s) => s.endAt == null && s.actionId == 'a2' && s.activityId == 'ens').length, 1);
    expect(find.text('Suivante ›'), findsOneWidget);
    await tester.tap(find.text('Suivante ›'));
    await tester.pumpAndSettle();
    expect(st.sessions.where((s) => s.endAt == null).isEmpty, isTrue);
    expect(find.text('Ranger le bureau'), findsWidgets);
    expect(find.text('Lancer le chrono'), findsOneWidget);
    expect(replaces.count, 0); // « Suivante » change d'action sur place

    // Action faite → après : « Enchaîner » sur la suivante ouverte de la file.
    await tester.tap(find.text('Action faite').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ranger le bureau ✓'), findsOneWidget);
    expect(find.text('Enchaîner · Corriger les copies'), findsOneWidget);

    // Terminer le bloc → récap : tenu, fait, reste, « Caser un bloc demain ».
    await tester.tap(find.text('Terminer le bloc'));
    await tester.pumpAndSettle();
    expect(find.text('BLOC TERMINÉ'), findsOneWidget);
    expect(find.text('FAIT SUR CE BLOC'), findsOneWidget);
    expect(find.text('RESTE DANS LA FILE · 2'), findsOneWidget);
    expect(find.text('Caser un bloc Enseignement demain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
