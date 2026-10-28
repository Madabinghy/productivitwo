import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isOverdueAction;
import 'package:productivitwo_v1/utils/checklist_logic.dart' show nextChecklistItem;
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/status_row.dart' show StateChip;

/// Mur des projets, lot 2 (2026-10) : une TÂCHE dépliée sur place. En tête
/// la tâche (titre · k / n actions · état) et sa rangée de briques (une par
/// action) ; tap = déplie ses actions (points des étapes, état) ; tap sur une
/// action à étapes = déplie ses étapes cochables ; sans étape = sa fiche.
/// Trois profondeurs dans un seul écran, les fiches restent pour AGIR.
class WallTask extends StatefulWidget {
  final ProjectTask task;
  final DateTime today;
  final Set<String> runningTaskIds;
  final Set<String> runningActionIds;
  final bool initiallyExpanded;
  final bool isTarget;
  final VoidCallback onOpenFiche;
  final void Function(TaskAction a) onOpenAction;
  final Future<void> Function() onToggleDone;
  final Future<void> Function(TaskAction a, bool done) onActionDone;
  final Future<void> Function(TaskAction a, ChecklistItem c, bool done) onStep;
  /// Jalon d'une séance : ouvre l'écran « séance en cours ».
  final VoidCallback? onLaunchSession;

  const WallTask({
    super.key,
    required this.task,
    required this.today,
    this.runningTaskIds = const {},
    this.runningActionIds = const {},
    this.initiallyExpanded = false,
    this.isTarget = false,
    required this.onOpenFiche,
    required this.onOpenAction,
    required this.onToggleDone,
    required this.onActionDone,
    required this.onStep,
    this.onLaunchSession,
  });

  @override
  State<WallTask> createState() => _WallTaskState();
}

class _WallTaskState extends State<WallTask> {
  late bool _open = widget.initiallyExpanded;
  final _openActions = <String>{};

  ProjectTask get t => widget.task;

  String _chip(Brick b) {
    switch (b.state) {
      case BrickState.done:
        return 'faite';
      case BrickState.running:
        return 'chrono';
      case BrickState.late:
        final end = t.endDate;
        final days = end == null ? 0 : DateTime(widget.today.year, widget.today.month, widget.today.day).difference(DateTime(end.year, end.month, end.day)).inDays;
        return days > 0 ? 'en retard · $days j' : 'en retard';
      case BrickState.started:
        return 'en cours';
      case BrickState.upcoming:
        return 'à venir';
      case BrickState.todo:
        return 'à faire';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text3 = cs.onSurface.withValues(alpha: .55);
    final brick = taskBrick(t, widget.today, runningTaskIds: widget.runningTaskIds, runningActionIds: widget.runningActionIds);
    final row = taskBricks(t, widget.today, runningActionIds: widget.runningActionIds);
    final done = t.status == 'done';
    final color = brickColor(brick.state);
    final chipColor = switch (brick.state) {
      BrickState.done => kPalierGreen,
      BrickState.todo || BrickState.upcoming => kPalierMuted,
      _ => color,
    };
    final hasActions = t.actions.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isTarget || _open ? kPalierGreen.withValues(alpha: .4) : cs.outlineVariant.withValues(alpha: .35),
          width: widget.isTarget ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasActions ? () => setState(() => _open = !_open) : widget.onOpenFiche,
          onLongPress: widget.onOpenFiche,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                InkResponse(
                  radius: 18,
                  onTap: widget.onToggleDone,
                  child: Icon(
                    t.isMilestone
                        ? (done ? Icons.flag_rounded : Icons.flag_outlined)
                        : (done ? Icons.check_circle_rounded : Icons.radio_button_unchecked),
                    size: 20,
                    color: done ? kPalierGreen : cs.onSurface.withValues(alpha: .35),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: done ? text3 : cs.onSurface,
                          decoration: done ? TextDecoration.lineThrough : null)),
                ),
                const SizedBox(width: 6),
                if (hasActions)
                  Text('${brick.done} / ${brick.total}',
                      style: TextStyle(fontSize: 11, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 6),
                StateChip(_chip(brick), color: chipColor),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Fiche de la tâche',
                  onPressed: widget.onOpenFiche,
                  icon: Icon(Icons.open_in_new_rounded, size: 15, color: text3),
                ),
              ]),
              if (hasActions)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 4, 0),
                  child: ProgressBricks(row: row, height: 8, gap: 2),
                ),
              if (widget.onLaunchSession != null && !done)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 4, 0),
                  child: FilledButton.tonalIcon(
                    onPressed: widget.onLaunchSession,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Séance en cours'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
            ]),
          ),
        ),
        if (_open && hasActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final a in t.actions) _action(cs, a),
            ]),
          ),
      ]),
    );
  }

  Widget _action(ColorScheme cs, TaskAction a) {
    final text3 = cs.onSurface.withValues(alpha: .55);
    final b = actionBrick(a, t, widget.today, runningActionIds: widget.runningActionIds);
    final color = brickColor(b.state);
    final open = _openActions.contains(a.id);
    final hasSteps = a.checklist.isNotEmpty;
    final late = isOverdueAction(a, t, widget.today);
    final String meta;
    if (hasSteps) {
      meta = '${b.done} / ${b.total} étapes';
    } else if (a.estimatedMin != null) {
      meta = '≈ ${a.estimatedMin} min';
    } else {
      meta = '';
    }
    final chipColor = switch (b.state) {
      BrickState.done => kPalierGreen,
      BrickState.todo || BrickState.upcoming => kPalierMuted,
      _ => color,
    };
    final chip = switch (b.state) {
      BrickState.done => null,
      BrickState.running => 'chrono',
      BrickState.late => 'en retard',
      BrickState.started => 'en cours',
      BrickState.upcoming => 'à venir',
      BrickState.todo => late ? 'en retard' : null,
    };
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: cs.onSurface.withValues(alpha: .10), width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: hasSteps ? () => setState(() => open ? _openActions.remove(a.id) : _openActions.add(a.id)) : () => widget.onOpenAction(a),
          onLongPress: () => widget.onOpenAction(a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(children: [
              InkResponse(
                radius: 16,
                onTap: () => widget.onActionDone(a, !a.done),
                child: Icon(a.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    size: 18, color: a.done ? kPalierGreen : cs.onSurface.withValues(alpha: .35)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: a.done ? text3 : cs.onSurface,
                          decoration: a.done ? TextDecoration.lineThrough : null)),
                  if (hasSteps || meta.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(children: [
                        if (hasSteps) ...[
                          StepDots(done: b.done, total: b.total, allDone: a.done, size: 8),
                          const SizedBox(width: 8),
                        ],
                        Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: text3))),
                      ]),
                    ),
                ]),
              ),
              if (chip != null) ...[const SizedBox(width: 6), StateChip(chip, color: chipColor)],
              if (hasSteps) Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: text3),
            ]),
          ),
        ),
        if (open && hasSteps)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 0, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in a.checklist) _step(cs, a, c, identical(nextChecklistItem(a), c)),
            ]),
          ),
      ]),
    );
  }

  Widget _step(ColorScheme cs, TaskAction a, ChecklistItem c, bool current) {
    final text3 = cs.onSurface.withValues(alpha: .55);
    return InkWell(
      onTap: () => widget.onStep(a, c, !c.done),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: c.done ? kPalierGreen : cs.onSurface.withValues(alpha: .10),
              border: current ? Border.all(color: kBrickRunning, width: 2) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: c.done ? text3 : cs.onSurface,
                    decoration: c.done ? TextDecoration.lineThrough : null)),
          ),
        ]),
      ),
    );
  }
}
