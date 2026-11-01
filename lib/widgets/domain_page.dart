import 'dart:math' as math;
import 'package:productivitwo_v1/utils/sport_stats.dart' show resolveSportPick;
import 'package:productivitwo_v1/widgets/sport_sheet.dart' show showSportSheet, kSportAccent;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineSeries;
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, rootProjectOf;
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;
import 'package:productivitwo_v1/utils/project_moment.dart' show projectPlan;
import 'package:productivitwo_v1/widgets/domain_session_screen.dart' show DomainSessionScreen;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/project_fiche_sheet.dart' show showProjectFiche;
import 'package:productivitwo_v1/widgets/project_sheet.dart' show showProjectSheet;
import 'package:productivitwo_v1/widgets/rest_sheet.dart' show liftRest, showRestSheet;
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart' show showRoutineSheet;
import 'package:productivitwo_v1/utils/routines_today.dart' show todayMark;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus, routineMinus, routineTodayCount;
import 'package:productivitwo_v1/widgets/status_row.dart';

/// Page d'un domaine (tap sur une ligne de Domaines ; `domain` null = toutes
/// les activités ou routines), refonte 2026-10-30 « le domaine vu par toute
/// l'app » : en-tête = intention + minimum vital (⚙ = intention, veille, nom /
/// couleur), puis une liste par type — OBJECTIFS · ROUTINES · ACTIVITÉS ·
/// PROJETS —, l'état en chip sur la ligne, tap = la fiche. Plus de segment
/// Temps / Routines ni d'en-tête chiffré (c'est la ligne de l'onglet).
/// Renvoie `true` quand un chrono a été lancé (la racine bascule sur Aujourd'hui).
Future<bool?> showDomainPage(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  Domain? domain,
  String focus = 'time',
  required Future<void> Function({String? domainId, required bool isHabit}) onCreate,
  required Future<bool> Function(Activity a) onOpenActivity,
  void Function(Activity a, int minutes)? onLaunchTimed,
  void Function(ScheduleBlock block)? onLaunchBlock,
  List<Project> projects = const [],
  VoidCallback? onManageDomains,
  void Function(Activity activity, Project project, ProjectTask task)? onStartTimer,
}) async {
  // Préchargement (2026-10-30) : objectifs avant l'ouverture, déroulés des
  // activités du domaine en arrière-plan — plus de section qui arrive après coup.
  if (domain != null) await FicheCache.objectivesFast(sync);
  for (final a in logic.state.activities) {
    if (!a.deleted && !a.isHabit && (domain == null || a.domainId == domain.id) && !FicheCache.templates.containsKey(a.id)) {
      FicheCache.loadTemplates(sync, a.id).ignore();
    }
  }
  if (!context.mounted) return null;
  return showFiche<bool>(
    context,
    builder: (ctx, scroll) => _DomainPage(
      logic: logic,
      sync: sync,
      domain: domain,
      focus: focus,
      scroll: scroll,
      onCreate: onCreate,
      onOpenActivity: onOpenActivity,
      onLaunchTimed: onLaunchTimed,
      onLaunchBlock: onLaunchBlock,
      projects: projects,
      onManageDomains: onManageDomains,
      onStartTimer: onStartTimer,
    ),
  );
}

class _DomainPage extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Domain? domain;
  final String focus;
  final ScrollController scroll;
  final Future<void> Function({String? domainId, required bool isHabit}) onCreate;
  final Future<bool> Function(Activity a) onOpenActivity;
  final void Function(Activity a, int minutes)? onLaunchTimed;
  final void Function(ScheduleBlock block)? onLaunchBlock;
  final List<Project> projects;
  final VoidCallback? onManageDomains;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;
  const _DomainPage({
    required this.logic,
    required this.sync,
    required this.domain,
    required this.focus,
    required this.scroll,
    required this.onCreate,
    required this.onOpenActivity,
    this.onLaunchTimed,
    this.onLaunchBlock,
    this.projects = const [],
    this.onManageDomains,
    this.onStartTimer,
  });

  @override
  State<_DomainPage> createState() => _DomainPageState();
}

