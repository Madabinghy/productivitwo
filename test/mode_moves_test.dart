import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/chain.dart';
import 'package:productivitwo_v1/utils/mode_moves.dart';

void main() {
  final today = DateTime(2026, 10, 27, 14, 7);
  Project proj(String id, {String? linked, List<ProjectTask> tasks = const []}) =>
      Project(id: id, title: id, startDate: DateTime(2026, 9, 1), createdBy: 'u', linkedActivityId: linked, tasks: tasks);
  Activity act(String id) => Activity(id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'time', goalMin: 1, createdAt: DateTime(2026, 1, 1));

  test('candidats : coup en cours (projet → prochaine action), puis projet en retard, puis objectif ; doublons de source écartés', () {
    final action = TaskAction(id: 'a1', title: 'Écrire le chapitre 3');
    final task = ProjectTask(id: 't1', title: 'Chapitre 3', startDate: DateTime(2026, 10, 1), actions: [action]);
    final p = proj('livre', linked: 'ecrire', tasks: [task]);
    final coup = StrategicObjective(title: 'Finir le chapitre 3', horizon: 'tactical', endDate: DateTime(2026, 10, 30), projectIds: ['livre']);
    final expired = StrategicObjective(title: 'Vieux coup', horizon: 'tactical', endDate: DateTime(2026, 10, 20), projectIds: ['livre']);
    final strat = StrategicObjective(title: 'Lire plus', timeCommitments: [ObjectiveTimeCommitment(activityId: 'lire', weeklyMin: 140)]);
    final c = deepWorkCandidates(
      objectives: [strat, expired, coup],
      projects: [p],
      activities: [act('ecrire'), act('lire')],
      today: today,
      nextOf: (x) => x.id == 'livre' ? (project: x, task: task, action: action) : null,
      projectPick: (project: p, task: task, action: action), // même source que le coup → écarté
      objectivePick: (objective: strat, activityId: 'lire'),
    );
    expect(c.map((x) => x.kind).toList(), ['coup', 'objective']);
    expect(c.first.title, 'Finir le chapitre 3');
    expect(c.first.subtitle, contains('jusqu\'au 30 oct.'));
    expect(c.first.subtitle, contains('Écrire le chapitre 3'));
    expect((c.first.projectId, c.first.taskId, c.first.actionId, c.first.activityId), ('livre', 't1', 'a1', 'ecrire'));
    expect(c.last.activityId, 'lire');
    expect(c.last.subtitle, contains('chrono lire'));
  });

  test('coup sans projet → premier engagement de temps ; rien de lançable → rien', () {
    final coup = StrategicObjective(title: 'Sprint lecture', horizon: 'tactical', endDate: DateTime(2026, 11, 2), timeCommitments: [ObjectiveTimeCommitment(activityId: 'lire', weeklyMin: 300)]);
    final vide = StrategicObjective(title: 'Sans source', horizon: 'tactical', endDate: DateTime(2026, 11, 2));
    final c = deepWorkCandidates(objectives: [vide, coup], projects: const [], activities: [act('lire')], today: today);
    expect(c.length, 1);
    expect((c.single.kind, c.single.activityId, c.single.objectiveId), ('coup', 'lire', coup.id));
  });

  test('bloc de deep work : 90 min à partir de maintenant arrondi aux 5 min, sur la source', () {
    const c = DeepWorkCandidate(kind: 'project', title: 'Livre', subtitle: '', projectId: 'livre', taskId: 't1', actionId: 'a1', activityId: 'ecrire');
    final b = deepWorkBlock(c, today);
    expect(b.startTime, '14:05');
    expect(b.durationMin, 90);
    expect(b.title, 'Deep work · Livre');
    expect((b.category, b.projectId, b.taskId, b.actionId, b.activityId), ('project', 'livre', 't1', 'a1', 'ecrire'));
    final a = deepWorkBlock(const DeepWorkCandidate(kind: 'other', title: 'Lire', subtitle: '', activityId: 'lire'), DateTime(2026, 10, 27, 1, 30), dayStartMin: 300);
    expect(a.startTime, '01:30'); // minute vécue 25 h 30 → heure d'horloge
    expect(a.category, 'personal');
  });

  test('3 petites choses : routines, étapes et actions ≤ 10 min, dans l\'ordre, 3 au plus', () {
    final blk = ScheduleBlock(id: 'b', startTime: '09:00', durationMin: 60, title: 'B', category: 'project');
    ChainItem it(ChainKind k, {int? est}) => ChainItem(kind: k, block: blk, action: k == ChainKind.action ? TaskAction(title: 'x', estimatedMin: est) : null);
    final items = [
      it(ChainKind.block),
      it(ChainKind.routine),
      it(ChainKind.action, est: 45),
      it(ChainKind.step),
      it(ChainKind.action, est: 10),
      it(ChainKind.action, est: 5),
      it(ChainKind.session),
    ];
    final s = smallChain(items);
    expect(s.length, 3);
    expect(s.map((i) => i.kind).toList(), [ChainKind.routine, ChainKind.step, ChainKind.action]);
    expect(s.last.action!.estimatedMin, 10);
    expect(smallChain([it(ChainKind.action)]), isEmpty); // sans estimation = 45 min, pas « petite »
  });
}
