import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/chain.dart' show buildObjectiveChain;
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineTodayCount;

const kObjectiveAccent = Color(0xFF00897B);

/// Carte OBJECTIF DU MOMENT (« une carte, une fiche », lot 5 : partagée entre
/// l'onglet Objectifs et la fiche Objectifs d'Aujourd'hui, sur `MomentCard`).
/// UN objectif (`rankObjectiveMoments`), UN geste (`ObjectiveMove`), anneau
/// « n % du rythme », « Fiche » = trajectoire, pilule « 1 / n · suivant › ».
class ObjectiveMomentCard extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<StrategicObjective> objectives;
  final List<ScheduleBlock> blocks;
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
    final days = buildObjectiveDays(
      objectives: widget.objectives,
      activities: st.activeActivities,
      sessions: st.sessions,
      blocks: widget.blocks,
      projects: widget.logic.currentProjects,
      now: now,
      dayStartMin: widget.logic.dayStartMin,
    );
    final ranked = rankObjectiveMoments(
      days,
      nowMin: widget.logic.livedNowMinNow,
      now: now,
      routineCount: (a) => routineTodayCount(widget.logic, a),
      weekPercent: (o) => computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent,
      runningActivityId: widget.logic.runningActivity()?.id,
    );
    if (ranked.isEmpty) return const SizedBox.shrink();
    final m = ranked[_offset % ranked.length];
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
    final move = _move(m);
    return MomentCard(
      accent: kObjectiveAccent,
      eyebrow: 'OBJECTIF DU MOMENT',
      pill: ranked.length > 1 ? '${_offset % ranked.length + 1} / ${ranked.length} · suivant ›' : null,
      onPill: ranked.length > 1 ? () => setState(() => _offset = (_offset + 1) % ranked.length) : null,
      ring: pct == null ? 0 : pct.clamp(0.0, 1.0),
      ringColor: pctInt == null ? kObjectiveAccent : palierColor(pctInt),
      ringBig: pctInt == null ? '—' : '$pctInt %',
      ringSmall: pctInt == null ? 'SANS RYTHME' : 'DU RYTHME',
      contextIcon: Icons.flag_rounded,
      context_: o.kpiTarget != null && o.kpiTarget!.isNotEmpty ? o.kpiTarget : null,
      title: o.title,
      sub: m.allDone
          ? '✓ Tout est fait pour aujourd’hui'
          : remaining.isEmpty
              ? _hint(m.move)
              : 'Reste aujourd’hui : ${remaining.join(' · ')}',
      subColor: m.allDone ? kPalierGreen : null,
      primaryLabel: move.label,
      primaryIcon: move.icon,
      primaryOutlined: m.move.kind == ObjectiveMoveKind.running,
      onPrimary: move.onTap,
      onFiche: () => _fiche(o),
      chainLabel: chainN > 0 ? 'Enchaîner · $chainN ${chainN > 1 ? 'choses' : 'chose'} pour cet objectif' : null,
      onChain: chainN > 0 ? () => widget.onChainObjective!(o) : null,
    );
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
        return (label: 'Arrêter · ${mv.time!.name}', icon: Icons.stop_rounded, onTap: () => widget.logic.stopActive());
      case ObjectiveMoveKind.block:
        final b = mv.block!;
        final launch = widget.onLaunch ?? widget.onOpenSource;
        return (label: '${b.startTime} · ${b.title}', icon: Icons.play_arrow_rounded, onTap: launch == null ? null : () => launch(b));
      case ObjectiveMoveKind.time:
        final t = mv.time!;
        return (label: 'Chrono · ${t.name}', icon: Icons.play_arrow_rounded, onTap: t.activity == null ? null : () => widget.logic.start(t.activityId));
      case ObjectiveMoveKind.routine:
        final a = mv.routine!;
        return (label: '+1 · ${a.name}', icon: null, onTap: () => routinePlus(widget.logic, a));
      case ObjectiveMoveKind.reading:
        return (label: 'Noter un relevé', icon: Icons.edit_rounded, onTap: () => _fiche(m.objective));
      case ObjectiveMoveKind.nextAction:
        final n = mv.next!;
        return (label: n.action.title, icon: Icons.arrow_forward_rounded, onTap: widget.onOpenTask == null ? null : () => widget.onOpenTask!(n.project, n.task));
      case ObjectiveMoveKind.none:
        return (label: m.allDone ? 'Rien de plus aujourd’hui' : 'Rien d’engagé aujourd’hui', icon: null, onTap: null);
    }
  }
}
