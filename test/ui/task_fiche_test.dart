import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/task_fiche_sheet.dart';

/// Fiche de tâche « une carte, une fiche » : s'ouvre sans exception de layout
/// sur un écran étroit (titre de séance long, émoji de rôle, actions avec
/// étapes, contexte, échéance propre, action faite), et la fiche d'action
/// s'ouvre au tap sur une ligne.
void main() {
  final dom = Domain(id: 'd', name: 'Business');
  final act = Activity(id: 'contenu', domainId: 'd', name: 'Contenu', role: ActivityRole.generic, type: 'time', goalMin: 60, createdAt: DateTime(2026, 1, 1));
  final now = DateTime.now();
  final task = ProjectTask(
    id: 't1',
    title: '✅ Clôturer — Séance — 19 oct : révision Ch2 + lancement Ch4 relatifs',
    startDate: now.subtract(const Duration(days: 9)),
    endDate: now.subtract(const Duration(days: 2)),
    interventionRole: 'closure',
    description: 'Bilan de la séance et fiche de séquence.',
    actions: [
      TaskAction(id: 'a1', title: 'Remplir la fiche de séquence 5e (réalisé + bilan)', contexts: ['@ordinateur'], estimatedMin: 25, dueDate: now.subtract(const Duration(days: 1)))
        ..checklist.addAll([ChecklistItem(title: 'Réalisé'), ChecklistItem(title: 'Bilan', done: true)]),
      TaskAction(id: 'a2', title: 'Saisir les notes', estimatedMin: 15),
      TaskAction(id: 'a3', title: 'Relire le cours', done: true, doneAt: now.subtract(const Duration(days: 3))),
    ],
  );
  final project = Project(id: 'p1', title: '5e — Mathématiques', domainId: 'd', startDate: now.subtract(const Duration(days: 30)), createdBy: 'u', linkedActivityId: 'contenu', tasks: [task]);
  final st = AppState(domains: [dom], activities: [act], sessions: [], habitProgress: []);
  final logic = AppLogic(st, () {});

  Widget host(Future<void> Function(BuildContext ctx) open) => MaterialApp(
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: SizedBox(width: 360, child: TextButton(onPressed: () => open(ctx), child: const Text('open')))))),
      );

  Future<void> scrollUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 8 && f.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('fiche de tâche : en-tête, actions, détail, fiche d\'action, aucune exception', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var started = 0;
    await tester.pumpWidget(host((ctx) => showTaskFiche(ctx,
        project: project, task: task, activities: [act], sync: FirestoreSync(), logic: logic, onStartTimer: (_, __, ___) => started++)));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Titre sans l'émoji de rôle, chip en retard, actions ouvertes, faites repliées.
    expect(find.text('Clôturer — Séance — 19 oct : révision Ch2 + lancement Ch4 relatifs'), findsOneWidget);
    expect(find.textContaining('en retard'), findsWidgets);
    expect(find.text('Remplir la fiche de séquence 5e (réalisé + bilan)'), findsOneWidget);
    expect(find.text('Relire le cours'), findsNothing);
    expect(find.textContaining('FAITES · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Le bouton plein est en bas : on fait défiler.
    await scrollUntil(tester, find.textContaining('Lancer · Remplir'));
    expect(find.textContaining('Lancer · Remplir'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scrollUntil(tester, find.text('Saisir les notes'));
    for (var i = 0; i < 8 && find.text('Saisir les notes').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, 400));
      await tester.pump(const Duration(milliseconds: 250));
    }
    // Déplie les faites et le détail.
    await tester.tap(find.textContaining('FAITES · 1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Relire le cours'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Tap sur une action = sa fiche (étapes, échéance, activité liée).
    await tester.tap(find.text('Saisir les notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('ÉTAPES'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scrollUntil(tester, find.text('Lancer le chrono'));
    expect(find.text('ACTIVITÉ LIÉE'), findsOneWidget);
    expect(find.text('Contenu'), findsWidgets); // héritée du projet
    expect(find.text('Lancer le chrono'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lancer le chrono'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(started, 1);
    expect(tester.takeException(), isNull);
  });
}