/// Une activité-temps lue sur la fenêtre de budget.
class _TimeRow {
  final Activity a;
  final int goalMinDay;
  final int doneMin; // dans la fenêtre
  final int expectedMin; // minimum × jour de la fenêtre
  final int totalMin; // minimum × fenêtre
  final int avg7; // minutes / jour sur 7 jours glissants
  final bool paused;
  const _TimeRow(this.a, {required this.goalMinDay, required this.doneMin, required this.expectedMin, required this.totalMin, required this.avg7, required this.paused});
  bool get hasGoal => goalMinDay > 0;
  int get pctInt => !hasGoal ? 100 : (expectedMin <= 0 ? 100 : (doneMin / expectedMin * 100).round());
  /// « Au rythme » dès 95 % de l'attendu (même tolérance que l'ancienne page).
  bool get onTrack => !hasGoal || doneMin >= expectedMin * .95;
}

class _DomainPageState extends State<_DomainPage> {
  bool _showPaused = false;
  List<StrategicObjective>? _objectives = FicheCache.objectives;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    if (widget.domain != null) _loadObjectives();
  }

  Future<void> _loadObjectives() async {
    try {
      final all = await FicheCache.loadObjectives(widget.sync);
      if (mounted && !FicheCache.sameObjectives(_objectives, all)) setState(() => _objectives = all);
    } catch (_) {}
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  // ── Lectures ────────────────────────────────────────────────────────────────

  List<Activity> _acts(bool habits) => logic.state.activities
      .where((a) => !a.deleted && a.isHabit == habits && (widget.domain == null || a.domainId == widget.domain!.id))
      .toList();

  List<_TimeRow> _timeRows(DateTime now) {
    final days = logic.budgetWindowDays;
    final start = budgetWindowStart(now, days);
    final idx = budgetDayIndex(now, days);
    final byAct = minutesByActivity(logic.state.sessions, start, now);
    final out = <_TimeRow>[];
    for (final a in _acts(false)) {
      final s7 = logic.timeSliding(a.id, 7);
      out.add(_TimeRow(
        a,
        goalMinDay: a.goalMin,
        doneMin: byAct[a.id] ?? 0,
        expectedMin: a.goalMin * idx,
        totalMin: a.goalMin * days,
        avg7: (s7.doneMin / 7).round(),
        paused: logic.isActivitySnoozed(a.id, now),
      ));
    }
    return out;
  }

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _start(Activity a) {
    logic.start(a.id);
    Navigator.of(context).pop(true);
  }

  Future<void> _rowMenu(Activity a, DateTime now) async {
    final paused = logic.isActivitySnoozed(a.id, now);
    final running = logic.runningActivity()?.id == a.id;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ),
          if (paused)
            ListTile(leading: const Icon(Icons.play_circle_outline), title: const Text('Reprendre'), onTap: () => Navigator.pop(c, 'resume'))
          else ...[
            ListTile(
                leading: const Icon(Icons.redo_rounded),
                title: const Text('Reporter à demain'),
                subtitle: running ? const Text('Impossible : le chrono tourne dessus') : null,
                enabled: !running,
                onTap: () => Navigator.pop(c, 'tomorrow')),
            ListTile(leading: const Icon(Icons.pause_circle_outline), title: const Text('Mettre en pause jusqu\'à…'), onTap: () => Navigator.pop(c, 'pause')),
          ],
          ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: Text('Supprimer', style: TextStyle(color: Theme.of(c).colorScheme.error)),
              onTap: () => Navigator.pop(c, 'delete')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'resume':
        logic.clearSnooze(a.id);
      case 'tomorrow':
        logic.snoozeActivityUntil(a.id, DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'pause':
        final d = await showDatePicker(
            context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 365)), locale: const Locale('fr', 'FR'));
        if (d != null) logic.snoozeActivityUntil(a.id, DateTime(d.year, d.month, d.day, 23, 59, 59));
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Supprimer « ${a.name} » ?'),
            content: Text(a.isHabit ? 'Cette routine sera supprimée et retirée des plans.' : 'Cette activité sera supprimée et retirée des plans.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
            ],
          ),
        );
        if (ok == true) logic.deleteActivityCascade(a.id);
    }
    if (mounted) setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final d = widget.domain;
    final habitsFirst = d != null || widget.focus == 'habit';
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        _header(now),
        if (d != null && _hasSport(d))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showSportSheet(context, logic: widget.logic, sync: widget.sync),
              icon: const Icon(Icons.directions_run_rounded, size: 18, color: kSportAccent),
              label: const Text('Voir le suivi du sport'),
            ),
          ),
        if (d != null) ..._objectiveBody(now, d),
        if (habitsFirst) ...[..._habitBody(now, d), ..._timeBody(now, d)] else ...[..._timeBody(now, d), ..._habitBody(now, d)],
        if (d != null) ..._projectBody(now, d),
      ],
    );
  }

  bool _hasSport(Domain d) {
    final st = widget.logic.state;
    final pick = resolveSportPick(st.activities, st.domains, widget.logic.sportOverrides);
    return pick.kinds.keys.any((id) => pick.byId[id]?.domainId == d.id);
  }

  Widget _header(DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.domain;
    final st = logic.state;
    if (d == null) {
      final n = _acts(widget.focus == 'habit').length;
      return FicheHeader(
        title: widget.focus == 'habit' ? 'Toutes les routines' : 'Toutes les activités',
        kpi: '$n ${widget.focus == 'habit' ? 'routine' : 'activité'}${n > 1 ? 's' : ''} · tous domaines',
      );
    }
    final rows = domainWeeks(
        domains: [d], activities: st.activeActivities, sessions: st.sessions, hits: st.habitHits, now: now, rest: logic.restDomains, windowDays: logic.budgetWindowDays);
    final r = rows.single;
    final color = domainColor(d.id, st.activeDomains) ?? cs.primary;
    final String? chip;
    final Color chipColor;
    if (r.resting) {
      chip = 'en veille';
      chipColor = kPalierMuted;
    } else if (!r.hasGoal) {
      chip = null;
      chipColor = kPalierMuted;
    } else {
      chip = r.pctInt >= 85 ? 'au rythme' : (r.pctInt >= 60 ? 'à surveiller' : 'à rattraper');
      chipColor = palierColor(r.pctInt);
    }
    final restUntil = r.restUntil == null ? null : DateTime.tryParse(r.restUntil!);
    final win = r.windowDays == 14 ? 'sur 14 j' : 'cette semaine';
    final pills = <String>[
      if (r.hasGoal) 'Minimum vital · ${fmtMin(r.goalMinDay)} / j',
      if (r.hasGoal) '${fmtMin(r.doneMin)} / ${fmtMin(r.weekMin)} $win' else if (r.doneMin > 0) '${fmtMin(r.doneMin)} $win',
      if (r.resting && restUntil != null) 'en veille jusqu\'au ${dayMonthFr(restUntil)}',
    ];
    final intention = d.intention?.trim() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: FicheHeader(
            leading: Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            title: d.name,
            chip: chip,
            chipColor: chipColor,
          ),
        ),
        IconButton(
          tooltip: 'Réglages du domaine',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _settings(d),
        ),
      ]),
      if (intention.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('« $intention »',
              style: TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic, color: cs.onSurface.withValues(alpha: .72))),
        ),
      if (pills.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in pills)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .06), borderRadius: BorderRadius.circular(999)),
                child: Text(t, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .72))),
              ),
          ]),
        ),
      ..._weekBlock(now, d, r, color),
    ]);
  }

  /// CETTE SEMAINE (grammaire des feuilles, 2026-11-01) : barre fait / attendu,
  /// une barre par jour, puis UN bouton — lancer l'activité la plus en retard.
  List<Widget> _weekBlock(DateTime now, Domain d, DomainWeek r, Color color) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final days = r.windowDays;
    final start = budgetWindowStart(now, days);
    final perDay = dailyMinutesByDomain(logic.state.sessions, logic.state.activeActivities, start, days, now: now)[d.id] ?? List.filled(days, 0);
    final today = budgetDayIndex(now, days) - 1;
    final maxDay = perDay.fold<int>(math.max(1, r.goalMinDay), (m, v) => v > m ? v : m);
    final running = logic.runningActivity();
    final runningHere = running != null && running.domainId == d.id;
    final late = _timeRows(now).where((t) => !t.paused && t.goalMinDay > 0 && t.doneMin < t.expectedMin).toList()
      ..sort((a, b) => (b.expectedMin - b.doneMin).compareTo(a.expectedMin - a.doneMin));
    if (!r.hasGoal && r.doneMin == 0 && late.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text(days == 14 ? 'SUR 14 JOURS' : 'CETTE SEMAINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
        if (r.hasGoal) Text('attendu ${fmtMin(r.expectedMin)}', style: TextStyle(fontSize: 11.5, color: mute)),
      ]),
      const SizedBox(height: 6),
      if (r.hasGoal) ExpectedBar(done: r.doneMin, total: r.weekMin, expected: r.expectedMin, color: color),
      const SizedBox(height: 8),
      SizedBox(
        height: 34,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < perDay.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: i > today ? 3 : (3 + 31 * perDay[i] / maxDay).clamp(3.0, 34.0),
                decoration: BoxDecoration(
                  color: i > today ? cs.onSurface.withValues(alpha: .06) : color.withValues(alpha: i == today ? .55 : 1),
                  borderRadius: BorderRadius.circular(2),
                  border: i == today ? Border.all(color: color) : null,
                ),
              ),
            ),
          ],
        ]),
      ),
      if (!runningHere && late.isNotEmpty) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: color.computeLuminance() > .45 ? Colors.black : Colors.white, minimumSize: const Size.fromHeight(46)),
          onPressed: () => _start(late.first.a),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('${late.first.a.name} · reste ${fmtMin(late.first.expectedMin - late.first.doneMin)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ];
  }

  /// ⚙ : intention et minimum vital (session Orion), veille, puis la gestion
  /// des domaines (nom, couleur) quand elle est branchée.
  Future<void> _settings(Domain d) async {
    final resting = logic.isDomainResting(d.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Intention et minimum vital'),
              subtitle: const Text('Avec Orion'),
              onTap: () => Navigator.pop(c, 'define')),
          ListTile(
              leading: Icon(resting ? Icons.wb_sunny_outlined : Icons.bedtime_outlined),
              title: Text(resting ? 'Lever la veille' : 'Mettre en veille…'),
              onTap: () => Navigator.pop(c, resting ? 'lift' : 'rest')),
          if (widget.onManageDomains != null)
            ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Nom, couleur, domaines'),
                onTap: () => Navigator.pop(c, 'manage')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'define':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DomainSessionScreen(logic: logic, domainName: d.name)));
      case 'lift':
        await liftRest(logic, widget.sync, d.id);
      case 'rest':
        final now = DateTime.now();
        final until = await showDatePicker(
            context: context,
            initialDate: now.add(const Duration(days: 7)),
            firstDate: now,
            lastDate: now.add(const Duration(days: 365)),
            locale: const Locale('fr', 'FR'),
            helpText: 'En veille jusqu\'au');
        if (until == null || !mounted) return;
        await showRestSheet(context,
            logic: logic,
            sync: widget.sync,
            untilYmd: ymdOf(until),
            excludeDomainIds: {for (final o in logic.state.activeDomains) if (o.id != d.id) o.id});
      case 'manage':
        widget.onManageDomains!();
    }
    if (mounted) setState(() {});
  }

  // ── Objectifs ───────────────────────────────────────────────────────────────

  List<Widget> _objectiveBody(DateTime now, Domain d) {
    final st = logic.state;
    final list = (_objectives ?? const <StrategicObjective>[]).where((o) => o.status == 'active' && o.domainId == d.id).toList();
    if (list.isEmpty) return const [];
    int pctOf(ObjectiveProgress p) => p.weekPercent == null ? 100 : (p.weekPercent! * 100).round();
    final rows = [for (final o in list) (o: o, p: computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now))]
      ..sort((a, b) => comparePct(pctOf(a.p), pctOf(b.p)));
    return [
      ListSectionTitle('OBJECTIFS · ${rows.length}'),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: StatusRow(
            leading: Icon(r.o.isTactical ? Icons.bolt_rounded : Icons.flag_outlined),
            title: r.o.title,
            sub: [
              if (r.o.isTactical) 'rush',
              if (r.p.daysLeft != null) r.p.daysLeft! <= 0 ? 'échéance passée' : 'encore ${r.p.daysLeft} j',
              if (isReadingDue(r.o, now)) 'relevé dû',
            ].join(' · '),
            bar: r.p.weekPercent == null ? null : (done: r.p.weekPercent!.clamp(0.0, 1.0), total: 1, expected: r.p.weekElapsed),
            pct: pctOf(r.p),
            chip: r.p.weekPercent == null ? null : '${pctOf(r.p)} % du rythme',
            onTap: () async {
              final changed = await showObjectiveTrajectorySheet(context, logic: logic, sync: widget.sync, objective: r.o, projects: widget.projects);
              if (changed) _loadObjectives();
            },
          ),
        ),
    ];
  }

  // ── Projets ─────────────────────────────────────────────────────────────────

  List<Widget> _projectBody(DateTime now, Domain d) {
    final st = logic.state;
    final all = widget.projects;
    final list = all
        .where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all) && (p.domainId ?? rootProjectOf(p, all).domainId) == d.id)
        .map((p) => (p: p, plan: projectPlan(p, now)))
        .toList()
      ..sort((a, b) => comparePct(a.plan.pctInt, b.plan.pctInt));
    if (list.isEmpty) return const [];
    return [
      ListSectionTitle('PROJETS · ${list.length}'),
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: StatusRow(
            leading: const Icon(Icons.view_timeline_outlined),
            title: r.p.title,
            sub: [
              '${r.plan.done} / ${r.plan.total} tâche${r.plan.total > 1 ? 's' : ''}',
              if (nextAction(r.p) case final n?) 'prochaine : ${n.action.title}',
            ].join(' · '),
            bar: r.plan.total > 0 ? (done: r.plan.done, total: r.plan.total, expected: r.plan.expected) : null,
            pct: r.plan.pctInt,
            chip: r.plan.expected <= 0 ? null : (r.plan.delta >= 0 ? 'au plan' : '${r.plan.delta} au plan'),
            onTap: () => showProjectSheet(context,
                project: r.p, domains: st.activeDomains, activities: st.activities, sessions: st.sessions, logic: logic, onStartTimer: widget.onStartTimer),
            onLongPress: () => showProjectFiche(context,
                project: r.p,
                allProjects: all,
                domains: st.activeDomains,
                activities: st.activities,
                sessions: st.sessions,
                sync: widget.sync,
                logic: logic,
                onStartTimer: widget.onStartTimer),
          ),
        ),
    ];
  }

  // ── Activités ───────────────────────────────────────────────────────────────

  List<Widget> _timeBody(DateTime now, Domain? d) {
    final cs = Theme.of(context).colorScheme;
    final rows = _timeRows(now);
    final live = rows.where((r) => !r.paused).toList()..sort((a, b) => comparePct(a.pctInt, b.pctInt));
    final paused = rows.where((r) => r.paused).toList();
    return [
      ListSectionTitle('ACTIVITÉS · ${live.length}', action: '+ Activité', onAction: () async {
        await widget.onCreate(domainId: d?.id, isHabit: false);
        if (mounted) setState(() {});
      }),
      if (live.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('Aucune activité-temps ici.', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
        )
      else
        for (final r in live) _timeRow(r, now),
      if (paused.isNotEmpty) ...[
        ListSectionTitle('EN PAUSE · ${paused.length}', onAction: () => setState(() => _showPaused = !_showPaused), expanded: _showPaused),
        if (_showPaused) for (final r in paused) _timeRow(r, now),
      ],
    ];
  }

  Widget _timeRow(_TimeRow r, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final a = r.a;
    final running = logic.runningActivity()?.id == a.id;
    final until = r.paused ? logic.snoozedUntilOf(a.id) : null;
    final sub = r.paused
        ? 'en pause${until == null ? '' : ' jusqu\'au ${until.day}/${until.month.toString().padLeft(2, '0')}'}'
        : [
            '${fmtMin(r.avg7)} / j en moy.',
            if (r.hasGoal) 'objectif ${fmtMin(r.goalMinDay)} / j' else 'pas d\'objectif',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: GestureDetector(
          onTap: r.paused ? null : () => running ? logic.stopActive() : _start(a),
          child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, color: running ? cs.primary : null),
        ),
        title: a.name,
        sub: sub,
        bar: r.hasGoal && !r.paused ? (done: r.doneMin, total: r.totalMin, expected: r.expectedMin) : null,
        pct: r.pctInt,
        chip: r.paused || !r.hasGoal ? null : (r.onTrack ? 'au rythme' : 'à rattraper'),
        muted: r.paused,
        trailing: r.paused || !r.hasGoal ? Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)) : null,
        onTap: () async {
          final changed = await widget.onOpenActivity(a);
          if (changed && mounted) setState(() {});
        },
        onLongPress: () => _rowMenu(a, now),
      ),
    );
  }

  // ── Routines ────────────────────────────────────────────────────────────────

  List<Widget> _habitBody(DateTime now, Domain? d) {
    final cs = Theme.of(context).colorScheme;
    final all = _acts(true);
    double ratio(Activity a) {
      final t = logic.activeHabitTarget(a);
      return t <= 0 ? 0 : (logic.activeHabitDone(a) / t).clamp(0.0, 1.0);
    }
    int pctOf(Activity a) => (ratio(a) * 100).round();
    // À faire d'abord (la moins avancée en tête), puis les atteintes.
    final todo = all.where((a) => !logic.habitReached(a)).toList()..sort((x, y) => comparePct(pctOf(x), pctOf(y)));
    final done = all.where(logic.habitReached).toList()..sort((x, y) => x.name.compareTo(y.name));
    return [
      ListSectionTitle('ROUTINES · ${all.length}', action: '+ Routine', onAction: () async {
        await widget.onCreate(domainId: d?.id, isHabit: true);
        if (mounted) setState(() {});
      }),
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('Aucune routine ici.', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
        ),
      for (final a in todo) _habitRow(a, now),
      for (final a in done) _habitRow(a, now),
    ];
  }

  Widget _habitRow(Activity a, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final target = logic.activeHabitTarget(a);
    final done = logic.activeHabitDone(a);
    final reached = logic.habitReached(a);
    final period = switch (a.habitFreq) { HabitFreq.weekly => '7 j', HabitFreq.monthly => '30 j', _ => 'aujourd\'hui' };
    final series = routineSeries(a, logic.state.habitHits, now, dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id), frozen: logic.frozenOf(a.id));
    final pct = target <= 0 ? 100 : (done / target * 100).round().clamp(0, 100);
    final todayN = routineTodayCount(logic, a);
    final mark = todayMark(a.habitFreq, todayN);
    final sub = [
      '$period : $done / $target',
      if (mark != null) mark,
      if (series.current > 0) '🔥 ${series.current} j',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Icon(reached || mark != null ? Icons.check_rounded : Icons.repeat_rounded,
            color: reached ? cs.primary : (mark != null ? cs.primary.withValues(alpha: .6) : null)),
        title: a.name,
        sub: sub,
        bar: target > 0 ? (done: done, total: target, expected: target) : null,
        pct: reached ? 100 : (pct >= 60 ? 60 : 0),
        muted: reached,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _round('−', done > 0 ? () => routineMinus(logic, a) : null),
          const SizedBox(width: 6),
          _round('+', () => routinePlus(logic, a), primary: true),
        ]),
        onTap: () => showRoutineSheet(context, logic: logic, habitId: a.id, day: now, onSaved: () => setState(() {})),
        onLongPress: () => _rowMenu(a, now),
      ),
    );
  }

  Widget _round(String label, VoidCallback? onTap, {bool primary = false}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: primary ? cs.primary.withValues(alpha: .16) : cs.onSurface.withValues(alpha: .06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: onTap == null ? cs.onSurface.withValues(alpha: .3) : (primary ? cs.primary : cs.onSurface))),
          ),
        ),
      ),
    );
  }
}
