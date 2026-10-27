import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';

void main() {
  Activity act() => Activity(id: 'a1', name: 'Admin', domainId: 'd', type: 'time', goalMin: 30, ownActions: [
        TaskAction(id: 'x1', title: 'Relancer le client', note: 'Mail de juin', contexts: ['@ordinateur'], estimatedMin: 10),
        TaskAction(id: 'x2', title: 'Autre'),
      ]);
  Project proj({bool withTask = true}) => Project(
        id: 'p1',
        title: 'SOF',
        createdBy: 'u',
        startDate: DateTime(2026, 10, 1),
        tasks: [if (withTask) ProjectTask(id: 't1', title: 'Factures', startDate: DateTime(2026, 10, 1), status: 'done')],
      );

  test('vers une tâche donnée : l\'action change de maison et garde tout', () {
    final a = act();
    final p = proj();
    final t = attachOwnActionToProject(a, 'x1', p, task: p.tasks.first)!;
    expect(t.id, 't1');
    expect(t.status, 'pending'); // tâche rouverte pour accueillir une action ouverte
    expect(a.ownActions.map((x) => x.id), ['x2']);
    final moved = t.actions.single;
    expect(moved.id, 'x1');
    expect(moved.note, 'Mail de juin');
    expect(moved.allContexts, {'@ordinateur'});
    expect(moved.estimatedMin, 10);
    expect(moved.linkedActivityId, 'a1');
  });

  test('sans tâche : « Au fil de l\'eau » créée dans le projet', () {
    final a = act();
    final p = proj(withTask: false);
    final t = attachOwnActionToProject(a, 'x1', p)!;
    expect(t.id, kFlowTaskId);
    expect(p.tasks.map((x) => x.id), [kFlowTaskId]);
    expect(t.actions.single.id, 'x1');
  });

  test('action inconnue : rien ne bouge', () {
    final a = act();
    final p = proj();
    expect(attachOwnActionToProject(a, 'nope', p), isNull);
    expect(a.ownActions.length, 2);
    expect(p.tasks.first.actions, isEmpty);
  });
}
