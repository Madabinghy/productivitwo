import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';

void main() {
  final d0 = DateTime(2026, 9, 28);
  final spec = [
    TaskAction(id: 'o', title: 'Objectif : offre en 4 pages'),
    TaskAction(id: 'c', title: 'Critères : devis · planning · clause'),
    TaskAction(id: 'k', title: 'Contraintes : pas de remise > 10 %'),
  ];
  final steps = [
    TaskAction(id: 'a1', title: 'Reprendre le brief', done: true),
    TaskAction(id: 'a2', title: 'Chiffrer les modules', checklist: [
      ChecklistItem(id: 'i1', title: 'Base', done: true),
      ChecklistItem(id: 'i2', title: 'Atelier'),
    ]),
    TaskAction(id: 'a3', title: 'Relire et exporter'),
  ];
  final t1 = ProjectTask(id: 't1', title: 'Proposition', startDate: d0, phaseId: 'ph2',
      actions: [...spec, ...steps]);
  final t2 = ProjectTask(id: 't2', title: 'Relance', startDate: d0,
      actions: [TaskAction(id: 'b1', title: 'Appeler'), TaskAction(id: 'b2', title: 'Noter')]);
  final p = Project(id: 'p', title: 'Cléa', startDate: d0, createdBy: 'u', tasks: [t1, t2],
      phases: [ProjectPhase(id: 'ph2', label: 'Commercial', startDate: d0, endDate: d0)],
      linkedActivityId: 'actP');

  test('spec 4 lignes séparée des étapes', () {
    expect(taskSpecLines(t1).map((l) => l.label), ['Objectif', 'Critères', 'Contraintes']);
    expect(taskSpecLines(t1).first.text, 'offre en 4 pages');
    expect(taskSteps(t1).map((a) => a.id), ['a1', 'a2', 'a3']);
    expect(specLineOf('Appeler : Marta'), isNull);
  });

  test('cible = bloc courant quand le chrono lui correspond', () {
    final b = ScheduleBlock(startTime: '08:30', durationMin: 60, title: 'Offre',
        projectId: 'p', taskId: 't1', actionId: 'a2');
    final s = Session(activityId: 'actP', startAt: d0, taskId: 't1', actionId: 'a2');
    final f = resolveFocusTarget(open: s, currentBlock: b, projects: [p])!;
    expect(f.block, same(b));
    expect(f.action.id, 'a2');
    expect(f.phase?.label, 'Commercial');
    expect(f.stepsAreTaskActions, isFalse);
  });

  test('chrono hors bloc : tâche/action de la session ; sans action → prochaine ouverte', () {
    final other = ScheduleBlock(startTime: '08:30', durationMin: 60, title: 'Autre',
        projectId: 'p', taskId: 't1');
    final s = Session(activityId: 'actP', startAt: d0, taskId: 't2');
    final f = resolveFocusTarget(open: s, currentBlock: other, projects: [p])!;
    expect(f.block, isNull);
    expect(f.task.id, 't2');
    expect(f.action.id, 'b1');
    expect(f.stepsAreTaskActions, isTrue);
  });

  test('pas de bande sans tâche', () {
    final s = Session(activityId: 'x', startAt: d0);
    expect(resolveFocusTarget(open: s, currentBlock: null, projects: [p]), isNull);
    expect(resolveFocusTarget(open: null, currentBlock: null, projects: [p]), isNull);
  });

  test('documents : ceux de la tâche d\'abord, sinon ceux du projet', () {
    final docs = [
      {'id': 'd1', 'title': 'Brief', 'taskId': 't2'},
      {'id': 'd2', 'title': 'Offre type'},
    ];
    expect(focusDocuments(docs, 't2').map((d) => d['id']), ['d1']);
    expect(focusDocuments(docs, 't1').map((d) => d['id']), ['d1', 'd2']);
  });

  test('étape suivante après la courante', () {
    expect(nextStepAfter(t1, steps[1])?.id, 'a3');
    expect(nextStepAfter(t1, steps[2])?.id, 'a2'); // repli : étape ouverte restante
  });
}
