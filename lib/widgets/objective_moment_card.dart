import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/chain.dart' show buildObjectiveChain;
import 'package:productivitwo_v1/utils/coups.dart' show coupLabel;
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/widgets/deep_work_sheet.dart' show showDeepWorkSheet;
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart' show Brick, BrickRow, BrickState;
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show ProgressBricks;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlusWithUndo, routineTodayCount;

const kObjectiveAccent = Color(0xFF00897B);

/// Carte OBJECTIF DU MOMENT (« une carte, une fiche », lot 5 : partagée entre
/// l'onglet Objectifs et la fiche Objectifs d'Aujourd'hui, sur `MomentCard`).
/// UN objectif (`rankObjectiveMoments`), UN geste (`ObjectiveMove`), anneau
/// « n % du rythme », « Fiche » = trajectoire, pilule « 1 / n · suivant › ».
/// Classement du jour (le premier = l'objectif du moment), partagé par la carte
/// et par la liste « une liste, un seul bloc ouvert » de l'onglet Objectifs.
List<ObjectiveMoment> rankedObjectiveMoments(AppLogic logic, List<StrategicObjective> objectives, {List<ScheduleBlock> blocks = const []}) {
  final st = logic.state;
  final now = DateTime.now();
  final days = buildObjectiveDays(
    objectives: objectives,
    activities: st.activeActivities,
    sessions: st.sessions,
    blocks: blocks,
    projects: logic.currentProjects,
    now: now,
    dayStartMin: logic.dayStartMin,
  );
  return rankObjectiveMoments(
    days,
    nowMin: logic.livedNowMinNow,
    now: now,
    routineCount: (a) => routineTodayCount(logic, a),
    weekPercent: (o) => computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent,
    runningActivityId: logic.runningActivity()?.id,
    mode: logic.mode,
  );
}

class ObjectiveMomentCard extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<StrategicObjective> objectives;
  final List<ScheduleBlock> blocks;
  /// Bloc ouvert d'UN objectif donné (liste « un seul bloc ouvert ») : pas de
  /// pilule « suivant », étiquette OBJECTIF DU MOMENT seulement s'il est premier.
  final String? objectiveId;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onOpenSource;
  final void Function(Project project, ProjectTask task)? onOpenTask;
  final void Function(StrategicObjective objective)? onChainObjective;
  /// Après un changement dans la fiche (relevé, statut) : l'appelant recharge.
  final VoidCallback? onChanged;
  const ObjectiveMomentCard({
    super.key,
    required this.logic,
    required this.sync,
    required this.objectives,
    this.blocks = const [],
    this.onLaunch,
    this.onOpenSource,
    this.onOpenTask,
    this.onChainObjective,
    this.onChanged,
    this.objectiveId,
  });

  @override
  State<ObjectiveMomentCard> createState() => _ObjectiveMomentCardState();
}

class _ObjectiveMomentCardState extends State<ObjectiveMomentCard> {
  int _offset = 0;

