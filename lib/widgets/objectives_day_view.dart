import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/badge_hunt.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show scoreDay, routineReachedDays, fmtInt;
import 'package:productivitwo_v1/utils/chain.dart' show buildObjectiveChain;
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeSheet;
import 'package:productivitwo_v1/widgets/badge_painter.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/ring_painter.dart';
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
  int _offset = 0; // « Suivant » sur la carte Objectif du moment

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
    final ranked = rankObjectiveMoments(
      days,
      nowMin: widget.logic.livedNowMinNow,
      now: now,
      routineCount: (a) => routineTodayCount(widget.logic, a),
      weekPercent: (o) => computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now).weekPercent,
      runningActivityId: widget.logic.runningActivity()?.id,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _momentCard(NowPalette.of(context), ranked),
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


  // ── Objectif du moment ──────────────────────────────────────────────────────

  static const _accent = Color(0xFF00897B);

  Widget _momentCard(NowPalette pal, List<ObjectiveMoment> ranked) {
    final m = ranked[_offset % ranked.length];
    final o = m.objective;
    final pct = m.weekPercent;
    final pctInt = pct == null ? null : (pct * 100).round();
    final ring = pct == null ? 0.0 : pct.clamp(0.0, 1.0);
    final ringColor = pctInt == null ? _accent : palierColor(pctInt);
    final remaining = [...m.remaining, if (m.readingDue) 'relevé à noter'];
    final st = widget.logic.state;
    final chainN = widget.onChainObjective == null
        ? 0
        : buildObjectiveChain(m.day,
                projects: widget.logic.currentProjects,
                activities: st.activities,
                hits: st.habitHits,
                now: DateTime.now(),
                dismissed: widget.logic.nowDoneSet(widget.logic.livedYmdNow),
                dayStartMin: widget.logic.dayStartMin)
            .length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('OBJECTIF DU MOMENT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
          ),
          if (ranked.length > 1)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _offset = (_offset + 1) % ranked.length),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: _accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                child: Text('${_offset % ranked.length + 1} / ${ranked.length} · suivant ›',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: _accent)),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: const Size(96, 96),
                painter: RingPainter(progress: ring, color: ringColor, stroke: 9, trackColor: pal.track, cap: StrokeCap.round),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(pctInt == null ? '—' : '$pctInt %',
                    style: TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, fontFeatures: const [FontFeature.tabularFigures()])),
                Text(pctInt == null ? 'SANS RYTHME' : 'DU RYTHME', style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: pal.text3)),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.flag_rounded, size: 24, color: _accent)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(o.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.15, color: pal.text)),
                ),
              ]),
              const SizedBox(height: 6),
              if (m.allDone)
                Text('✓ Tout est fait pour aujourd’hui', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPalierGreen))
              else if (remaining.isEmpty)
                Text(_moveHint(m.move), style: TextStyle(fontSize: 12.5, color: pal.text3))
              else
                Text('Reste aujourd’hui : ${remaining.join(' · ')}',
                    style: TextStyle(fontSize: 12.5, color: pal.text3, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _moveButton(pal, m)),
          const SizedBox(width: 8),
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: () async {
                final changed = await showObjectiveTrajectorySheet(context,
                    logic: widget.logic, sync: widget.sync, objective: o, projects: widget.logic.currentProjects);
                if (changed) _load();
              },
              style: OutlinedButton.styleFrom(
                  foregroundColor: pal.text2,
                  side: BorderSide(color: pal.track),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              child: const Text('Fiche'),
            ),
          ),
        ]),
        if (chainN > 0) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => widget.onChainObjective!(o),
            style: TextButton.styleFrom(foregroundColor: _accent, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            icon: const Icon(Icons.playlist_play_rounded, size: 22),
            label: Text('Enchaîner · $chainN ${chainN > 1 ? 'choses' : 'chose'} pour cet objectif'),
          ),
        ],
      ]),
    );
  }

  String _moveHint(ObjectiveMove mv) => switch (mv.kind) {
        ObjectiveMoveKind.running => 'Chrono en cours · ${_min(mv.time!.doneTodayMin)} aujourd’hui',
        ObjectiveMoveKind.nextAction => '${mv.next!.project.title} › ${mv.next!.task.title}',
        ObjectiveMoveKind.reading => 'Relevé à noter',
        _ => 'Rien d’engagé pour aujourd’hui',
      };

  /// Le geste de la carte : un seul bouton, selon ce que la journée demande.
  Widget _moveButton(NowPalette pal, ObjectiveMoment m) {
    final mv = m.move;
    Widget filled(String label, VoidCallback? onTap, {IconData? icon}) => SizedBox(
          height: 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            onPressed: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 6)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        );
    switch (mv.kind) {
      case ObjectiveMoveKind.running:
        return SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () => widget.logic.stopActive(),
            style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: .5)),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            icon: const Icon(Icons.stop_rounded, size: 22),
            label: Text('Arrêter · ${mv.time!.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
      case ObjectiveMoveKind.block:
        final b = mv.block!;
        final launch = widget.onLaunch ?? widget.onOpenSource;
        return filled('${b.startTime} · ${b.title}', launch == null ? null : () => launch(b), icon: Icons.play_arrow_rounded);
      case ObjectiveMoveKind.time:
        final t = mv.time!;
        return filled('Chrono · ${t.name}', t.activity == null ? null : () => widget.logic.start(t.activityId), icon: Icons.play_arrow_rounded);
      case ObjectiveMoveKind.routine:
        final a = mv.routine!;
        return filled('+1 · ${a.name}', () => routinePlus(widget.logic, a));
      case ObjectiveMoveKind.reading:
        return filled('Noter un relevé', () async {
          final changed = await showObjectiveTrajectorySheet(context,
              logic: widget.logic, sync: widget.sync, objective: m.objective, projects: widget.logic.currentProjects);
          if (changed) _load();
        }, icon: Icons.edit_rounded);
      case ObjectiveMoveKind.nextAction:
        final n = mv.next!;
        return filled(n.action.title, widget.onOpenTask == null ? null : () => widget.onOpenTask!(n.project, n.task), icon: Icons.arrow_forward_rounded);
      case ObjectiveMoveKind.none:
        return SizedBox(
          height: 54,
          child: Center(
            child: Text(m.allDone ? 'Rien de plus à faire aujourd’hui' : 'Rien d’engagé pour aujourd’hui',
                style: TextStyle(fontSize: 13, color: pal.text3)),
          ),
        );
    }
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
