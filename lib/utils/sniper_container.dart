import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, isUpcomingTask;
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show ganttOrder;
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

/// L'activité comme contenant (maquette validée 2026-11-21, « Sniper, l'activité comme contenant ») :
/// les actions qu'une cible de temps peut contenir, dans l'ordre de priorité, et toutes celles de sa
/// fiche pour les choisir à la main.

int _round5(num m) => ((m / 5).ceil() * 5).toInt();

/// Durée d'une action dans le tir : son estimation (45 min sans) corrigée par le facteur réel / estimé,
/// au multiple de 5, 5 min au moins.
int stepMinutes(TaskAction a, double factor) {
  final m = _round5((a.estimatedMin ?? 45) * (factor <= 0 ? 1 : factor));
  return m < 5 ? 5 : m;
}

SniperStep _step(TaskAction a, {Project? project, ProjectTask? task, Activity? owner, required double factor, String? reason}) => SniperStep(
      StakeGesture(
        key: 'action:${a.id}',
        kind: StakeGestureKind.action,
        title: a.title,
        costMin: stepMinutes(a, factor),
        project: project,
        task: task,
        action: a,
        owner: owner,
      ),
      minutes: stepMinutes(a, factor),
      reason: reason,
    );

/// Ce qui complète le contenant : la file de l'activité (une action par projet lié, puis ses actions
/// propres ; visées aujourd'hui d'abord, puis en retard, puis datées), avec la raison de chacune.
List<SniperStep> containerFill(Activity a, List<Project> projects, DateTime today, {double factor = 1}) => [
      for (final q in blockQueue(activity: a, projects: projects, today: today))
        _step(
          q.action,
          project: q.project,
          task: q.task,
          owner: q.project == null ? a : null,
          factor: factor,
          reason: q.focusedToday
              ? 'visée aujourd’hui'
              : q.overdue
                  ? 'en retard'
                  : q.project != null
                      ? 'prochaine action · ${q.project!.title}'
                      : null,
        ),
    ];

/// Toutes les actions ouvertes de la fiche de l'activité, pour les choisir à la main : celles des
/// projets vivants qui la servent (tâches ouvertes, pas à venir), puis ses actions propres.
List<SniperStep> activityStepPool(Activity a, List<Project> projects, DateTime today, {double factor = 1}) {
  final out = <SniperStep>[];
  final day = DateTime(today.year, today.month, today.day);
  for (final p in projects) {
    if (p.status != 'active' || p.paused || isFolderProject(p, projects) || !projectServesActivity(p, a.id)) continue;
    final whole = p.linkedActivityId == a.id;
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped' || isUpcomingTask(t, day)) continue;
      for (final x in t.actions) {
        if (x.done || !(whole || x.linkedActivityId == a.id)) continue;
        out.add(_step(x, project: p, task: t, factor: factor, reason: p.title));
      }
    }
  }
  for (final x in a.ownActions) {
    if (!x.done) out.add(_step(x, owner: a, factor: factor));
  }
  return out;
}
