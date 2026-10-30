import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedNowMin;
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/utils/objectives_today.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/objective_readings_card.dart' show noteReadingQuick;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlusWithUndo;
import 'package:productivitwo_v1/widgets/status_row.dart' show StateChip;

/// Fiche « Objectifs aujourd'hui » (maquette validée 2026-10-30) : le chiffre du
/// jour (k / n choses faites, barre avec le repère de l'heure), OÙ J'EN SUIS
/// (une ligne par objectif : rythme, reste du jour ; tap = fiche), puis À FAIRE
/// (UNE liste de gestes classés par `buildObjectivesToday`, un bouton par
/// geste, le premier en avant ; l'objectif servi en étiquette). Badges visés
/// et explication sont partis (tuile Badges, ⓘ).
class ObjectivesDayView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<ScheduleBlock> blocks;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onOpenSource;
  final void Function(Project project, ProjectTask task)? onOpenTask;
  final BadgeCenter? badges; // chasse aux badges : carte « Badges visés »
  final VoidCallback? onChain;
  /// « Enchaîner » la file d'UN objectif (routines, blocs, temps en retard,
  /// prochaines actions) depuis la carte Objectif du moment.
  final void Function(StrategicObjective objective)? onChainObjective;
  const ObjectivesDayView({
    super.key,
    required this.logic,
    required this.sync,
    required this.blocks,
    this.onLaunch,
    this.onOpenSource,
    this.onOpenTask,
    this.badges,
    this.onChain,
    this.onChainObjective,
  });

  @override
  State<ObjectivesDayView> createState() => _ObjectivesDayViewState();
}

