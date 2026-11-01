import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';

void main() {
  test('les tâches sans action ouverte du projet lié sont proposées', () {
    final p = Project(id: 'p', title: 'Sortir une v1', createdBy: 'test', linkedActivityId: 'prod', startDate: DateTime(2026, 10, 30), tasks: [
      ProjectTask(id: 't1', title: 'Faire le plan', startDate: DateTime(2026, 10, 30), actions: [TaskAction(id: 'a1', title: 'Faire le plan')]),
      ProjectTask(id: 't2', title: 'Terminer les fonctionnalités', startDate: DateTime(2026, 10, 30)),
      ProjectTask(id: 't3', title: 'Finie', startDate: DateTime(2026, 10, 30), status: 'done'),
    ]);
    final today = DateTime(2026, 11, 1);
    final tasks = stopTaskCandidates([p], 'prod', today: today);
    expect(tasks.map((x) => x.task.id), ['t2']);
    expect(stopTaskCandidates([p], 'autre', today: today), isEmpty);
    expect(stopTargetCandidates([p], const [], 'prod', today: today).map((x) => x.action.id), ['a1']);
  });
}
