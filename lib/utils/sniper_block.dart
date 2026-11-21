import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show isMilestoneTask;
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedBlock;
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin;

/// Le Sniper DANS le bloc en cours (maquette validée 2026-11-21, « Sniper dans le bloc en cours ») :
/// quand un bloc de tâche ou d'activité est commencé, la lunette couvre ce qui reste du bloc et
/// vise son contenu (les actions de la tâche ; pour une activité, une action par projet lié puis
/// « le temps qui reste »), dans l'ordre du bloc.

/// Moins de 5 minutes avant la fin : le bloc ne se vise plus.
const kSniperBlockMinLeft = 5;

/// Le bloc en cours que le Sniper peut viser, sinon null : à faire, commencé et pas fini, avec un
/// contenu (une tâche, un projet ou une activité-temps). Jamais un rendez-vous d'agenda, un bloc de
/// temps (Deep work, Petites choses : ils ont leur mode), un besoin de base, une pause, un bloc de
/// séance ou un bloc à déroulé.
ScheduleBlock? sniperBlockOf({
  required List<ScheduleBlock> blocks,
  required int nowMin,
  required List<Activity> activities,
  required List<Project> projects,
}) {
  final byId = {for (final a in activities) a.id: a};
  for (final b in blocks) {
    if (b.status != 'pending' || b.kind != 'normal' || b.isTimeBlock || b.gcalEventId != null) continue;
    if (b.category == 'break' || b.sessionTemplateId != null) continue;
    final s = blockStartMin(b), e = blockEndMin(b);
    if (nowMin < s || e - nowMin < kSniperBlockMinLeft) continue;
    if (isBasicNeedBlock(b, byId)) continue;
    if (_isSessionBlock(b, projects)) continue;
    if (b.projectId != null) return b;
    final a = byId[b.activityId];
    if (a != null && !a.isHabit && !a.deleted) return b;
  }
  return null;
}

bool _isSessionBlock(ScheduleBlock b, List<Project> projects) {
  for (final t in b.targets) {
    if (t.taskId == null) continue;
    final p = projects.where((x) => x.id == t.projectId).firstOrNull;
    final task = p?.tasks.where((x) => x.id == t.taskId).firstOrNull;
    if (task != null && isMilestoneTask(task)) return true;
  }
  return false;
}

int _round5(num m) => ((m / 5).ceil() * 5).toInt();

int _minutesOf(TaskAction a, double factor) {
  final m = _round5((a.estimatedMin ?? 45) * (factor <= 0 ? 1 : factor));
  return m < 5 ? 5 : m;
}

Stake _actionStake(TaskAction a, {Project? project, ProjectTask? task, Activity? owner, required ScheduleBlock block, required double factor}) => Stake(
      StakeGesture(
        key: 'action:${a.id}',
        kind: StakeGestureKind.action,
        title: a.title,
        costMin: _minutesOf(a, factor),
        project: project,
        task: task,
        action: a,
        owner: owner,
        block: block,
      ),
      const [],
    );

/// Ce que le bloc contient, dans son ordre : pour chaque cible, l'action visée d'abord puis les
/// autres actions ouvertes de sa tâche (un projet entier : sa prochaine action) ; une action
/// propre d'activité visée ; pour un bloc d'activité seule, sa file (une action par projet lié,
/// puis ses actions propres). [factor] = réel / estimé des actions.
List<Stake> blockSniperStakes({
  required ScheduleBlock block,
  required List<Project> projects,
  required List<Activity> activities,
  required DateTime today,
  double factor = 1,
}) {
  final out = <Stake>[];
  final seen = <String>{};
  void add(Stake s) {
    if (seen.add(s.gesture.key)) out.add(s);
  }

  final activity = activities.where((a) => a.id == block.activityId && !a.deleted).firstOrNull;
  if (block.targets.isNotEmpty) {
    for (final t in block.targets) {
      final p = projects.where((x) => x.id == t.projectId).firstOrNull;
      if (p == null) continue;
      if (t.taskId == null) {
        final n = nextAction(p);
        if (n != null) add(_actionStake(n.action, project: p, task: n.task, block: block, factor: factor));
        continue;
      }
      final task = p.tasks.where((x) => x.id == t.taskId).firstOrNull;
      if (task == null || task.status != 'pending') continue;
      final open = task.actions.where((a) => !a.done).toList();
      final first = open.where((a) => a.id == t.actionId).firstOrNull;
      for (final a in [if (first != null) first, ...open.where((a) => a != first)]) {
        add(_actionStake(a, project: p, task: task, block: block, factor: factor));
      }
    }
    return out;
  }
  if (activity == null) return out;
  final own = activity.ownActions.where((a) => a.id == block.actionId && !a.done).firstOrNull;
  if (own != null) add(_actionStake(own, owner: activity, block: block, factor: factor));
  for (final q in blockQueue(activity: activity, projects: projects, today: today)) {
    add(_actionStake(q.action, project: q.project, task: q.task, owner: q.project == null ? activity : null, block: block, factor: factor));
  }
  return out;
}

