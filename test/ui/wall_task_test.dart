import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/wall_task.dart';

void main() {
  testWidgets('WallTask : tâche → actions → étapes dépliées sur place, gestes remontés', (tester) async {
    final today = DateTime(2026, 10, 28, 10);
    final a = TaskAction(id: 'a', title: 'Corriger les copies', checklist: [
      ChecklistItem(id: 's1', title: 'Swann', done: true),
      ChecklistItem(id: 's2', title: 'Dylan'),
      ChecklistItem(id: 's3', title: 'Sloann'),
    ]);
    final b = TaskAction(id: 'b', title: 'Saisir les notes', estimatedMin: 15);
    final t = ProjectTask(id: 't', title: 'Corriger les DM Ch2', startDate: DateTime(2026, 10, 20), endDate: DateTime(2026, 11, 5), actions: [a, b]);
    final log = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          WallTask(
            task: t,
            today: today,
            onOpenFiche: () => log.add('fiche'),
            onOpenAction: (x) => log.add('action:${x.id}'),
            onToggleDone: () async => log.add('toggle'),
            onActionDone: (x, d) async => log.add('done:${x.id}:$d'),
            onStep: (x, c, d) async => log.add('step:${c.id}:$d'),
          ),
        ]),
      ),
    ));
    expect(find.text('Corriger les DM Ch2'), findsOneWidget);
    expect(find.text('0 / 2'), findsOneWidget);
    expect(find.byType(ProgressBricks), findsOneWidget);
    expect(find.text('Corriger les copies'), findsNothing);

    await tester.tap(find.text('Corriger les DM Ch2'));
    await tester.pumpAndSettle();
    expect(find.text('Corriger les copies'), findsOneWidget);
    expect(find.text('1 / 3 étapes'), findsOneWidget);
    expect(find.byType(StepDots), findsOneWidget);
    expect(find.text('≈ 15 min'), findsOneWidget);
    expect(find.text('Dylan'), findsNothing);

    await tester.tap(find.text('Corriger les copies'));
    await tester.pumpAndSettle();
    expect(find.text('Dylan'), findsOneWidget);
    await tester.tap(find.text('Dylan'));
    await tester.pumpAndSettle();
    expect(log, contains('step:s2:true'));

    await tester.tap(find.text('Saisir les notes'));
    await tester.pumpAndSettle();
    expect(log, contains('action:b'));
    await tester.tap(find.byTooltip('Fiche de la tâche'));
    await tester.pumpAndSettle();
    expect(log, contains('fiche'));
    expect(tester.takeException(), isNull);
  });
}
