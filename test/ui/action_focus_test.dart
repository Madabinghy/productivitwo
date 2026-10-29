import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/action_focus_screen.dart';

void main() {
  testWidgets('page focus : avant → étapes → action faite → trace, aucune exception', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.now();
    final dom = Domain(id: 'd', name: 'Travail');
    final act = Activity(id: 'contenu', domainId: 'd', name: 'Enseignement', role: ActivityRole.generic, type: 'time', goalMin: 60, createdAt: DateTime(2026, 1, 1));
    final action = TaskAction(id: 'a1', title: 'Corriger les copies', estimatedMin: 45, contexts: ['@ordinateur'])
      ..checklist.addAll([ChecklistItem(title: 'Swann', done: true), ChecklistItem(title: 'Dylan')]);
    final task = ProjectTask(id: 't1', title: 'Corriger les DM Ch2', startDate: now.subtract(const Duration(days: 3)), actions: [
      action,
      TaskAction(id: 'a2', title: 'Saisir les notes', estimatedMin: 15),
    ]);
    final project = Project(id: 'p1', title: '5e — Mathématiques', domainId: 'd', startDate: now.subtract(const Duration(days: 30)), createdBy: 'u', tasks: [task]);
    final st = AppState(domains: [dom], activities: [act], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {});

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showActionFocusScreen(ctx, logic: logic, action: action, project: project, task: task, chronoActivity: act, sync: FirestoreSync()),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('FOCUS'), findsOneWidget);
    expect(find.text('Corriger les copies'), findsOneWidget);
    expect(find.text('5e — Mathématiques › Corriger les DM Ch2'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Lancer le chrono'), findsOneWidget);

    // Lancer le chrono → pendant : étape en cours en avant, chrono ciblé.
    await tester.tap(find.text('Lancer le chrono'));
    await tester.pump();
    expect(st.sessions.where((s) => s.endAt == null && s.actionId == 'a1').length, 1);
    expect(find.text('FOCUS · CHRONO'), findsOneWidget);
    expect(find.text('Dylan'), findsOneWidget);
    expect(find.text('Dernière étape : elle termine l\'action.'), findsOneWidget);

    // Étape faite = dernière → action faite → après : trace et chrono fermé.
    await tester.tap(find.text('Étape faite'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(action.done, isTrue);
    expect(st.sessions.where((s) => s.endAt == null).isEmpty, isTrue);
    expect(find.text('FOCUS · TERMINÉ'), findsOneWidget);
    expect(find.text('LA TÂCHE AVANCE'), findsOneWidget);
    expect(find.textContaining('reste Saisir les notes'), findsOneWidget);
    expect(find.textContaining('Enchaîner · Saisir les notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
