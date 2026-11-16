import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/planning.dart' show kTimeBlockLabels;

export 'package:productivitwo_v1/utils/planning.dart' show kTimeBlockLabels;

/// Empiler sur un bloc (2026-11-16) : un bloc du programme porte des COUCHES
/// indépendantes — un MODE (bloc de temps : Deep work · Petites choses), une
/// ACTIVITÉ (là où le temps compte) et des CIBLES (projets, tâches, séances),
/// dans l'ordre. Ce sont les champs `timeBlock`, `activityId`, `projectId` /
/// `taskId` / `actionId` (la cible principale) et `extraTargets` du bloc.

/// Au-delà, un bloc n'est plus un bloc : c'est une liste.
const int kMaxBlockTargets = 6;

class BlockLayers {
  final String? timeBlock, activityId;

  /// L'action propre de l'activité, quand le bloc n'a pas de cible.
  final String? ownActionId;
  final List<BlockTarget> targets;

  const BlockLayers({this.timeBlock, this.activityId, this.ownActionId, this.targets = const []});

  /// Une seule cible (ou une action propre sans projet), comme avant.
  factory BlockLayers.single({String? timeBlock, String? activityId, String? projectId, String? taskId, String? actionId}) =>
      BlockLayers(
        timeBlock: timeBlock,
        activityId: activityId,
        ownActionId: projectId == null ? actionId : null,
        targets: projectId == null ? const [] : [BlockTarget(projectId: projectId, taskId: taskId, actionId: actionId)],
      );

  factory BlockLayers.of(ScheduleBlock b) => BlockLayers(
      timeBlock: b.timeBlock,
      activityId: b.activityId,
      ownActionId: b.projectId == null ? b.actionId : null,
      targets: b.targets);

  bool get isEmpty => timeBlock == null && activityId == null && targets.isEmpty;
  bool get hasTarget => targets.isNotEmpty;

  /// Seulement une activité (ce qu'un rendez-vous d'agenda peut recevoir).
  bool get activityOnly => activityId != null && timeBlock == null && targets.isEmpty;

  void applyTo(ScheduleBlock b) {
    b.timeBlock = timeBlock;
    b.activityId = activityId;
    b.targets = targets;
    if (targets.isEmpty) b.actionId = ownActionId;
  }

  BlockLayers _with({List<BlockTarget>? targets}) =>
      BlockLayers(timeBlock: timeBlock, activityId: activityId, ownActionId: ownActionId, targets: targets ?? this.targets);

  BlockLayers withoutMode() => BlockLayers(activityId: activityId, ownActionId: ownActionId, targets: targets);

  /// Sans l'activité : l'action propre qu'elle portait part avec elle.
  BlockLayers withoutActivity() => BlockLayers(timeBlock: timeBlock, targets: targets);

  /// Sans la cible [index] : la suivante devient la principale.
  BlockLayers withoutTargetAt(int index) => index < 0 || index >= targets.length
      ? this
      : _with(targets: [
          for (var i = 0; i < targets.length; i++)
            if (i != index) targets[i],
        ]);

  BlockLayers withoutTargets() => _with(targets: const []);

  /// La cible [index] remplacée ; une cible déjà portée ailleurs est écartée.
  BlockLayers withTargetAt(int index, BlockTarget t) {
    if (index < 0 || index >= targets.length) return this;
    for (var i = 0; i < targets.length; i++) {
      if (i != index && targets[i].sameAs(t)) return this;
    }
    return _with(targets: [
      for (var i = 0; i < targets.length; i++) i == index ? t : targets[i],
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is BlockLayers &&
      other.timeBlock == timeBlock &&
      other.activityId == activityId &&
      other.ownActionId == ownActionId &&
      other.targets.length == targets.length &&
      [for (var i = 0; i < targets.length; i++) other.targets[i] == targets[i]].every((x) => x);

  @override
  int get hashCode => Object.hash(timeBlock, activityId, ownActionId, Object.hashAll(targets));
}

/// [add] posé sur [base] : le mode et l'activité apportés REMPLACENT les
/// leurs ; une cible apportée S'AJOUTE aux cibles déjà là (dans l'ordre), sauf
/// si le bloc la porte déjà. Changer d'activité sans cible lâche l'action
/// propre de l'ancienne.
BlockLayers stackLayers(BlockLayers base, BlockLayers add) {
  final activity = add.activityId ?? base.activityId;
  final targets = [...base.targets];
  for (final t in add.targets) {
    if (targets.length >= kMaxBlockTargets) break;
    if (!targets.any((x) => x.sameAs(t))) targets.add(t);
  }
  return BlockLayers(
    timeBlock: add.timeBlock ?? base.timeBlock,
    activityId: activity,
    ownActionId: targets.isNotEmpty ? null : (activity == base.activityId ? base.ownActionId : add.ownActionId),
    targets: targets,
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
  final base = BlockLayers.of(b);
  if (add.hasTarget && base.targets.length >= kMaxBlockTargets) return 'Ce bloc porte déjà $kMaxBlockTargets cibles.';
  if (stackLayers(base, add) == base) return 'Ce bloc le porte déjà.';
  return null;
}

/// Le nom d'une cible pour un titre : la tâche, sinon le projet.
typedef TargetName = ({String? project, String? task});

/// Le titre que l'app donne à un bloc d'après ses couches : « Deep work ·
/// Préparer la séance », « Préparer la séance + 2 », « Interventions ».
String layersTitle({String? timeBlock, String? activity, List<TargetName> targets = const []}) {
  final mode = kTimeBlockLabels[timeBlock];
  final names = [
    for (final t in targets)
      if ((t.task ?? t.project) != null) (t.task ?? t.project)!,
  ];
  final target = names.isEmpty ? activity : (names.length == 1 ? names.first : '${names.first} + ${names.length - 1}');
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

/// « Maths 6e › Préparer la séance », ou le projet seul.
String targetLabel(TargetName t) => [
      if ((t.project ?? '').isNotEmpty) t.project!,
      if ((t.task ?? '').isNotEmpty) t.task!,
    ].join(' › ');

/// Les couches en une ligne (« Deep work · Interventions · Maths 6e › Préparer
/// la séance + Corriger les copies »), sans ce que [title] dit déjà. Plusieurs
/// cibles : toutes sont dites, le titre n'en nomme qu'une.
String layersLine({String? timeBlock, String? activity, List<TargetName> targets = const [], String title = ''}) {
  final t = title.toLowerCase();
  bool said(String? s) => s == null || s.isEmpty || t.contains(s.toLowerCase());
  final mode = kTimeBlockLabels[timeBlock];
  final String target;
  if (targets.length <= 1) {
    final one = targets.firstOrNull;
    target = one == null ? '' : [if (!said(one.project)) one.project!, if (!said(one.task)) one.task!].join(' › ');
  } else {
    // Même projet répété : il n'est dit qu'une fois, devant ses tâches.
    final parts = <String>[];
    String? last;
    for (final x in targets) {
      final label = x.project == last && (x.task ?? '').isNotEmpty ? x.task! : targetLabel(x);
      if (label.isNotEmpty) parts.add(label);
      last = x.project;
    }
    target = parts.join(' + ');
  }
  return [if (!said(mode)) mode!, if (!said(activity)) activity!, if (target.isNotEmpty) target].join(' · ');
}