  Future<void> _fiche(StrategicObjective o) async {
    final changed = await showObjectiveTrajectorySheet(context,
        logic: widget.logic, sync: widget.sync, objective: o, projects: widget.logic.currentProjects);
    if (changed) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.logic.state;
    final now = DateTime.now();
    final ranked = rankedObjectiveMoments(widget.logic, widget.objectives, blocks: widget.blocks);
    if (ranked.isEmpty) return const SizedBox.shrink();
    final fixed = widget.objectiveId == null ? null : ranked.where((x) => x.objective.id == widget.objectiveId).firstOrNull;
    if (widget.objectiveId != null && fixed == null) return const SizedBox.shrink();
    final isMoment = fixed == null || identical(fixed, ranked.first);
    final m = fixed ?? ranked[_offset % ranked.length];
    final o = m.objective;
    final pct = m.weekPercent;
    final pctInt = pct == null ? null : (pct * 100).round();
    final remaining = [...m.remaining, if (m.readingDue) 'relevé à noter'];
    final chainN = widget.onChainObjective == null
        ? 0
        : buildObjectiveChain(m.day,
                projects: widget.logic.currentProjects,
                activities: st.activities,
                hits: st.habitHits,
                now: now,
                dismissed: widget.logic.nowDoneSet(widget.logic.livedYmdNow),
                dayStartMin: widget.logic.dayStartMin)
            .length;
    var move = _move(m);
    // En forme : le geste devient « Bloc de 90 min » (feuille « Sur quoi ? »,
    // présélectionnée sur cet objectif) dès qu'il a de quoi tenir un chrono.
    final deep = widget.logic.mode == DayMode.high &&
        widget.onLaunch != null &&
        m.move.kind != ObjectiveMoveKind.running &&
        m.move.kind != ObjectiveMoveKind.block &&
        (m.day.times.isNotEmpty || m.day.nextActions.isNotEmpty);
    if (deep) {
      move = (
        label: 'Bloc de 90 min · à fond',
        icon: Icons.bolt_rounded,
        onTap: () => showDeepWorkSheet(context,
            logic: widget.logic,
            sync: widget.sync,
            date: widget.logic.livedTodayYmd,
            onLaunch: widget.onLaunch!,
            objectives: widget.objectives,
            preferObjectiveId: o.id),
      );
    }
    // Grammaire de Projets (2026-10) : les morceaux du jour (temps engagés,
    // routines, blocs, relevé) en briques — la même brique que Projets — avec
    // la liste « Aujourd'hui : … » en légende ; la sous-ligne ne dit que l'état.
    final pieces = _pieces(m);
    final stateLine = pctInt == null
        ? 'sans rythme hebdo'
        : pctInt >= 110
            ? 'en avance sur le rythme'
            : pctInt >= 85
                ? 'au rythme'
                : 'en retard sur le rythme';
    final deepPossible = widget.onLaunch != null && (m.day.times.isNotEmpty || m.day.nextActions.isNotEmpty);
    void openDeep() => showDeepWorkSheet(context,
        logic: widget.logic,
        sync: widget.sync,
        date: widget.logic.livedTodayYmd,
        onLaunch: widget.onLaunch!,
        objectives: widget.objectives,
        preferObjectiveId: o.id);
    return MomentCard(
      accent: kObjectiveAccent,
      eyebrow: o.isTactical ? (isMoment ? 'COUP EN COURS' : 'COUP') : (isMoment ? 'OBJECTIF DU MOMENT' : 'OBJECTIF'),
      pill: fixed == null && ranked.length > 1
          ? '${_offset % ranked.length + 1} / ${ranked.length} · suivant ›'
          : (o.isTactical ? coupLabel(o, now) : (pctInt == null ? null : '$pctInt % du rythme')),
      onPill: fixed == null && ranked.length > 1 ? () => setState(() => _offset = (_offset + 1) % ranked.length) : null,
      ring: pct == null ? 0 : pct.clamp(0.0, 1.0),
      ringColor: pctInt == null ? kObjectiveAccent : palierColor(pctInt),
      ringBig: pctInt == null ? '—' : '$pctInt %',
      ringSmall: pctInt == null ? 'SANS RYTHME' : 'DU RYTHME',
      contextIcon: Icons.flag_rounded,
      context_: o.kpiTarget != null && o.kpiTarget!.isNotEmpty ? o.kpiTarget : null,
      title: o.title,
      sub: m.allDone
          ? '✓ Tout est fait pour aujourd’hui'
          : [stateLine, if (m.readingDue) 'relevé dû', if (remaining.isEmpty && !m.readingDue) _hint(m.move)].join(' · '),
      subColor: m.allDone ? kPalierGreen : (pctInt != null && pctInt < 60 ? palierColor(pctInt) : null),
      visual: pieces.isEmpty
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ProgressBricks(row: BrickRow(bricks: pieces, expected: 0), height: 12, accent: kObjectiveAccent),
              MomentLegend(remaining.isEmpty ? 'Aujourd’hui : tout est fait' : 'Aujourd’hui : ${remaining.join(' · ')}',
                  right: '${pieces.where((b) => b.state == BrickState.done).length} / ${pieces.length}'),
            ]),
      primaryLabel: move.label,
      primaryIcon: move.icon,
      primaryOutlined: m.move.kind == ObjectiveMoveKind.running,
      onPrimary: move.onTap,
      ficheLabel: 'Détail',
      onFiche: () => _fiche(o),
      chainLabel: chainN > 0 ? 'Enchaîner · $chainN' : null,
      onChain: chainN > 0 ? () => widget.onChainObjective!(o) : null,
      moreTitle: o.title,
      moreActions: [
        if (deepPossible && !deep) MomentAction('Bloc de 90 min', icon: Icons.bolt_rounded, hint: 'deep work sur cet objectif', onTap: openDeep),
        if (m.readingDue && m.move.kind != ObjectiveMoveKind.reading)
          MomentAction('Noter un relevé', icon: Icons.edit_rounded, onTap: () => _fiche(o)),
        for (final t in m.day.times)
          if (t.activity != null && !(m.move.kind == ObjectiveMoveKind.time && m.move.time?.activityId == t.activityId))
            MomentAction('Chrono · ${t.name}',
                icon: Icons.play_arrow_rounded,
                hint: '${fmtMin(t.doneTodayMin)} / ${fmtMin(t.expectedTodayMin)} aujourd’hui',
                onTap: () => widget.logic.start(t.activityId)),
        for (final a in m.day.routines)
          if (!(m.move.kind == ObjectiveMoveKind.routine && m.move.routine?.id == a.id))
            MomentAction('+1 · ${a.name}', icon: Icons.add, onTap: () => routinePlusWithUndo(context, widget.logic, a)),
        for (final n in m.day.nextActions.take(3))
          if (widget.onOpenTask != null && !(m.move.kind == ObjectiveMoveKind.nextAction && m.move.next?.action.id == n.action.id))
            MomentAction(n.action.title, icon: Icons.arrow_forward_rounded, hint: n.project.title, onTap: () => widget.onOpenTask!(n.project, n.task)),
      ],
    );
  }

  /// Les morceaux du jour en briques : chaque temps engagé (fait / attendu
  /// aujourd'hui), chaque routine (compte / cible), chaque bloc à faire ou
  /// fait, le relevé s'il est dû.
  List<Brick> _pieces(ObjectiveMoment m) {
    final d = m.day;
    final out = <Brick>[];
    Brick brick(String id, String title, double fill) => Brick(
        id: id, title: title, state: fill >= 1 ? BrickState.done : (fill > 0 ? BrickState.started : BrickState.todo), fill: fill.clamp(0, 1));
    for (final t in d.times) {
      out.add(brick('t-${t.activityId}', t.name, t.expectedTodayMin <= 0 ? 1 : t.doneTodayMin / t.expectedTodayMin));
    }
    for (final a in d.routines) {
      final target = a.habitFreq == HabitFreq.daily ? ((a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1)) : 1;
      out.add(brick('r-${a.id}', a.name, routineTodayCount(widget.logic, a) / target));
    }
    for (final b in d.blocks) {
      if (b.status == 'skipped' || b.status == 'deleted') continue;
      out.add(brick('b-${b.id}', b.title, b.status == 'done' ? 1 : 0));
    }
    if (m.readingDue) out.add(brick('reading', 'Relevé', 0));
    return out;
  }

  String _minLeft(ObjectiveTimeToday t) {
    final left = t.expectedTodayMin - t.doneTodayMin;
    return left > 0 ? fmtMin(left) : t.name;
  }

  String _hint(ObjectiveMove mv) => switch (mv.kind) {
        ObjectiveMoveKind.running => 'Chrono en cours · ${fmtMin(mv.time!.doneTodayMin)} aujourd’hui',
        ObjectiveMoveKind.nextAction => '${mv.next!.project.title} › ${mv.next!.task.title}',
        ObjectiveMoveKind.reading => 'Relevé à noter',
        _ => 'Rien d’engagé pour aujourd’hui',
      };

  ({String label, IconData? icon, VoidCallback? onTap}) _move(ObjectiveMoment m) {
    final mv = m.move;
    switch (mv.kind) {
      case ObjectiveMoveKind.running:
        return (label: 'Arrêter', icon: Icons.stop_rounded, onTap: () => widget.logic.stopActive());
      case ObjectiveMoveKind.block:
        final b = mv.block!;
        final launch = widget.onLaunch ?? widget.onOpenSource;
        return (label: 'Lancer · ${b.startTime}', icon: Icons.play_arrow_rounded, onTap: launch == null ? null : () => launch(b));
      case ObjectiveMoveKind.time:
        final t = mv.time!;
        return (label: 'Chrono · ${_minLeft(t)}', icon: Icons.play_arrow_rounded, onTap: t.activity == null ? null : () => widget.logic.start(t.activityId));
      case ObjectiveMoveKind.routine:
        final a = mv.routine!;
        return (label: '+1 · ${a.name}', icon: null, onTap: () => routinePlusWithUndo(context, widget.logic, a));
      case ObjectiveMoveKind.reading:
        return (label: 'Noter un relevé', icon: Icons.edit_rounded, onTap: () => _fiche(m.objective));
      case ObjectiveMoveKind.nextAction:
        final n = mv.next!;
        return (label: 'Ouvrir l’action', icon: Icons.arrow_forward_rounded, onTap: widget.onOpenTask == null ? null : () => widget.onOpenTask!(n.project, n.task));
      case ObjectiveMoveKind.none:
        return (label: m.allDone ? 'Rien de plus aujourd’hui' : 'Rien d’engagé aujourd’hui', icon: null, onTap: null);
    }
  }
}
