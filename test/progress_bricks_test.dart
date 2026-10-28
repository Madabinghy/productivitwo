import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';

void main() {
  final today = DateTime(2026, 10, 28, 10);

  ProjectTask task(String id, String start, {String? end, String status = 'pending', List<TaskAction>? actions}) => ProjectTask(
      id: id, title: id, startDate: DateTime.parse(start), endDate: end == null ? null : DateTime.parse(end), status: status, actions: actions);
  Project proj(List<ProjectTask> tasks) =>
      Project(id: 'p', title: 'p', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: tasks, createdAt: DateTime(2026, 9, 1));

  test('actionFill / taskFill : étapes puis actions, moyenne des parts', () {
    final a = TaskAction(id: 'a', title: 'a', checklist: [ChecklistItem(title: '1', done: true), ChecklistItem(title: '2')]);
    final b = TaskAction(id: 'b', title: 'b', done: true);
    final c = TaskAction(id: 'c', title: 'c');
    expect(actionFill(a), .5);
    expect(actionFill(b), 1);
    expect(actionFill(c), 0);
    expect(taskFill(task('t', '2026-10-01', actions: [a, b, c])), .5);
    expect(taskFill(task('t', '2026-10-01')), 0);
    expect(taskFill(task('t', '2026-10-01', status: 'done')), 1);
  });

  test('projectBricks : ordre Gantt, états, trait = tâches attendues, hors gtd-flow / sautées', () {
    final p = proj([
      task('done', '2026-10-01', end: '2026-10-05', status: 'done'),
      task('late', '2026-10-06', end: '2026-10-20', actions: [TaskAction(id: 'l1', title: 'x')]),
      task('started', '2026-10-10', end: '2026-11-10', actions: [TaskAction(id: 's1', title: 'x', done: true), TaskAction(id: 's2', title: 'y')]),
      task('run', '2026-10-12', end: '2026-11-12', actions: [TaskAction(id: 'r1', title: 'x')]),
      task('todo', '2026-10-15', end: '2026-11-15'),
      task('up', '2026-11-02', end: '2026-11-20'),
      task('skip', '2026-10-01', status: 'skipped'),
      task('gtd-flow', '2026-10-01'),
    ]);
    final row = projectBricks(p, today, runningActionIds: {'r1'});
    expect(row.bricks.map((b) => b.id).toList(), ['done', 'late', 'started', 'run', 'todo', 'up']);
    expect(row.bricks.map((b) => b.state).toList(),
        [BrickState.done, BrickState.late, BrickState.started, BrickState.running, BrickState.todo, BrickState.upcoming]);
    expect(row.bricks[2].fill, .5);
    expect(row.expected, 2); // done (éch. 5 oct.) + late (éch. 20 oct.) ; les autres échoient en novembre
    expect(row.tickX, closeTo(2 / 6, 1e-9));
    expect(row.done, 1);
    expect(row.behindTick, 1);
    expect(behindLabel(row), '1 tâche derrière le trait : 1 en retard');
    expect(row.hasRunning, isTrue);
  });

  test('taskBricks : une brique par action, échéance propre en retard, trait sur les échues', () {
    final t = task('t', '2026-10-01', end: '2026-11-05', actions: [
      TaskAction(id: 'a', title: 'a', done: true),
      TaskAction(id: 'b', title: 'b', dueDate: DateTime(2026, 10, 27)),
      TaskAction(id: 'c', title: 'c', checklist: [ChecklistItem(title: '1', done: true), ChecklistItem(title: '2'), ChecklistItem(title: '3')]),
      TaskAction(id: 'd', title: 'd'),
    ]);
    final row = taskBricks(t, today, runningActionIds: {'c'});
    expect(row.bricks.map((b) => b.state).toList(), [BrickState.done, BrickState.late, BrickState.running, BrickState.todo]);
    expect(row.bricks[2].fill, closeTo(1 / 3, 1e-9));
    expect(row.bricks[2].done, 1);
    expect(row.bricks[2].total, 3);
    expect(row.expected, 1); // seule b est échue (27 oct.) ; la tâche échoit le 5 nov.
  });

  test('runningTargets : chronos ouverts seulement ; wallDigest : projets derrière le trait', () {
    final r = runningTargets([
      Session(id: '1', activityId: 'x', startAt: today, taskId: 't1', actionId: 'a1'),
      Session(id: '2', activityId: 'x', startAt: today, endAt: today, taskId: 't2'),
      Session(id: '3', activityId: 'x', startAt: today, taskId: 't3', deleted: true),
    ]);
    expect(r.taskIds, {'t1'});
    expect(r.actionIds, {'a1'});
    final fine = projectBricks(proj([task('a', '2026-10-01', end: '2026-10-05', status: 'done'), task('b', '2026-11-01', end: '2026-11-05')]), today);
    final behind = projectBricks(proj([task('a', '2026-10-01', end: '2026-10-05')]), today);
    expect(behindLabel(fine), isNull);
    expect(wallDigest([fine, behind]), (done: 1, total: 3, behind: 1));
  });
}
