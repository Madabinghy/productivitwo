import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show scoreDay, routineReachedDays, fmtInt;
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart';
import 'package:productivitwo_v1/widgets/objective_moment_card.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/objective_day.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineMinus, routineTodayCount;

/// Segment « Objectifs » d'Aujourd'hui (2026-10) : par objectif en cours, ses
/// engagements de temps au rythme du jour (▶ lance le chrono), ses routines
/// (− / +), ses blocs du programme du jour (tap = source, ▶ = lancer) et la
/// prochaine action de ses projets. Ce qui ne sert aucun objectif reste dans
/// Actions et Routines.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final text3 = dark ? kBText3 : cs.onSurface.withValues(alpha: .55);
    final st = widget.logic.state;
    final now = DateTime.now();
    final days = buildObjectiveDays(
      objectives: _objectives,
      activities: st.activeActivities,
      sessions: st.sessions,
      blocks: widget.blocks,
      projects: widget.logic.currentProjects,
      now: now,
      dayStartMin: widget.logic.dayStartMin,
    );
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()));
    }
    final huntsCard = _huntsCard(cs, dark, text3, now);
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        child: Column(children: [
          if (huntsCard != null) ...[huntsCard, const SizedBox(height: 16)],
          Icon(Icons.flag_outlined, size: 36, color: text3),
          const SizedBox(height: 10),
          Text('Aucun objectif en cours.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('Définis-en un dans Objectifs : ses routines, ses blocs et ses projets apparaîtront ici.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: text3)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ObjectiveMomentCard(
          logic: widget.logic,
          sync: widget.sync,
          objectives: _objectives,
          blocks: widget.blocks,
          onLaunch: widget.onLaunch,
          onOpenSource: widget.onOpenSource,
          onOpenTask: widget.onOpenTask,
          onChainObjective: widget.onChainObjective,
          onChanged: _load,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        child: Text(
          'Ce qui sert tes objectifs en cours, aujourd\u2019hui : le temps engagé au rythme du jour, '
          'les routines à cocher, les blocs du programme et la prochaine action de chaque projet.',
          style: TextStyle(fontSize: 13, height: 1.35, color: text3),
        ),
      ),
      if (huntsCard != null) huntsCard,
      for (final d in days) _objectiveCard(cs, dark, text3, d, now),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Text('Ce qui ne sert aucun objectif reste dans Actions et Routines.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: text3)),
      ),
    ]);
  }


  /// « Badges visés » : chaque chasse avec le levier du jour et, quand il
  /// existe, le geste direct (+1 sur la routine, lancer Enchaîner).
  Widget? _huntsCard(ColorScheme cs, bool dark, Color text3, DateTime now) {
    final bc = widget.badges;
    final deck = bc?.deck;
    if (bc == null || deck == null) return null;
    final views = huntViews(widget.logic.badgeHunts, deck).where((v) => !v.caught).toList();
    if (views.isEmpty) return null;
    final st = widget.logic.state;
    final today = widget.logic.livedToday;
    final reachedByRoutine = {
      for (final a in st.activeActivities)
        if (a.isHabit && a.habitFreq == HabitFreq.daily) a.id: routineReachedDays(a, st.habitHits, dayStartMin: widget.logic.dayStartMin),
    };
    final todayScore = scoreDay(today, activities: st.activeActivities, reachedDaysByRoutine: reachedByRoutine,
        schedule: DailySchedule(date: objectivesDayKey(today), generatedBy: 'app', generatedAt: now, blocks: widget.blocks));
    final todayYmd = objectivesDayKey(today);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: dark ? kBSurface : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBadgeBrassDark.withValues(alpha: .6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.gps_fixed, size: 15, color: kBadgeBrass),
          const SizedBox(width: 8),
          Text('Badges visés', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const Spacer(),
          Text('${views.length} / $kMaxBadgeHunts', style: TextStyle(fontSize: 12.5, color: text3)),
        ]),
        for (final v in views) _huntRow(cs, text3, v, now, todayScore: todayScore, reachedByRoutine: reachedByRoutine, todayYmd: todayYmd),
      ]),
    );
  }

  Widget _huntRow(ColorScheme cs, Color text3, HuntView v, DateTime now, {required dynamic todayScore, required Map<String, Set<String>> reachedByRoutine, required String todayYmd}) {
    final b = v.badge;
    final routineId = b.def.subjectId;
    final todayReached = routineId != null && (reachedByRoutine[routineId]?.contains(todayYmd) ?? false);
    final readingDue = b.def.id == 'releve-fidele' && _objectives.any((o) => isReadingDue(o, now));
    final lever = v.lever(
      todayReached: todayReached,
      readingDue: readingDue,
      todayRoutinesDue: todayScore.routinesDue as int,
      todayRoutinesReached: todayScore.routinesReached as int,
      todayBlocks: todayScore.blocks as int,
      todayBlocksDone: todayScore.blocksDone as int,
    );
    Widget? action;
    if (lever.kind == LeverKind.routine && routineId != null && !todayReached) {
      final a = widget.logic.state.activeActivities.where((x) => x.id == routineId).firstOrNull;
      if (a != null) action = IconButton(visualDensity: VisualDensity.compact, onPressed: () => routinePlus(widget.logic, a), icon: Icon(Icons.add_circle, size: 24, color: cs.primary));
    } else if (lever.kind == LeverKind.chain && widget.onChain != null) {
      action = IconButton(visualDensity: VisualDensity.compact, tooltip: 'Enchaîner', onPressed: widget.onChain, icon: Icon(Icons.playlist_play_rounded, color: cs.primary));
    }
    return InkWell(
      onTap: () => showBadgeSheet(context, b, logic: widget.logic),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          BadgeView(state: b, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b.def.name} · ${fmtInt(v.tierValue)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              Text(v.paceLabel(now), style: TextStyle(fontSize: 12, color: text3)),
              if (lever.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(lever.text, style: TextStyle(fontSize: 12.5, color: todayReached ? kPalierGreen : cs.onSurface.withValues(alpha: .8))),
                ),
            ]),
          ),
          if (action != null) action,
        ]),
      ),
    );
  }

  Widget _objectiveCard(ColorScheme cs, bool dark, Color text3, ObjectiveDay d, DateTime now) {
    final st = widget.logic.state;
    final progress = computeObjectiveProgress(d.objective, st.activities, st.sessions, st.habitHits, now);
    final pct = progress.weekPercent == null ? null : (progress.weekPercent! * 100).round();
    const accent = Color(0xFF00897B);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: dark ? kBSurface : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? kBLine : cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag_rounded, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(child: Text(d.objective.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cs.onSurface))),
          if (pct != null)
            Text('$pct % du rythme', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palierColor(pct))),
        ]),
        if (d.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Rien d’engagé pour aujourd’hui : ajoute une routine, du temps ou un projet à cet objectif.', style: TextStyle(fontSize: 12.5, color: text3)),
          ),
        for (final t in d.times) _timeRow(cs, text3, t),
        for (final a in d.routines) _routineRow(cs, text3, a),
        for (final b in d.blocks) _blockRow(cs, dark, text3, b),
        for (final n in d.nextActions) _nextActionRow(cs, text3, n),
      ]),
    );
  }

  Widget _rowShell({required Widget leading, required Widget body, Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            SizedBox(width: 26, child: leading),
            const SizedBox(width: 8),
            Expanded(child: body),
            if (trailing != null) trailing,
          ]),
        ),
      );

  Widget _timeRow(ColorScheme cs, Color text3, ObjectiveTimeToday t) {
    final running = widget.logic.runningActivity()?.id == t.activityId;
    final ok = t.doneTodayMin >= t.expectedTodayMin;
    return _rowShell(
      leading: Icon(Icons.timer_outlined, size: 18, color: text3),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
        Text(
          '${_min(t.doneTodayMin)} / ${_min(t.expectedTodayMin)} aujourd’hui · ${_min(t.doneWeekMin)} / ${_min(t.weeklyMin)} cette semaine',
          style: TextStyle(fontSize: 12, color: ok ? kPalierGreen : text3, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
      trailing: running
          ? Padding(padding: const EdgeInsets.only(right: 10), child: Text('en cours', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)))
          : IconButton(
              tooltip: 'Lancer le chrono',
              visualDensity: VisualDensity.compact,
              onPressed: t.activity == null ? null : () => widget.logic.start(t.activityId),
              icon: Icon(Icons.play_circle_outline, color: cs.primary),
            ),
    );
  }

  Widget _routineRow(ColorScheme cs, Color text3, Activity a) {
    final count = routineTodayCount(widget.logic, a);
    final target = a.habitFreq == HabitFreq.daily ? ((a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1)) : null;
    final reached = target != null && count >= target;
    return _rowShell(
      leading: Icon(reached ? Icons.check_circle : Icons.loop_rounded, size: 18, color: reached ? kPalierGreen : text3),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
        Text(target == null ? '$count aujourd’hui · cible sur la semaine' : '$count / $target aujourd’hui',
            style: TextStyle(fontSize: 12, color: reached ? kPalierGreen : text3)),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(visualDensity: VisualDensity.compact, onPressed: count > 0 ? () => routineMinus(widget.logic, a) : null, icon: const Icon(Icons.remove_circle_outline, size: 22)),
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => routinePlus(widget.logic, a), icon: Icon(Icons.add_circle, size: 24, color: cs.primary)),
      ]),
    );
  }

  Widget _blockRow(ColorScheme cs, bool dark, Color text3, ScheduleBlock b) {
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    return _rowShell(
      onTap: widget.onOpenSource == null ? null : () => widget.onOpenSource!(b),
      leading: Text(b.startTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: done ? kPalierGreen : text3, fontFeatures: const [FontFeature.tabularFigures()])),
      body: Text(
        b.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: skipped ? text3 : cs.onSurface,
          decoration: done ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: done
          ? const Icon(Icons.check_circle, size: 20, color: kPalierGreen)
          : skipped
              ? Text('sauté', style: TextStyle(fontSize: 12, color: text3))
              : IconButton(
                  tooltip: 'Lancer',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onLaunch == null ? null : () => widget.onLaunch!(b),
                  icon: Icon(Icons.play_circle_outline, color: cs.primary),
                ),
    );
  }

  Widget _nextActionRow(ColorScheme cs, Color text3, ({Project project, ProjectTask task, TaskAction action}) n) {
    return _rowShell(
      onTap: widget.onOpenTask == null ? null : () => widget.onOpenTask!(n.project, n.task),
      leading: Icon(Icons.arrow_forward_rounded, size: 18, color: text3),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: cs.onSurface)),
        Text('${n.project.title} › ${n.task.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: text3)),
      ]),
      trailing: Icon(Icons.chevron_right, color: text3),
    );
  }

  String _min(int m) => m >= 60 ? '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${(m % 60).toString().padLeft(2, '0')}'}' : '$m min';
}

/// Clé du jour vécu, pour les tests et le cache (même forme que les programmes).
String objectivesDayKey(DateTime now) => ymdOf(now);
