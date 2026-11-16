import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_work.dart';
import 'package:productivitwo_v1/utils/chain.dart';
import 'package:productivitwo_v1/utils/offensive.dart';
import 'package:productivitwo_v1/utils/widget_payload.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  final day = DateTime(2026, 11, 16);

  group('ScheduleBlock.extraTargets', () {
    test('aller-retour JSON, et rien d’écrit pour un bloc à une cible', () {
      final b = ScheduleBlock(startTime: '06:00', durationMin: 120, title: 'Deep work', projectId: 'p1', taskId: 't1')
        ..extraTargets = const [BlockTarget(projectId: 'p1', taskId: 't2', actionId: 'x2'), BlockTarget(projectId: 'p2')];
      final back = ScheduleBlock.from(b.toJson());
      expect(back.extraTargets, b.extraTargets);
      expect(back.targets, hasLength(3));
      expect(back.targetTaskIds, {'t1', 't2'});

      final one = ScheduleBlock(startTime: '06:00', durationMin: 60, title: 'Bloc', projectId: 'p1', taskId: 't1');
      expect(one.toJson().containsKey('extraTargets'), isFalse);
      expect(one.targets, [const BlockTarget(projectId: 'p1', taskId: 't1')]);
    });

    test('sans projet principal, pas de cible ; entrées abîmées ignorées', () {
      final b = ScheduleBlock.from({
        'startTime': '06:00',
        'title': 'Lecture',
        'activityId': 'a1',
        'extraTargets': [
          {'projectId': 'p2'}
        ],
      });
      expect(b.targets, isEmpty);
      final c = ScheduleBlock.from({
        'startTime': '06:00',
        'title': 'Bloc',
        'projectId': 'p1',
        'extraTargets': [
          {'projectId': 'p2', 'taskId': ''},
          {'taskId': 'orphelin'},
          'n’importe quoi',
        ],
      });
      expect(c.extraTargets, [const BlockTarget(projectId: 'p2')]);
    });

    test('targets = : la première devient la principale, vide = plus de cible', () {
      final b = ScheduleBlock(startTime: '06:00', durationMin: 60, title: 'Bloc', projectId: 'p1', taskId: 't1', actionId: 'x1');
      b.targets = const [BlockTarget(projectId: 'p2', taskId: 'u1'), BlockTarget(projectId: 'p1', taskId: 't1', actionId: 'x1')];
      expect((b.projectId, b.taskId, b.actionId), ('p2', 'u1', null));
      expect(b.extraTargets, [const BlockTarget(projectId: 'p1', taskId: 't1', actionId: 'x1')]);
      b.targets = const [];
      expect((b.projectId, b.taskId, b.actionId), (null, null, null));
      expect(b.extraTargets, isEmpty);
    });
  });

  group('le chrono de chaque cible compte pour le bloc', () {
    Session s(String id, {String? taskId, String? actionId, int fromMin = 0, int min = 30}) => Session(
        id: id,
        activityId: 'a1',
        startAt: day.add(Duration(hours: 6, minutes: fromMin)),
        endAt: day.add(Duration(hours: 6, minutes: fromMin + min)),
        taskId: taskId,
        actionId: actionId);
    final block = ScheduleBlock(startTime: '06:00', durationMin: 120, title: 'Bloc', projectId: 'p1', taskId: 't1', actionId: 'x1')
      ..extraTargets = const [BlockTarget(projectId: 'p1', taskId: 't2')];
    final start = day.add(const Duration(hours: 6)), end = day.add(const Duration(hours: 8));

    test('sessionMatchesBlock : la tâche principale ou une suivante', () {
      expect(sessionMatchesBlock(s('1', taskId: 't1'), block), isTrue);
      expect(sessionMatchesBlock(s('2', taskId: 't2'), block), isTrue);
      expect(sessionMatchesBlock(s('3', taskId: 't9'), block), isFalse);
      expect(sessionMatchesBlock(s('4'), block), isFalse);
    });

    test('loggedMinForBlock additionne les cibles', () {
      final sessions = [
        s('1', taskId: 't1', actionId: 'x1', min: 30),
        s('2', taskId: 't2', fromMin: 30, min: 40),
        s('3', taskId: 't9', fromMin: 70, min: 20),
      ];
      expect(loggedMinForBlock(block, sessions, start, end), 70);
      // Une seule cible : comme avant, seule son action compte.
      final single = ScheduleBlock(startTime: '06:00', durationMin: 120, title: 'Bloc', projectId: 'p1', taskId: 't1', actionId: 'x1');
      expect(loggedMinForBlock(single, sessions, start, end), 30);
    });
  });

  group('buildBlockQueue', () {
    TaskAction a(String id, {bool done = false}) => TaskAction(id: id, title: id, done: done);
    final p1 = Project(id: 'p1', title: 'Maths 6e', startDate: day, createdBy: 'user', tasks: [
      ProjectTask(id: 't1', title: 'Préparer', startDate: day, actions: [a('a1'), a('a2'), a('a3', done: true)]),
      ProjectTask(id: 't2', title: 'Corriger', startDate: day, actions: [a('b1')]),
      ProjectTask(id: 't3', title: 'Faite', startDate: day, status: 'done', actions: [a('c1')]),
    ]);
    final p2 = Project(id: 'p2', title: 'CM', startDate: day, createdBy: 'user', tasks: [
      ProjectTask(id: 'u1', title: 'Fiche', startDate: day, actions: [a('d1'), a('d2')]),
    ]);

    test('les cibles dans l’ordre du bloc, l’action visée d’abord', () {
      final q = buildBlockQueue([p1, p2], day, const [
        BlockTarget(projectId: 'p1', taskId: 't2'),
        BlockTarget(projectId: 'p1', taskId: 't1', actionId: 'a2'),
      ]);
      expect([for (final t in q) t.action.id], ['b1', 'a2', 'a1']);
    });

    test('un projet entier donne ses actions prêtes, sans doublon ; tâche faite ou inconnue ignorée', () {
      final q = buildBlockQueue([p1, p2], day, const [
        BlockTarget(projectId: 'p2', taskId: 'u1', actionId: 'd2'),
        BlockTarget(projectId: 'p2'),
        BlockTarget(projectId: 'p1', taskId: 't3'),
        BlockTarget(projectId: 'p1', taskId: 'inconnue'),
        BlockTarget(projectId: 'nulle-part'),
      ]);
      expect([for (final t in q) t.action.id], ['d2', 'd1']);
    });
  });
  group('les cibles suivantes vues par le reste de l’app', () {
    TaskAction a(String id, {bool done = false}) => TaskAction(id: id, title: 'Action $id', done: done);
    Project build({bool firstDone = false}) => Project(id: 'p1', title: 'Maths 6e', startDate: day, createdBy: 'user', tasks: [
          ProjectTask(id: 't1', title: 'Préparer', startDate: day, actions: [a('a1', done: firstDone)]),
          ProjectTask(id: 't2', title: 'Corriger', startDate: day, actions: [
            TaskAction(id: 'b1', title: 'Corriger les copies', checklist: [ChecklistItem(id: 'c1', title: 'Paquet A')]),
          ]),
        ]);
    ScheduleBlock block() =>
        ScheduleBlock(startTime: '06:00', durationMin: 120, title: 'Bloc', projectId: 'p1', taskId: 't1', actionId: 'a1')
          ..extraTargets = const [BlockTarget(projectId: 'p1', taskId: 't2', actionId: 'b1')];

    test('targetActionIds : ce qui est « au programme »', () {
      expect(block().targetActionIds, {'a1', 'b1'});
    });

    test('activeTargetOf : la première cible où il reste à faire', () {
      expect(activeTargetOf(block(), [build()])!.taskId, 't1');
      expect(activeTargetOf(block(), [build(firstDone: true)])!.taskId, 't2');
      // Une seule cible : elle, même faite.
      final single = ScheduleBlock(startTime: '06:00', durationMin: 60, title: 'Bloc', projectId: 'p1', taskId: 't1');
      expect(activeTargetOf(single, [build(firstDone: true)])!.taskId, 't1');
      expect(activeTargetOf(ScheduleBlock(startTime: '06:00', durationMin: 60, title: 'Libre'), [build()]), isNull);
    });

    test('Enchaîner déroule la tâche principale puis les suivantes', () {
      final items = chainItemsOf(block(), projects: [build()], activities: const [], hits: const [], now: day);
      expect([for (final i in items) i.action?.id], ['a1', 'b1']);
      expect(items.last.task?.id, 't2');
      expect(items.last.step?.id, 'c1');
    });

    test('le widget montre la cible du moment, ses boutons agissent sur elle', () {
      final w = widgetBlock(block(), day, '2026-11-16', [build(firstDone: true)]);
      expect(w['ctx'], 'Maths 6e › Corriger');
      expect((w['taskId'], w['actionId'], w['itemId']), ('t2', 'b1', 'c1'));
      final first = widgetBlock(block(), day, '2026-11-16', [build()]);
      expect((first['taskId'], first['actionId']), ('t1', 'a1'));
    });
  });
}