/// La cible d'un bloc d'activité : un chrono sur l'activité jusqu'à la fin du bloc, qui contient ses
/// actions (l'activité comme contenant).
Stake blockFillStake(Activity a, int minutes, ScheduleBlock block) => Stake(
      StakeGesture(key: 'activity:${a.id}', kind: StakeGestureKind.activity, title: a.name, costMin: minutes, activity: a, block: block),
      const [],
    );

/// La cible d'un enjeu du bloc : une action à son temps estimé (déjà corrigé), un temps à sa durée.
SniperTarget? blockTargetOf(Stake s) {
  final g = s.gesture;
  switch (g.kind) {
    case StakeGestureKind.action:
      return SniperTarget(s, SniperKind.action, minutes: g.costMin < 5 ? 5 : g.costMin);
    case StakeGestureKind.activity:
      return SniperTarget(s, SniperKind.timed, minutes: g.costMin < 1 ? 1 : g.costMin);
    default:
      return null;
  }
}

Stake _withCost(Stake s, int minutes) {
  final g = s.gesture;
  return Stake(
    StakeGesture(
      key: g.key,
      kind: g.kind,
      title: g.title,
      costMin: minutes,
      activity: g.activity,
      block: g.block,
      project: g.project,
      task: g.task,
      action: g.action,
      owner: g.owner,
      objective: g.objective,
      progress: g.progress,
    ),
    s.gains,
  );
}

String _hm(int min) {
  final m = min % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Le plan dans le bloc : les cibles dans l'ordre du bloc tant qu'elles tiennent dans [budgetMin]
/// (pauses comprises) ; une première action plus longue que le bloc prend tout le temps qui reste ;
/// le reste « hors de portée ». Avec [fill] (bloc d'activité), une seule cible : l'activité jusqu'à la
/// fin du bloc, qui contient ses actions dans l'ordre (l'activité comme contenant).
SniperPlan planBlockSniper({
  required List<Stake> stakes,
  required int budgetMin,
  required int untilMin,
  Activity? fill,
  ScheduleBlock? block,
  int pauseMin = kSniperPauseMin,
  int maxTargets = kSniperMaxTargets,
}) {
  // Bloc d'activité : UNE cible, l'activité, qui contient ses actions tant qu'elles tiennent.
  if (fill != null && block != null) {
    final total = budgetMin > kSniperMaxMin ? kSniperMaxMin : budgetMin;
    if (total < kSniperBlockMinLeft) return SniperPlan(budgetMin: budgetMin, pauseMin: pauseMin);
    final steps = <SniperStep>[];
    var used = 0;
    for (final s in stakes) {
      if (s.gesture.kind != StakeGestureKind.action) continue;
      final m = s.gesture.costMin;
      if (steps.isNotEmpty && used + m > total) continue;
      steps.add(SniperStep(s.gesture, minutes: m));
      used += m;
    }
    final stake = blockFillStake(fill, total, block);
    return SniperPlan(
      aimed: [SniperTarget(stake, SniperKind.timed, minutes: total, steps: steps)],
      budgetMin: budgetMin,
      pauseMin: pauseMin,
    );
  }
  final aimed = <SniperTarget>[];
  final out = <SniperMiss>[];
  var used = 0;
  for (final s in stakes) {
    final t = blockTargetOf(s);
    if (t == null) continue;
    if (aimed.length >= maxTargets) {
      out.add(SniperMiss(t, 'au-delà de $maxTargets cibles'));
      continue;
    }
    final add = t.cost + (aimed.isEmpty ? 0 : pauseMin);
    if (used + add <= budgetMin) {
      used += add;
      aimed.add(t);
      continue;
    }
    if (aimed.isEmpty && budgetMin >= kSniperBlockMinLeft) {
      final capped = blockTargetOf(_withCost(s, budgetMin))!;
      used = budgetMin;
      aimed.add(capped);
      continue;
    }
    out.add(SniperMiss(t, 'ne tient plus avant ${_hm(untilMin)}'));
  }
  return SniperPlan(aimed: aimed, outOfReach: out, budgetMin: budgetMin, pauseMin: pauseMin);
}
