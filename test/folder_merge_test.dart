import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/folder_merge.dart';

void main() {
  final d0 = DateTime(2026, 9, 1);
  ProjectTask task(String id, {String? phaseId}) =>
      ProjectTask(id: id, title: id, startDate: d0, phaseId: phaseId, actions: [TaskAction(title: 'a')]);
  final folder = Project(id: 'F', title: 'Chérubins', startDate: d0, createdBy: 'u', tasks: []);
  final cm = Project(id: 'CM', title: 'CM', startDate: DateTime(2026, 9, 28), endDate: DateTime(2027, 6, 30),
      createdBy: 'u', parentProjectId: 'F',
      phases: [ProjectPhase(id: 'p1', label: 'P1', startDate: d0, endDate: d0)],
      tasks: [task('t1', phaseId: 'p1'), task('t2')]);
  final six = Project(id: '6e', title: '6e', startDate: DateTime(2026, 9, 7), createdBy: 'u',
      parentProjectId: 'F', tasks: [task('t3')]);
  final archived = Project(id: 'old', title: 'old', startDate: d0, createdBy: 'u',
      parentProjectId: 'F', status: 'archived', tasks: [task('t9')]);
  final sof = Project(id: 'SOF', title: 'SOF', startDate: d0, createdBy: 'u', tasks: [task('s1')]);
  final all = [folder, cm, six, archived, sof];

  test('isFolder : sans tâche avec enfants', () {
    expect(isFolder(folder, all), isTrue);
    expect(isFolder(sof, all), isFalse);
  });

  test('mergeFolder : une section par sous-projet, tâches copiées, dates englobantes', () {
    final m = mergeFolder(folder, all);
    expect(m.children.map((c) => c.id), ['6e', 'CM']);
    expect(m.view.id, 'F');
    expect(m.view.phases.map((p) => p.label), ['6e', 'CM']);
    expect(m.view.tasks.map((t) => t.id).toSet(), {'t1', 't2', 't3'});
    expect(m.view.tasks.firstWhere((t) => t.id == 't1').phaseId, 'CM');
    expect(m.originPhase['t1'], 'p1');
    expect(m.view.startDate, DateTime(2026, 9, 7));
    expect(m.view.endDate, DateTime(2027, 6, 30));
    // les copies n'altèrent pas l'original
    expect(cm.tasks.first.phaseId, 'p1');
  });

  test('splitMergedTasks : phase d\'origine restaurée, déplacement, nouvelle tâche', () {
    final m = mergeFolder(folder, all);
    final merged = List.of(m.view.tasks);
    merged.firstWhere((t) => t.id == 't3').phaseId = 'CM'; // déplacée 6e → CM
    merged.add(task('new', phaseId: '6e'));
    merged.add(task('loose'));
    final split = splitMergedTasks(m, merged);
    expect(split['CM']!.map((t) => t.id).toSet(), {'t1', 't2', 't3'});
    expect(split['CM']!.firstWhere((t) => t.id == 't1').phaseId, 'p1');
    expect(split['CM']!.firstWhere((t) => t.id == 't3').phaseId, isNull);
    expect(split['6e']!.map((t) => t.id), ['new', 'loose']);
    expect(split.containsKey('old'), isFalse);
  });
}
