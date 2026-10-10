import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_work.dart';

void main() {
  TaskAction a(String id, {bool done = false}) => TaskAction(id: id, title: id, done: done);
  final task = ProjectTask(
      id: 't',
      title: 'T',
      startDate: DateTime(2026, 10, 1),
      actions: [a('fait', done: true), a('un'), a('deux'), a('trois')]);

  test('sans action visée : la première action ouverte passe en avant', () {
    final w = blockWork(task, null);
    expect(w.focus?.id, 'un');
    expect(w.open.map((x) => x.id).toList(), ['deux', 'trois']);
    expect(w.done.map((x) => x.id).toList(), ['fait']);
  });

  test('action visée par le bloc : elle passe en avant, même faite', () {
    expect(blockWork(task, 'trois').focus?.id, 'trois');
    expect(blockWork(task, 'trois').open.map((x) => x.id).toList(), ['un', 'deux']);
    final w = blockWork(task, 'fait');
    expect(w.focus?.id, 'fait');
    expect(w.done, isEmpty);
  });

  test('action visée inconnue ou tâche toute faite', () {
    expect(blockWork(task, 'disparue').focus?.id, 'un');
    final allDone = ProjectTask(
        id: 'x', title: 'X', startDate: DateTime(2026, 10, 1), actions: [a('f', done: true)]);
    final w = blockWork(allDone, null);
    expect(w.focus, isNull);
    expect(w.done.length, 1);
  });
}
