import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_stack.dart';
import 'package:productivitwo_v1/web/schedule_block_dialog.dart';

void main() {
  final day = DateTime(2026, 11, 16);
  final activities = [Activity(id: 'a1', domainId: 'd1', name: 'Interventions')];
  final projects = [
    Project(
      id: 'p1',
      title: 'Maths 6e',
      startDate: day,
      createdBy: 'user',
      tasks: [
        ProjectTask(id: 't1', title: '📝 Préparer la séance', startDate: day),
        ProjectTask(id: 't2', title: 'Corriger les copies', startDate: day),
      ],
    ),
  ];
  final domains = [Domain(id: 'd1', name: 'Travail')];

  Future<ScheduleBlock?> Function() open(WidgetTester tester, ScheduleBlock block, {bool withLists = true}) {
    ScheduleBlock? result;
    var closed = false;
    return () async {
      if (closed) return result;
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showScheduleBlockDialog(ctx,
                      block: block,
                      activities: withLists ? activities : null,
                      projects: withLists ? projects : null,
                      domains: domains);
                  closed = true;
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return null;
    };
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
  }

  Future<void> pick(WidgetTester tester, String key, String label) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('empiler une activité puis deux tâches sur un Deep work', (tester) async {
    final block = ScheduleBlock(startTime: '06:00', durationMin: 120, title: 'Deep work', category: 'project', timeBlock: 'deep');
    await open(tester, block)();
    expect(find.text('CE BLOC PORTE'), findsOneWidget);

    await pick(tester, 'block-activity', 'Interventions');
    await pick(tester, 'block-project', 'Maths 6e');
    await pick(tester, 'block-task-0', '📝 Préparer la séance');
    // Le même projet une seconde fois, sur une autre tâche.
    await pick(tester, 'block-project', 'Maths 6e');
    await pick(tester, 'block-task-1', 'Corriger les copies');
    await save(tester);
    await tester.pumpAndSettle();

    expect(
        BlockLayers.of(block),
        const BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [
          BlockTarget(projectId: 'p1', taskId: 't1'),
          BlockTarget(projectId: 'p1', taskId: 't2'),
        ]));
    expect(block.extraTargets, hasLength(1));
    // Le titre posé par l'app a suivi les couches.
    expect(block.title, 'Deep work · Préparer la séance + 1');
  });

  testWidgets('retirer la cible principale : la suivante prend sa place', (tester) async {
    final block = ScheduleBlock(
        startTime: '06:00', durationMin: 120, title: 'Mon créneau', category: 'project', projectId: 'p1', taskId: 't1')
      ..extraTargets = const [BlockTarget(projectId: 'p1', taskId: 't2')];
    await open(tester, block)();
    await tester.ensureVisible(find.byKey(const ValueKey('block-target-remove-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-target-remove-0')));
    await tester.pumpAndSettle();
    await save(tester);
    await tester.pumpAndSettle();

    expect((block.projectId, block.taskId), ('p1', 't2'));
    expect(block.extraTargets, isEmpty);
    expect(block.title, 'Mon créneau');
  });

  testWidgets('retirer le mode et l’activité, un titre à la main reste', (tester) async {
    final block = ScheduleBlock(
        startTime: '06:00', durationMin: 120, title: 'Mon créneau', category: 'project', timeBlock: 'deep', activityId: 'a1');
    await open(tester, block)();
    await tester.ensureVisible(find.byKey(const ValueKey('block-mode-deep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-mode-deep')));
    await tester.pumpAndSettle();
    await pick(tester, 'block-activity', 'Aucune');
    await save(tester);
    await tester.pumpAndSettle();

    expect(BlockLayers.of(block), const BlockLayers());
    expect(block.title, 'Mon créneau');
  });

  testWidgets('sans les listes, les liens du bloc sont gardés tels quels', (tester) async {
    final block = ScheduleBlock(startTime: '06:00', durationMin: 60, title: 'Bloc', activityId: 'a1');
    await open(tester, block, withLists: false)();
    expect(find.text('CE BLOC PORTE'), findsNothing);
    await save(tester);
    await tester.pumpAndSettle();
    expect(block.activityId, 'a1');
  });
  testWidgets('poser le mode Miracle morning sur un bloc libre', (tester) async {
    final block = ScheduleBlock(startTime: '05:30', durationMin: 60, title: '', category: 'personal');
    await open(tester, block)();
    await tester.ensureVisible(find.byKey(const ValueKey('block-mode-morning')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('block-mode-morning')));
    await tester.pumpAndSettle();
    await save(tester);
    await tester.pumpAndSettle();
    expect(block.timeBlock, 'morning');
    expect(block.title, 'Miracle morning');
  });
}
