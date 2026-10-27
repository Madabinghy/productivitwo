import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/chain.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Modes et coups, lot 2 (2026-10, handoff `docs/specs/modes-et-coups-2026-10`
/// § 2.4 et § 3) : ce que le mode propose. Logique pure, aucune écriture.

/// Un candidat de « Deep work 90 min » : le coup en cours, sinon le projet le
/// plus en retard, sinon l'objectif le plus en retard sur son rythme.
class DeepWorkCandidate {
  final String kind; // coup | project | objective | other
  final String title;
  final String subtitle;
  final String? projectId;
  final String? taskId;
  final String? actionId;
  final String? activityId;
  final String? objectiveId;
  const DeepWorkCandidate({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.projectId,
    this.taskId,
    this.actionId,
    this.activityId,
    this.objectiveId,
  });

  /// Deux candidats sur la même source ne sont proposés qu'une fois.
  String get sourceKey => projectId != null ? 'p:$projectId' : 'a:${activityId ?? ''}';
  bool get launchable => projectId != null || activityId != null;
}

typedef NextPick = ({Project project, ProjectTask task, TaskAction action});

/// Coups en cours : objectifs tactiques actifs dont l'échéance n'est pas passée.
List<StrategicObjective> activeCoups(List<StrategicObjective> objectives, DateTime today) {
  final d = DateTime(today.year, today.month, today.day);
  return [
    for (final o in objectives)
      if (o.isTactical && o.status == 'active' && (o.endDate == null || !o.endDate!.isBefore(d))) o,
  ]..sort((a, b) => (a.endDate ?? d).compareTo(b.endDate ?? d));
}

/// Les candidats classés : [coups] (leur projet → prochaine action, sinon leur
/// premier engagement de temps), puis [projectPick] (projet le plus en retard,
/// calculé par l'appelant via `rankProjectMoments`), puis [objectivePick]
/// (objectif le plus en retard avec un engagement de temps, `rankObjectiveMoments`).
List<DeepWorkCandidate> deepWorkCandidates({
  required List<StrategicObjective> objectives,
  required List<Project> projects,
  required List<Activity> activities,
  required DateTime today,
  NextPick? Function(Project p)? nextOf,
  NextPick? projectPick,
  ({StrategicObjective objective, String activityId})? objectivePick,
}) {
  final out = <DeepWorkCandidate>[];
  final seen = <String>{};
  void add(DeepWorkCandidate c) {
    if (!c.launchable || !seen.add(c.sourceKey)) return;
    out.add(c);
  }

  String nameOf(String? activityId) => activities.where((a) => a.id == activityId).firstOrNull?.name ?? '';
  for (final o in activeCoups(objectives, today)) {
    final until = o.endDate == null ? '' : ' · jusqu\'au ${_dayLabel(o.endDate!)}';
    var placed = false;
    for (final pid in o.projectIds) {
      final p = projects.where((x) => x.id == pid && x.status == 'active').firstOrNull;
      if (p == null) continue;
      final n = nextOf?.call(p);
      add(DeepWorkCandidate(
        kind: 'coup',
        title: o.title,
        subtitle: 'Coup en cours$until${n != null ? ' · ${n.action.title}' : ' · ${p.title}'}',
        projectId: p.id,
        taskId: n?.task.id,
        actionId: n?.action.id,
        activityId: p.linkedActivityId,
        objectiveId: o.id,
      ));
      placed = true;
      break;
    }
    if (!placed && o.timeCommitments.isNotEmpty) {
      final c = o.timeCommitments.first;
      add(DeepWorkCandidate(
          kind: 'coup', title: o.title, subtitle: 'Coup en cours$until · ${nameOf(c.activityId)}', activityId: c.activityId, objectiveId: o.id));
    }
  }
  if (projectPick case final n?) {
    add(DeepWorkCandidate(
      kind: 'project',
      title: n.project.title,
      subtitle: 'Projet le plus en retard · ${n.action.title}',
      projectId: n.project.id,
      taskId: n.task.id,
      actionId: n.action.id,
      activityId: n.project.linkedActivityId,
    ));
  }
  if (objectivePick case final o?) {
    add(DeepWorkCandidate(
      kind: 'objective',
      title: o.objective.title,
      subtitle: 'Objectif en retard sur son rythme · chrono ${nameOf(o.activityId)}',
      activityId: o.activityId,
      objectiveId: o.objective.id,
    ));
  }
  return out;
}

String _dayLabel(DateTime d) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${months[d.month - 1]}';
}

/// Le bloc de deep work : [durationMin] à partir de maintenant (arrondi aux
/// 5 min inférieures), sur la source du candidat. Jamais lancé sans un geste.
ScheduleBlock deepWorkBlock(DeepWorkCandidate c, DateTime now, {int durationMin = 90, int dayStartMin = kDefaultDayStartMin}) {
  final min = (livedNowMin(now, dayStartMin) ~/ 5) * 5;
  final hh = ((min ~/ 60) % 24).toString().padLeft(2, '0');
  final mm = (min % 60).toString().padLeft(2, '0');
  return ScheduleBlock(
    startTime: '$hh:$mm',
    durationMin: durationMin,
    title: 'Deep work · ${c.title}',
    category: c.projectId != null ? 'project' : 'personal',
    projectId: c.projectId,
    taskId: c.taskId,
    actionId: c.actionId,
    activityId: c.activityId,
  );
}

/// Mode Flemme : « 3 petites choses » — routines, étapes et actions courtes
/// (≤ [maxMin], sans estimation = courte si c'est une étape), dans l'ordre de la
/// file, [limit] au plus.
List<ChainItem> smallChain(List<ChainItem> items, {int limit = 3, int maxMin = 10}) {
  final out = <ChainItem>[];
  for (final i in items) {
    final ok = switch (i.kind) {
      ChainKind.routine => true,
      ChainKind.step => true,
      ChainKind.action => (i.action?.estimatedMin ?? 45) <= maxMin,
      ChainKind.session || ChainKind.block => false,
    };
    if (ok) out.add(i);
    if (out.length >= limit) break;
  }
  return out;
}
