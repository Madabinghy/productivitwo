import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';

TaskAction _a(List<String> items, {bool done = false}) => TaskAction(
      title: 'a',
      done: done,
      checklist: [for (var i = 0; i < items.length; i++) ChecklistItem(id: 'i$i', title: items[i])],
    );

void main() {
  final now = DateTime(2026, 9, 28, 10);

  group('setChecklistItem', () {
    test('cocher un item parmi d\'autres ne change pas l\'action', () {
      final a = _a(['x', 'y']);
      expect(setChecklistItem(a, 'i0', true, now: now), isFalse);
      expect(a.checklist[0].done, isTrue);
      expect(a.checklist[0].doneAt, now);
      expect(a.done, isFalse);
      expect(a.checklistDone, 1);
    });
    test('dernier item coché → action faite', () {
      final a = _a(['x', 'y']);
      setChecklistItem(a, 'i0', true, now: now);
      expect(setChecklistItem(a, 'i1', true, now: now), isTrue);
      expect(a.done, isTrue);
      expect(a.doneAt, now);
    });
    test('décocher un item d\'une action faite la rouvre', () {
      final a = _a(['x'], done: true)..checklist[0].done = true;
      expect(setChecklistItem(a, 'i0', false), isTrue);
      expect(a.done, isFalse);
      expect(a.doneAt, isNull);
    });
    test('item inconnu : rien ne bouge', () {
      final a = _a(['x']);
      expect(setChecklistItem(a, 'zz', true), isFalse);
      expect(a.checklistDone, 0);
    });
  });

  test('addChecklistItem : titre vide ignoré, action faite rouverte', () {
    final a = _a(['x'], done: true)..checklist[0].done = true;
    expect(addChecklistItem(a, '   '), isNull);
    final item = addChecklistItem(a, ' Nouveau ')!;
    expect(item.title, 'Nouveau');
    expect(a.checklistTotal, 2);
    expect(a.done, isFalse);
    removeChecklistItem(a, item.id);
    expect(a.checklistTotal, 1);
  });

  group('resolveBlockAction', () {
    final t = ProjectTask(id: 't', title: 't', startDate: DateTime(2026, 9, 1), actions: [
      TaskAction(id: 'a1', title: 'faite', done: true),
      TaskAction(id: 'a2', title: 'suivante'),
      TaskAction(id: 'a3', title: 'après'),
    ]);
    final p = Project(id: 'p', title: 'p', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [t]);
    ScheduleBlock blk({String? taskId, String? actionId}) => ScheduleBlock(
        startTime: '09:00', durationMin: 30, title: 'b', projectId: 'p', taskId: taskId, actionId: actionId);

    test('actionId explicite', () {
      expect(resolveBlockAction(p, blk(taskId: 't', actionId: 'a3'))!.action.id, 'a3');
    });
    test('sans actionId : prochaine action ouverte de la tâche', () {
      expect(resolveBlockAction(p, blk(taskId: 't'))!.action.id, 'a2');
      expect(nextOpenAction(t)!.id, 'a2');
    });
    test('bloc sans tâche ou projet inconnu → null', () {
      expect(resolveBlockAction(p, blk()), isNull);
      expect(resolveBlockAction(null, blk(taskId: 't')), isNull);
    });
  });
}
