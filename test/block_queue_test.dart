import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_queue.dart';

void main() {
  final today = DateTime(2026, 10, 29, 14);
  Activity act(String id, {List<TaskAction>? own}) =>
      Activity(id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'time', createdAt: DateTime(2026, 1, 1), ownActions: own);
  ProjectTask task(String id, {String? end, String? start, String status = 'pending', List<TaskAction>? actions}) => ProjectTask(
      id: id, title: id, startDate: DateTime.parse(start ?? '2026-10-01'), endDate: end == null ? null : DateTime.parse(end), status: status, actions: actions);
  Project proj(String id, List<ProjectTask> tasks, {String? linked, String status = 'active', bool paused = false, String? parent}) => Project(
      id: id, title: id, startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: tasks, linkedActivityId: linked, status: status, paused: paused, parentProjectId: parent);

  test('une action par projet lié, en retard d\'abord, puis datées, puis actions propres', () {
    final ens = act('ens', own: [TaskAction(id: 'own1', title: 'Ranger le bureau'), TaskAction(id: 'own2', title: 'faite', done: true)]);
    final maths5 = proj('5e', [
      task('dm', end: '2026-10-27', actions: [TaskAction(id: 'copies', title: 'Corriger les copies'), TaskAction(id: 'notes', title: 'Saisir les notes')]),
    ], linked: 'ens');
    final techno = proj('techno', [
      task('cloture', end: '2026-10-17', actions: [TaskAction(id: 'fiche', title: 'Remplir la fiche', linkedActivityId: 'ens'), TaskAction(id: 'autre', title: 'Pas pour cette activité', linkedActivityId: 'sport')]),
    ]);
    final cm = proj('cm', [task('prep', end: '2026-11-03', actions: [TaskAction(id: 'prep1', title: 'Préparer la séance')])], linked: 'ens');
    final sport = proj('sport', [task('x', actions: [TaskAction(id: 'sx', title: 'x')])], linked: 'sport');
    final paused = proj('pause', [task('y', actions: [TaskAction(id: 'py', title: 'y')])], linked: 'ens', paused: true);
    final q = blockQueue(activity: ens, projects: [maths5, techno, cm, sport, paused], today: today);
    expect(q.map((e) => e.id).toList(), ['fiche', 'copies', 'prep1', 'own1']);
    expect(q[0].overdue, isTrue);
    expect(q[1].overdue, isTrue);
    expect(q[2].overdue, isFalse);
    expect(q[0].context, 'techno › cloture');
    expect(q[3].project, isNull);
    expect(queueEstimateMin(q), 4 * 45);
  });

  test('tâches à venir, faites et dossiers exclus ; vide sans lien', () {
    final ens = act('ens');
    final folder = proj('dossier', [], linked: 'ens');
    final child = proj('enfant', [
      task('future', start: '2026-11-10', actions: [TaskAction(id: 'f', title: 'f')]),
      task('done', status: 'done', actions: [TaskAction(id: 'd', title: 'd')]),
      task('now', actions: [TaskAction(id: 'n', title: 'n', done: true), TaskAction(id: 'n2', title: 'n2')]),
    ], linked: 'ens', parent: 'dossier');
    final q = blockQueue(activity: ens, projects: [folder, child], today: today);
    expect(q.map((e) => e.id).toList(), ['n2']);
    expect(blockQueue(activity: act('autre'), projects: [folder, child], today: today), isEmpty);
  });

  test('blockRemainingMin', () {
    final b = ScheduleBlock(id: 'b', startTime: '14:00', durationMin: 120, title: 'Ens', category: 'project');
    expect(blockRemainingMin(b, 13 * 60), 120);
    expect(blockRemainingMin(b, 14 * 60 + 12), 108);
    expect(blockRemainingMin(b, 17 * 60), 0);
  });
}