class _ObjectivesDayViewState extends State<ObjectivesDayView> {
  static List<StrategicObjective>? _cache;
  List<StrategicObjective> _objectives = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final c = _cache;
    if (c != null) {
      _objectives = c;
      _loaded = true;
    }
    widget.logic.addListener(_onLogic);
    widget.badges?.addListener(_onLogic);
    widget.badges?.load();
    _load();
  }

  @override
  void dispose() {
    widget.logic.removeListener(_onLogic);
    widget.badges?.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final all = await widget.sync.fetchStrategicObjectives();
      if (!mounted) return;
      _cache = all;
      setState(() {
        _objectives = all;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final text3 = dark ? kBText3 : cs.onSurface.withValues(alpha: .55);
    final logic = widget.logic;
    final st = logic.state;
    final now = DateTime.now();
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()));
    }
    final days = buildObjectiveDays(
      objectives: _objectives,
      activities: st.activeActivities,
      sessions: st.sessions,
      blocks: widget.blocks,
      projects: logic.currentProjects,
      now: now,
      dayStartMin: logic.dayStartMin,
    );
    final view = buildObjectivesToday(
      days,
      routineProgress: (a) => (logic.activeHabitDone(a), logic.activeHabitTarget(a) <= 0 ? 1 : logic.activeHabitTarget(a)),
      readingDue: (o) => isReadingDue(o, now),
      pctOf: (o) {
        final p = computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent;
        return p == null ? null : (p * 100).round();
      },
      runningActivityId: logic.runningActivity()?.id,
    );
    final header = Row(children: [
      Expanded(child: Text('Objectifs aujourd’hui', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: cs.onSurface))),
      const InfoDot(kRuleObjectivesToday),
    ]);
    if (days.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 28),
        Icon(Icons.flag_outlined, size: 36, color: text3),
        const SizedBox(height: 10),
        Text('Aucun objectif en cours.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text('Définis-en un dans Objectifs : ses routines, ses blocs et ses projets apparaîtront ici.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: text3)),
      ]);
    }
    final total = view.total;
    final allDone = total > 0 && view.remaining == 0;
    final ratio = total == 0 ? 0.0 : view.doneCount / total;
    final dayPart = ((livedNowMin(now, logic.dayStartMin) - 8 * 60) / (14 * 60)).clamp(0.0, 1.0);
    final todo = view.todo;
    final first = todo.where((t) => t.counted).firstOrNull ?? todo.firstOrNull;
    final rest = [for (final t in todo) if (!identical(t, first)) t];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 8),
      // ── 1. Le chiffre du jour ─────────────────────────────────────────────
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('${view.doneCount} / $total',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: allDone ? kPalierGreen : cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Expanded(
          child: Text(allDone ? 'tout est tenu pour aujourd’hui' : 'choses faites · ${view.remaining} reste${view.remaining > 1 ? 'nt' : ''}',
              style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .75))),
        ),
        if (view.lateCount > 0)
          Text('${view.lateCount} en retard', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPalierAmber)),
      ]),
      const SizedBox(height: 8),
      _dayBar(cs, ratio, allDone ? null : dayPart, allDone),
      // ── 2. Où j'en suis ───────────────────────────────────────────────────
      _section(text3, 'OÙ J’EN SUIS'),
      for (final s in view.statuses) _statusLine(cs, text3, s),
      // ── 3. À faire ─────────────────────────────────────────────────────────
      if (first != null) ...[
        _section(text3, allDone ? 'POUR ALLER PLUS LOIN · FACULTATIF' : 'À FAIRE · LE PLUS UTILE D’ABORD'),
        _featured(cs, text3, first),
        for (final t in rest) _todoLine(cs, text3, t),
      ],
      const SizedBox(height: 14),
      Row(children: [
        if (widget.onChain != null && view.remaining > 0)
          TextButton(onPressed: widget.onChain, child: Text('Enchaîner les ${view.remaining} →', style: const TextStyle(fontWeight: FontWeight.w700, color: _accent))),
        const Spacer(),
        if (view.done.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _showDone = !_showDone),
            child: Text('✓ Fait aujourd’hui · ${view.doneCount}${_showDone ? ' ▴' : ' ▾'}', style: TextStyle(color: text3)),
          ),
      ]),
      if (_showDone)
        for (final t in view.done)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.check_rounded, size: 16, color: kPalierGreen),
              const SizedBox(width: 8),
              Expanded(child: Text(t.title, style: TextStyle(fontSize: 13.5, color: text3))),
              Text(t.objective.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: text3)),
            ]),
          ),
    ]);
  }

  static const _accent = Color(0xFF00897B);

  Widget _section(Color text3, String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 10.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: text3)),
      );

  Widget _dayBar(ColorScheme cs, double ratio, double? tick, bool full) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned(
              left: 0,
              right: 0,
              top: 3,
              height: 8,
              child: DecoratedBox(decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)))),
          Positioned(
              left: 0,
              top: 3,
              height: 8,
              width: w * ratio,
              child: DecoratedBox(decoration: BoxDecoration(color: full ? kPalierGreen : _accent, borderRadius: BorderRadius.circular(4)))),
          if (tick != null) Positioned(left: (w * tick - 1).clamp(0.0, w - 2), top: 0, width: 2, height: 14, child: ColoredBox(color: cs.onSurface)),
        ]);
      }),
    );
  }

  Widget _statusLine(ColorScheme cs, Color text3, ObjStatus s) {
    final color = s.heldToday ? kPalierGreen : (s.pct == null ? text3 : palierColor(s.pct!));
    final chip = s.heldToday ? '✓ tenu aujourd’hui' : (s.pct == null ? null : '${s.pct} % du rythme');
    return InkWell(
      onTap: () async {
        final changed = await showObjectiveTrajectorySheet(context, logic: widget.logic, sync: widget.sync, objective: s.objective, projects: widget.logic.currentProjects);
        if (changed) _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(s.objective.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cs.onSurface))),
            if (chip != null) StateChip(chip, color: color, compact: true),
          ]),
          if (s.pct != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: (s.pct! / 100).clamp(0.0, 1.0), minHeight: 5, color: color, backgroundColor: cs.onSurface.withValues(alpha: .1)),
            ),
          ],
          const SizedBox(height: 5),
          Text(s.left.isEmpty ? 'rien ne reste aujourd’hui' : 'reste aujourd’hui : ${s.left.join(' · ')}',
              style: TextStyle(fontSize: 12, color: text3), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  String _tag(ObjTodo t) => '${t.objective.title}${t.objective.isTactical ? ' · rush' : ''}';

  Widget _featured(ColorScheme cs, Color text3, ObjTodo t) {
    final late = _late(t);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: .6)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_tag(t).toUpperCase()}${late ? ' · EN RETARD' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4FD1C5))),
            const SizedBox(height: 3),
            Text(t.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text(t.sub, style: TextStyle(fontSize: 12, color: text3)),
          ]),
        ),
        const SizedBox(width: 10),
        _gesture(cs, t, primary: true),
      ]),
    );
  }

  bool _late(ObjTodo t) {
    final p = computeObjectiveProgress(t.objective, widget.logic.state.activities, widget.logic.state.sessions, widget.logic.state.habitHits, DateTime.now()).weekPercent;
    return p != null && p < .85;
  }

  Widget _todoLine(ColorScheme cs, Color text3, ObjTodo t) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text('${_tag(t)} · ${t.sub}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: text3)),
            ]),
          ),
          const SizedBox(width: 10),
          _gesture(cs, t),
        ]),
      );

  /// UN bouton par geste : Chrono · +1 · Noter · Lancer · Ouvrir.
  Widget _gesture(ColorScheme cs, ObjTodo t, {bool primary = false}) {
    final logic = widget.logic;
    final running = t.activity != null && logic.runningActivity()?.id == t.activity!.id;
    final (String label, VoidCallback? onTap) = switch (t.kind) {
      ObjTodoKind.time => running ? ('■ Arrêter', logic.stopActive) : ('▶ Chrono', t.activity == null ? null : () => logic.start(t.activity!.id)),
      ObjTodoKind.routine => ('+1', t.activity == null ? null : () => routinePlusWithUndo(context, logic, t.activity!)),
      ObjTodoKind.reading => (
          'Noter',
          () => noteReadingQuick(context, sync: widget.sync, objective: t.objective).then((ok) {
                if (ok) _load();
              })
        ),
      ObjTodoKind.block => ('Lancer', t.block == null || widget.onLaunch == null ? null : () => widget.onLaunch!(t.block!)),
      ObjTodoKind.action => ('Ouvrir', t.next == null || widget.onOpenTask == null ? null : () => widget.onOpenTask!(t.next!.project, t.next!.task)),
    };
    if (primary) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, minimumSize: const Size(0, 44), shape: const StadiumBorder()),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );
    }
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
          backgroundColor: _accent.withValues(alpha: .2), foregroundColor: const Color(0xFF4FD1C5), minimumSize: const Size(76, 36), shape: const StadiumBorder()),
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }
}

/// Clé du jour vécu, pour les tests et le cache (même forme que les programmes).
String objectivesDayKey(DateTime now) => ymdOf(now);
