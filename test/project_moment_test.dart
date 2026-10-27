import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/project_moment.dart';

void main() {
  final now = DateTime(2026, 10, 27, 14); // mardi

  ProjectTask task(String id, String start, {String? end, String status = 'pending', List<TaskAction>? actions, String? role, String? interventionId}) =>
      ProjectTask(
          id: id,
          title: id,
          startDate: DateTime.parse(start),
          endDate: end == null ? null : DateTime.parse(end),
          status: status,
          actions: actions,
          interventionRole: role,
          interventionId: interventionId);
  Project proj(String id, List<ProjectTask> tasks, {String status = 'active', String? parent, DateTime? created}) => Project(
      id: id, title: id, startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: tasks, status: status, parentProjectId: parent,
      createdAt: created ?? DateTime(2026, 10, 26));

  test('projectPlan : faites / total / attendues à ce jour, hors gtd-flow et sautées', () {
    final p = proj('p', [
      task('a', '2026-10-01', end: '2026-10-10', status: 'done'),
      task('b', '2026-10-05', end: '2026-10-20'), // attendue, pas faite
      task('c', '2026-10-20', end: '2026-11-05'), // pas encore attendue
      task('d', '2026-10-01', status: 'skipped'),
      task('gtd-flow', '2026-10-01'),
    ]);
    final plan = projectPlan(p, now);
    expect((plan.done, plan.total, plan.expected), (1, 3, 2));
    expect(plan.pctInt, 50);
    expect(plan.delta, -1);
  });

  test('rankProjectMoments : séance à 7 j d\'abord, puis retard de plan, puis prochaine action, puis à venir ; dossiers exclus', () {
    final sessionP = proj('Séance', [
      task('m', '2026-10-30', end: '2026-10-30', role: 'session', interventionId: 'i1'),
      task('prep', '2026-10-27', end: '2026-10-29', role: 'prep', interventionId: 'i1', actions: [TaskAction(id: 'x', title: 'Imprimer')]),
    ]);
    sessionP.interventions = [ProjectIntervention(id: 'i1', title: 'Soustractions', date: DateTime(2026, 10, 30), startTime: '09:00', endTime: '10:00')];
    final late = proj('Retard', [
      task('a', '2026-10-01', end: '2026-10-10'),
      task('b', '2026-10-01', end: '2026-10-12', status: 'done'),
      task('c', '2026-10-01', end: '2026-10-15', actions: [TaskAction(id: 'y', title: 'Faire')]),
    ]);
    final fine = proj('Bien', [task('a', '2026-10-01', end: '2026-10-10', status: 'done'), task('b', '2026-10-20', end: '2026-11-20', actions: [TaskAction(id: 'z', title: 'Suite')])]);
    final upcoming = proj('Plus tard', [task('a', '2026-11-02', end: '2026-11-20', actions: [TaskAction(id: 'u', title: 'Début')])]);
    final folder = proj('Client', []);
    final child = proj('Enfant', [task('a', '2026-10-01', end: '2026-10-10', status: 'done')], parent: 'Client');
    final archived = proj('Vieux', [task('a', '2026-10-01')], status: 'archived');
    final all = [upcoming, fine, late, sessionP, folder, child, archived];
    final ranked = rankProjectMoments(all, const [], now);
    expect(ranked.map((m) => m.project.title).toList(), ['Séance', 'Retard', 'Bien', 'Plus tard', 'Enfant']);
    final s = ranked.first;
    expect(s.sessionSoon, isTrue);
    expect(s.daysToSession, 3);
    expect(s.weekActions.map((a) => a.action.title).toList(), ['Imprimer']); // prépa de la séance
    expect(sessionLabel(s.session!, now), 'séance ven. 30 oct.');
    final r = ranked[1];
    expect(r.behind, isTrue);
    expect(r.stateLabel, 'en retard');
    expect(r.deltaLabel, '−2 tâches');
    expect(r.weekActions.map((a) => a.action.title).toList(), ['Faire']); // échéance dépassée
    expect(ranked.last.rootTitle, 'Client');
    expect(ranked.last.next, isNull);
    expect(ranked[3].upcoming, isTrue);
    expect(ranked[3].stateLabel, 'à venir');
    expect(ranked[3].weekActions, isEmpty);
  });
}
