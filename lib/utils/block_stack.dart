import 'package:productivitwo_v1/models.dart';

/// Empiler sur un bloc (2026-11-16) : un bloc du programme porte jusqu'à trois
/// COUCHES indépendantes — un MODE (bloc de temps : Deep work · Petites
/// choses), une ACTIVITÉ (là où le temps compte) et une CIBLE (projet, tâche,
/// action). Rien de neuf en base : ce sont les champs `timeBlock`,
/// `activityId`, `projectId` / `taskId` / `actionId` du bloc.
const kTimeBlockLabels = {'deep': 'Deep work', 'small': 'Petites choses', 'buffer': 'Tampon'};

class BlockLayers {
  final String? timeBlock, activityId, projectId, taskId, actionId;
  const BlockLayers({this.timeBlock, this.activityId, this.projectId, this.taskId, this.actionId});

  factory BlockLayers.of(ScheduleBlock b) => BlockLayers(
      timeBlock: b.timeBlock, activityId: b.activityId, projectId: b.projectId, taskId: b.taskId, actionId: b.actionId);

  bool get isEmpty => timeBlock == null && activityId == null && projectId == null;
  bool get hasTarget => projectId != null;

  /// Seulement une activité (ce qu'un rendez-vous d'agenda peut recevoir).
  bool get activityOnly => activityId != null && timeBlock == null && projectId == null;

  void applyTo(ScheduleBlock b) {
    b.timeBlock = timeBlock;
    b.activityId = activityId;
    b.projectId = projectId;
    b.taskId = taskId;
    b.actionId = actionId;
  }

  BlockLayers withoutMode() => BlockLayers(activityId: activityId, projectId: projectId, taskId: taskId, actionId: actionId);

  /// Sans l'activité : l'action propre qu'elle portait part avec elle.
  BlockLayers withoutActivity() =>
      BlockLayers(timeBlock: timeBlock, projectId: projectId, taskId: taskId, actionId: projectId == null ? null : actionId);

  BlockLayers withoutTarget() => BlockLayers(timeBlock: timeBlock, activityId: activityId);

  @override
  bool operator ==(Object other) =>
      other is BlockLayers &&
      other.timeBlock == timeBlock &&
      other.activityId == activityId &&
      other.projectId == projectId &&
      other.taskId == taskId &&
      other.actionId == actionId;

  @override
  int get hashCode => Object.hash(timeBlock, activityId, projectId, taskId, actionId);
}

/// [add] posé sur [base] : chaque couche apportée remplace la sienne, les
/// autres restent. Une cible (projet) vient entière, avec sa tâche et son
/// action ; changer d'activité sans cible lâche l'action propre de l'ancienne.
BlockLayers stackLayers(BlockLayers base, BlockLayers add) {
  final target = add.hasTarget;
  final activity = add.activityId ?? base.activityId;
  final keepOwnAction = base.projectId != null || activity == base.activityId;
  return BlockLayers(
    timeBlock: add.timeBlock ?? base.timeBlock,
    activityId: activity,
    projectId: target ? add.projectId : base.projectId,
    taskId: target ? add.taskId : base.taskId,
    actionId: target ? add.actionId : (keepOwnAction ? base.actionId : null),
  );
}

/// Un bloc qui peut recevoir une couche : à faire, normal, pas une pause.
/// Le jour passé et les besoins de base (sommeil, repas) se décident à l'appel.
bool canStackOn(ScheduleBlock b) => b.status == 'pending' && b.kind == 'normal' && b.category != 'break';

/// Pourquoi [add] ne se pose pas sur [b] (null = il se pose). Un rendez-vous
/// d'agenda ne prend qu'une activité : son titre et son heure viennent de
/// l'agenda, et ce n'est ni un Deep work ni une tâche.
String? stackRefusal(ScheduleBlock b, BlockLayers add) {
  if (add.isEmpty) return 'Rien à ajouter à ce bloc.';
  if (!canStackOn(b)) return 'Ce bloc ne peut plus rien recevoir.';
  if (b.gcalEventId != null && !add.activityOnly) return 'Un rendez-vous d’agenda ne reçoit qu’une activité.';
  if (stackLayers(BlockLayers.of(b), add) == BlockLayers.of(b)) return 'Ce bloc le porte déjà.';
  return null;
}

/// Le titre que l'app donne à un bloc d'après ses couches : « Deep work ·
/// Préparer la séance », « Préparer la séance », « Interventions ».
String layersTitle({String? timeBlock, String? activity, String? project, String? task}) {
  final mode = kTimeBlockLabels[timeBlock];
  final target = task ?? project ?? activity;
  if (mode != null && target != null) return '$mode · $target';
  return mode ?? target ?? '';
}

/// Le titre après un changement de couches : un titre écrit à la main reste,
/// un titre posé par l'app ([oldAuto], ou vide) suit les couches.
String retitled(String current, String oldAuto, String newAuto) {
  final c = current.trim();
  if (newAuto.isEmpty) return current;
  return c.isEmpty || c == oldAuto ? newAuto : current;
}

/// Les couches en une ligne (« Deep work · Interventions · Maths 6e › Préparer
/// la séance »), sans ce que [title] dit déjà.
String layersLine({String? timeBlock, String? activity, String? project, String? task, String title = ''}) {
  final t = title.toLowerCase();
  bool said(String? s) => s == null || s.isEmpty || t.contains(s.toLowerCase());
  final mode = kTimeBlockLabels[timeBlock];
  final target = [if (!said(project)) project!, if (!said(task)) task!].join(' › ');
  return [if (!said(mode)) mode!, if (!said(activity)) activity!, if (target.isNotEmpty) target].join(' · ');
}
