import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/task_picker_sheet.dart';

/// Sélecteur de tâche : phases, titre sans émoji, tâches faites absentes,
/// rend l'id choisi ou « Au fil de l'eau ».
void main() {
  testWidgets('showTaskPicker : par phase, rend la tâche choisie', (tester) async {
    final d = DateTime(2026, 10, 1);
    final ph1 = ProjectPhase(id: 'p1', label: 'Préparer', startDate: d, endDate: d.add(const Duration(days: 30)));
    final ph2 = ProjectPhase(id: 'p2', label: 'Clôturer', startDate: d.add(const Duration(days: 5)), endDate: d.add(const Duration(days: 40)));
    final project = Project(title: '5e — Mathématiques', startDate: d, createdBy: 'user', phases: [ph1, ph2], tasks: [
      ProjectTask(id: 'a', title: '📝 Préparer — Séance du 3 nov', phaseId: 'p1', startDate: d, actions: [TaskAction(title: 'x', done: true), TaskAction(title: 'y')]),
      ProjectTask(id: 'b', title: '✅ Clôturer — Séance du 19 oct', phaseId: 'p2', startDate: d),
      ProjectTask(id: 'c', title: 'Tâche faite', phaseId: 'p1', startDate: d, status: 'done'),
    ]);
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(onPressed: () async => result = await showTaskPicker(ctx, project: project, currentTaskId: 'a'), child: const Text('go')),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('PRÉPARER · 1'), findsOneWidget);
    expect(find.text('CLÔTURER · 1'), findsOneWidget);
    expect(find.text('Préparer — Séance du 3 nov'), findsOneWidget);
    expect(find.textContaining('1 / 2 actions'), findsOneWidget);
    expect(find.text('Tâche faite'), findsNothing);
    await tester.tap(find.text('Clôturer — Séance du 19 oct'));
    await tester.pumpAndSettle();
    expect(result, 'b');
  });
}
