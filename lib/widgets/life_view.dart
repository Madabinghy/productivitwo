import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart' show domainColor;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/life_natures.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/meal_day.dart' show mealWeekView, currentMealMoment, MealCell;
import 'package:productivitwo_v1/utils/meal_plan.dart' show PlannedMeal, leftoversOf, mealKey;
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/sleep_stats.dart';
import 'package:productivitwo_v1/utils/sport_stats.dart';
import 'package:productivitwo_v1/utils/week_stats.dart' show domainWeeks, DomainWeek;
import 'package:productivitwo_v1/utils/budget_window.dart' show dailyMinutesByDomain;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/meal_sheet.dart' show showMealSheet;
import 'package:productivitwo_v1/widgets/dishes_sheet.dart' show kMealAccent;
import 'package:productivitwo_v1/widgets/finance_sheet.dart' show kMoneyAccent, showFinanceSheet;
import 'package:productivitwo_v1/utils/finances.dart' show accountNow, euros, monthSummary, trackedDays;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/objectives_card.dart';
import 'package:productivitwo_v1/utils/seasons.dart';
import 'package:productivitwo_v1/widgets/season_widgets.dart';
import 'package:productivitwo_v1/widgets/sport_sheet.dart' show showSportSheet, WeightTrajectoryPainter;
import 'package:productivitwo_v1/widgets/sleep_sheet.dart' show SleepNightsMini;
import 'package:productivitwo_v1/widgets/finance_flow_card.dart' show FinanceFlowMini;
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show computeObjectiveTrajectory;
import 'package:productivitwo_v1/widgets/week_stats_view.dart';
import 'package:productivitwo_v1/utils/freedom.dart';
import 'package:productivitwo_v1/utils/tile_charts.dart';
import 'package:productivitwo_v1/utils/domain_widget.dart';
import 'package:productivitwo_v1/widget_service.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart' show projectBricks;
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show ProgressBricks;
import 'package:productivitwo_v1/widgets/freedom_screens.dart';

const _kNight = Color(0xFF7FB2E8);
const _kAmber = Color(0xFFF0B44C);
const _natureColors = {
  DomainNature.night: _kNight,
  DomainNature.sessions: Color(0xFFF07C4C),
  DomainNature.meals: Color(0xFF7CC96A),
  DomainNature.money: kMoneyAccent,
};
const _kSheetNames = {
  DomainNature.night: 'Sommeil',
  DomainNature.sessions: 'Sport',
  DomainNature.meals: 'Repas',
  DomainNature.money: 'Finances',
};
const _kNaturesPref = 'life_natures';
/// Domaines de travail dont la tuile montre les briques du projet du moment (au lieu du cumul).
const _kBricksPref = 'life_tile_bricks';
/// Hauteur commune des tuiles de Ma vie (à l'échelle du texte 1).
const kLifeTileHeight = 192.0;
/// Hauteur des mini-graphiques des tuiles.
const kLifeVizHeight = 48.0;

/// Onglet « Ma vie » (maquette validée 2026-11-01) : les lanceurs des modes,
/// la semaine en une ligne, une tuile par domaine selon sa nature (Sommeil,
/// Sport, Repas ouvrent leur feuille ; les autres la page du domaine), les
/// objectifs dans leur domaine ; Saison, Badges, tous les objectifs, Gérer.
class LifeView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final BadgeCenter? badges;
  final List<Project> projects;
  final Future<bool?> Function(Domain domain) onOpenDomain;
  final VoidCallback onOpenSleep;
  final VoidCallback onManageDomains;
  const LifeView({
    super.key,
    required this.logic,
    required this.sync,
    this.badges,
    required this.projects,
    required this.onOpenDomain,
    required this.onOpenSleep,
    required this.onManageDomains,
  });

  @override
  State<LifeView> createState() => LifeViewState();
}

class LifeViewState extends State<LifeView> {
  AppLogic get logic => widget.logic;
  List<StrategicObjective> _objectives = FicheCache.objectives ?? const [];
  Map<String, DomainNature> _overrides = const {};
  Set<String> _bricks = const {};
  /// Ce que touche chaque tuile (feuille ou page du domaine) : le widget iOS y mène.
  final _taps = <String, VoidCallback>{};
  Timer? _refresh;
  DateTime? _exportedAt;
  String? _exportedIds;

  @override
  void initState() {
    super.initState();
    _load();
    // Le widget « Mes domaines » suit même quand l'onglet est caché (_TabFreeze ne le reconstruit plus).
    _refresh = Timer.periodic(const Duration(minutes: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Lien du widget : ce que fait le tap sur la tuile du domaine.
  void openDomain(String id) {
    final tap = _taps[id];
    if (tap != null) return tap();
    final d = logic.state.activeDomains.where((x) => x.id == id).firstOrNull;
    if (d != null) widget.onOpenDomain(d);
  }

  /// Dessine les tuiles pour le widget, au plus toutes les 10 minutes (tout de suite si la liste change).
  void _exportWidget(List<({WidgetDomain domain, Widget square, Widget? wide})> cells, Color bg) {
    final ids = cells.map((c) => c.domain.id).join(',');
    final at = _exportedAt;
    if (ids == _exportedIds && at != null && DateTime.now().difference(at).inMinutes < 10) return;
    _exportedAt = DateTime.now();
    _exportedIds = ids;
    WidgetService.exportDomains(cells: cells, bg: bg.toARGB32());
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kNaturesPref);
      if (raw != null && mounted) setState(() => _overrides = parseNatures(Map<String, dynamic>.from(jsonDecode(raw) as Map)));
      final b = p.getStringList(_kBricksPref);
      if (b != null && mounted) setState(() => _bricks = b.toSet());
    } catch (_) {}
    try {
      final o = await FicheCache.objectivesFast(widget.sync);
      if (o != null && mounted) setState(() => _objectives = o);
    } catch (_) {}
  }

  Future<void> _reloadObjectives() async {
    try {
      final o = await FicheCache.loadObjectives(widget.sync);
      if (mounted) setState(() => _objectives = o);
    } catch (_) {}
  }

  DomainNature _natureOf(Domain d) => _overrides[d.id] ?? guessNature(d, logic.state.activities);

  /// Le projet du moment d'un domaine (vivant, hors dossiers), s'il y en a un.
  Project? _projectOf(Domain d, DateTime now) {
    final all = widget.projects;
    final live = [
      for (final p in all)
        if (p.domainId == d.id && p.status == 'active' && !p.paused && !isFolderProject(p, all) && p.tasks.isNotEmpty) p,
    ];
    if (live.isEmpty) return null;
    final ranked = rankProjectMoments(live, logic.state.sessions, now);
    return ranked.isEmpty ? live.first : ranked.first.project;
  }

  Future<void> _toggleBricks(Domain d) async {
    final next = {..._bricks};
    if (!next.remove(d.id)) next.add(d.id);
    setState(() => _bricks = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kBricksPref, next.toList());
    } catch (_) {}
  }

  Future<void> _pickNature(Domain d) async {
    final cur = _natureOf(d);
    final canBricks = cur == DomainNature.work && _projectOf(d, DateTime.now()) != null;
    final n = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('${d.name} · quelle nature ?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Elle choisit la tuile et ce qui s’ouvre au tap. Rien d’autre ne change.', style: TextStyle(fontSize: 12.5)),
          ),
          if (canBricks)
            SwitchListTile(
              key: const Key('life-bricks-toggle'),
              value: _bricks.contains(d.id),
              title: const Text('Briques du projet du moment'),
              subtitle: const Text('à la place du cumul de la semaine', style: TextStyle(fontSize: 12)),
              onChanged: (_) => Navigator.pop(ctx, 'bricks'),
            ),
          for (final n in DomainNature.values)
            ListTile(
              leading: Text(kNatureEmoji[n]!, style: const TextStyle(fontSize: 20)),
              title: Text(kNatureLabels[n]!),
              subtitle: Text(kNatureHints[n]!, style: const TextStyle(fontSize: 12)),
              trailing: n == cur ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, n),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (n == 'bricks') return _toggleBricks(d);
    if (n is! DomainNature || n == cur) return;
    setState(() => _overrides = {..._overrides, d.id: n});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kNaturesPref, jsonEncode(_overrides.map((k, v) => MapEntry(k, v.name))));
    } catch (_) {}
  }

  String? _domainOf(StrategicObjective o) {
    if (o.domainId != null && o.domainId!.isNotEmpty) return o.domainId;
    final ids = [...o.timeCommitments.map((c) => c.activityId), ...o.routineCommitments.map((c) => c.activityId)];
    for (final id in ids) {
      final a = logic.state.activities.where((x) => x.id == id).firstOrNull;
      if (a != null) return a.domainId;
    }
    return null;
  }

  void _openAllObjectives() {
    showFiche<void>(
      context,
      builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 32), children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 4), child: Text('Objectifs', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        ObjectivesCard(logic: logic, sync: widget.sync, projects: widget.projects),
      ]),
    ).then((_) => _reloadObjectives());
  }

  void _openCap() {
    showSeasonCapSheet(context, logic: logic, objectives: _objectives, sync: widget.sync, projects: widget.projects).then((_) => _reloadObjectives());
  }

  /// Cible de saison en centimes quand l'objectif se mesure en euros (courbe du solde).
  int? _euroTargetCents((Season, SeasonGoal, StrategicObjective)? sg) {
    if (sg == null) return null;
    final g = sg.$2;
    if (g.kind != SeasonGoalKind.metric || g.target == null) return null;
    final u = (g.unit ?? '').toLowerCase();
    if (!u.contains('€') && !u.contains('eur')) return null;
    return (g.target! * 100).round();
  }

  /// L'objectif de la saison en cours porté par ce domaine (le premier posé).
  (Season, SeasonGoal, StrategicObjective)? _seasonGoalOf(Domain d) {
    final s = currentSeason(logic.seasons, logic.livedTodayYmd);
    if (s == null) return null;
    for (final g in s.goals) {
      final o = _objectives.where((x) => x.id == g.objectiveId).firstOrNull;
      if (o != null && _domainOf(o) == d.id) return (s, effectiveSeasonGoal(s, g, o), o);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final st = logic.state;
    final now = DateTime.now();
    final domains = st.activeDomains;
    final weeks = {
      for (final r in domainWeeks(
          domains: domains, activities: st.activeActivities, sessions: st.sessions, hits: st.habitHits, now: now, rest: logic.restDomains, windowDays: logic.budgetWindowDays))
        r.domain.id: r,
    };
    final active = _objectives.where((o) => o.status == 'active').toList();
    final progress = {for (final o in active) o.id: computeObjectiveProgress(o, st.activities, st.sessions, st.habitHits, now)};
    final byDomain = <String, List<StrategicObjective>>{};
    final orphan = <StrategicObjective>[];
    for (final o in active) {
      final d = _domainOf(o);
      if (d == null || !domains.any((x) => x.id == d)) {
        orphan.add(o);
      } else {
        (byDomain[d] ??= []).add(o);
      }
    }
    for (final l in byDomain.values) {
      l.sort((a, b) => (progress[a.id]?.weekPercent ?? 2).compareTo(progress[b.id]?.weekPercent ?? 2));
    }
    final sorted = [...domains]..sort((a, b) {
        final c = natureOrder(_natureOf(a)).compareTo(natureOrder(_natureOf(b)));
        return c != 0 ? c : domains.indexOf(a).compareTo(domains.indexOf(b));
      });
    // Une seule tuile Sommeil / Sport / Repas, même si deux domaines en ont la nature.
    final seenSheet = <DomainNature>{};

    final tiles = <(Widget, bool)>[];
    final cells = <({WidgetDomain domain, Widget square, Widget? wide})>[];
    for (final d in sorted) {
      var n = _natureOf(d);
      if (_natureColors.containsKey(n)) {
        // Nature à feuille déjà prise par un autre domaine : la tuile reste, en tuile de domaine
        // (bug user 2026-11-05 : elle disparaissait sans un mot).
        if (seenSheet.contains(n)) {
          // Nature devinée (Sport ET Musculation) : la feuille couvre déjà les deux, une seule tuile.
          // Nature choisie à la main : la tuile reste, en tuile de domaine.
          if (!_overrides.containsKey(d.id)) continue;
          n = _fallbackNature(d);
        } else {
          seenSheet.add(n);
        }
      }
      // Routines × jours sur toute la largeur : les noms se lisent (retour user 2026-11-05).
      final wide = _wideGrid(d, n);
      tiles.add((_tile(cs, d, n, weeks[d.id], byDomain[d.id] ?? const [], progress, now, wide: wide), wide));
      cells.add((
        domain: WidgetDomain(
          id: d.id,
          name: _kSheetNames[n] ?? d.name,
          color: (_natureColors[n] ?? domainColor(d.id, st.activeDomains) ?? cs.primary).toARGB32(),
          link: 'domain/${d.id}',
          pace: domainPace(weeks[d.id]),
          wide: wide,
        ),
        square: _widgetFrame(_tile(cs, d, n, weeks[d.id], byDomain[d.id] ?? const [], progress, now, forWidget: true)),
        wide: wide ? _widgetFrame(_tile(cs, d, n, weeks[d.id], byDomain[d.id] ?? const [], progress, now, wide: true, forWidget: true)) : null,
      ));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _exportWidget(cells, cs.surface);
    });

    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 120), children: [
        Row(children: [
          Expanded(child: Text('Organisation', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface))),
          // Objectifs : la liste complète (rushs, veille, archivés, création) ; les tuiles portent chacune le leur.
          TextButton(key: const ValueKey('life-objectives'), onPressed: _openAllObjectives, child: Text('Objectifs · ${active.length}')),
          TextButton(onPressed: widget.onManageDomains, child: const Text('Gérer')),
        ]),
        const SizedBox(height: 6),
        // Saison (refonte 2026-11-04) : la période des objectifs, sa cible sur chaque tuile.
        SeasonBanner(
          logic: logic,
          objectives: _objectives,
          onOpenCap: _openCap,
          onOpenBilan: (season) => showSeasonBilanSheet(context, logic: logic, season: season, objectives: _objectives, sync: widget.sync, projects: widget.projects)
              .then((_) => _reloadObjectives()),
        ),
        _section(mute, 'CETTE SEMAINE'),
        WeekStatsView(logic: logic, sync: widget.sync, badges: widget.badges, onOpenDomain: (d, {focus = 'time'}) => widget.onOpenDomain(d), onManageDomains: widget.onManageDomains, onlyWeekLine: true),
        _section(mute, 'MES DOMAINES', right: 'appui long = nature'),
        LayoutBuilder(builder: (ctx, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final (t, wide) in tiles) SizedBox(width: wide ? c.maxWidth : w, child: t)]);
        }),
        _freedomTile(cs, mute),
        if (orphan.isNotEmpty) ...[
          _section(mute, 'OBJECTIFS SANS DOMAINE'),
          for (final o in orphan) _objectiveLine(cs, o, progress[o.id], cs.primary),
        ],
      ]),
    );
  }

  // Liberté (2026-11-04) : une carte par chose qu'on quitte ; aucune = un lien discret, sinon « + une autre ».
  Widget _freedomTile(ColorScheme cs, Color mute) {
    final ids = logic.freedomIds;
    void refresh(_) => mounted ? setState(() {}) : null;
    final add = Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const ValueKey('life-freedom-start'),
        onPressed: () => showFreedomSetup(context, logic: logic).then(refresh),
        child: Text(ids.isEmpty ? 'Quitter une habitude ›' : '+ Une autre habitude', style: TextStyle(color: mute)),
      ),
    );
    if (ids.isEmpty) return add;
    final now = DateTime.now();
    Widget card(String id) {
      final f = logic.freedomOf(id);
      final p = f.plan!;
      final stop = p.goal == FreedomGoal.stop;
      final head = stop ? 'libre depuis ${freeLabel(now.difference(freeSince(f)))}' : '${usedThisPeriod(f, now)} / ${p.limit ?? '?'} ${p.unit} ${p.period == FreedomPeriod.day ? "aujourd'hui" : 'cette semaine'}';
      final n = urgesOvercome(f);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: ValueKey('life-freedom-$id'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => showFreedomSheet(context, logic: logic, id: id).then(refresh),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kFreeAccent)),
                    const SizedBox(height: 2),
                    Text(head, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text('$n envie${n > 1 ? 's' : ''} surmontée${n > 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: mute)),
                  ]),
                ),
                FilledButton(
                  key: ValueKey('life-freedom-urge-$id'),
                  style: FilledButton.styleFrom(backgroundColor: kUrgeAccent, foregroundColor: const Color(0xFF2A1606)),
                  onPressed: () => showUrgeScreen(context, logic: logic, id: id).then(refresh),
                  child: const Text("J'ai une envie", style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(mute, 'LIBERTÉ'),
      for (final id in ids) card(id),
      add,
    ]);
  }

  Widget _section(Color mute, String t, {String? right}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
          if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
        ]),
      );

  Widget _objectiveLine(ColorScheme cs, StrategicObjective o, ObjectiveProgress? p, Color c, {int more = 0}) {
    final pct = p?.weekPercent;
    return InkWell(
      onTap: () async {
        await showObjectiveTrajectorySheet(context, logic: logic, sync: widget.sync, objective: o, projects: widget.projects);
        _reloadObjectives();
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5))),
            if (more > 0) Text(' +$more ', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .5))),
            if (pct != null) Text('${(pct * 100).round()} %', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ]),
          if (pct != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), minHeight: 4, color: c, backgroundColor: cs.onSurface.withValues(alpha: .08)),
              ),
            ),
        ]),
      ),
    );
  }

  /// Nature de repli d'un domaine dont la nature à feuille est déjà prise : Pratique s'il a du temps, sinon Entretien.
  DomainNature _fallbackNature(Domain d) {
    final acts = logic.state.activities.where((a) => !a.deleted && a.domainId == d.id);
    return acts.any((a) => !a.isHabit) ? DomainNature.practice : DomainNature.upkeep;
  }

  /// La tuile prend toute la largeur quand elle montre la grille routines × jours.
  bool _wideGrid(Domain d, DomainNature n) =>
      (n == DomainNature.upkeep || n == DomainNature.tracking) &&
      logic.state.activities.any((a) => !a.deleted && a.isHabit && a.domainId == d.id && a.habitFreq != HabitFreq.monthly);

  Widget _tile(ColorScheme cs, Domain d, DomainNature n, DomainWeek? w, List<StrategicObjective> objs, Map<String, ObjectiveProgress> progress, DateTime now,
      {bool wide = false, bool forWidget = false}) {
    final st = logic.state;
    final mute = cs.onSurface.withValues(alpha: .55);
    final c = _natureColors[n] ?? domainColor(d.id, st.activeDomains) ?? cs.primary;
    final sg = _seasonGoalOf(d);
    String eyebrow = d.name.toUpperCase();
    String value = '';
    String sub = '';
    Widget? viz;
    VoidCallback onTap = () => widget.onOpenDomain(d);
    switch (n) {
      case DomainNature.night:
        final nights = sleepNightList(sessions: st.sessions, activities: st.activities, now: now, dayStartMin: logic.dayStartMin, nights: 7);
        final target = sleepTargetMin(sleepActivityOf(st.activities));
        final s = sleepStats(nights, target);
        eyebrow = 'SOMMEIL';
        value = s.avgMin == null ? 'Pas de nuit' : fmtNight(s.avgMin!);
        sub = s.avgMin == null ? 'lance le chrono Sommeil au coucher' : 'moy. ${s.nights} nuits · dette ${fmtNight(s.debtMin)}';
        // Les nuits du coucher au lever, comme dans la feuille Sommeil (retour user 2026-11-04).
        final byBed = sleepNightsByBedDay(sessions: st.sessions, activities: st.activities, now: now, dayStartMin: logic.dayStartMin, nights: 7);
        viz = byBed.nights.every((x) => x == null) ? null : SleepNightsMini(nights: byBed.nights, bedDays: byBed.bedDays, target: target, height: kLifeVizHeight);
        onTap = widget.onOpenSleep;
      case DomainNature.sessions:
        final pick = resolveSportPick(st.activities, st.domains, logic.sportOverrides);
        final today = ymdOf(livedDate(now, logic.dayStartMin));
        final days = sportDays(pick: pick, sessions: st.sessions, hits: st.habitHits, fromYmd: mondayOf(today), toYmd: today, now: now, dayStartMin: logic.dayStartMin);
        final sessions = days.fold(0, (s, x) => s + x.sessions);
        final min = days.fold(0, (s, x) => s + x.activeMin);
        eyebrow = 'SPORT';
        value = '$sessions séance${sessions > 1 ? 's' : ''}';
        sub = min == 0 ? 'rien encore cette semaine' : '${fmtMin(min)} cette semaine';
        // Une barre par jour de la semaine : le temps actif (vide = repos).
        final maxMin = days.fold<int>(0, (a, x) => a > x.activeMin ? a : x.activeMin);
        viz = _bars([for (var i = 0; i < 7; i++) i < days.length && days[i].activeMin > 0 ? (days[i].activeMin / maxMin).clamp(0.12, 1.0) : 0.0], c, cs);
        // Avec un objectif chiffré (le poids) : sa trajectoire, comme dans la feuille Sport (retour user 2026-11-04).
        final wo = sportObjective(pick, _objectives.where((o) => o.status == 'active').toList());
        if (wo != null && wo.metric != null) {
          final traj = computeObjectiveTrajectory(wo, st.sessions, now);
          if (traj.result != null) {
            viz = SizedBox(height: kLifeVizHeight, width: double.infinity, child: CustomPaint(painter: WeightTrajectoryPainter(wo, traj, cs.onSurface, dot: 2.5)));
          }
        }
        onTap = () => showSportSheet(context, logic: logic, sync: widget.sync);
      case DomainNature.meals:
        final t = logic.livedToday;
        final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
        final days = [for (var i = 0; i < 7; i++) ymdOf(DateTime(monday.year, monday.month, monday.day + i))];
        final week = logic.mealWeek(days.first);
        final v = mealWeekView(days: days, week: week, activities: st.activities, hits: st.habitHits, sessions: st.sessions, now: now, dayStartMin: logic.dayStartMin);
        final moment = currentMealMoment(now);
        final nowKey = mealKey(ymdOf(t), moment);
        final leftFrom = leftoversOf(week.slots, days)[nowKey];
        final next = week.slots[nowKey] ??
            (leftFrom == null || week.slots[leftFrom] == null ? null : PlannedMeal(title: 'les restes · ${week.slots[leftFrom]!.title}'));
        eyebrow = 'REPAS';
        value = v.counted == 0 ? 'Repas' : '${v.balanced} / ${v.counted}';
        sub = next != null ? '${moment == 'petit-dej' ? 'ce matin' : (moment == 'midi' ? 'ce midi' : 'ce soir')} : ${next.title}' : (v.counted == 0 ? 'menu, plats, courses' : 'repas équilibrés');
        // La grille midi / soir de la semaine, comme dans la feuille Repas (retour user 2026-11-04).
        viz = _mealGrid(cs, days, (k) => v.cells[k], nowKey);
        onTap = () => showMealSheet(context, logic: logic, sync: widget.sync);
      case DomainNature.money:
        final f = logic.finances;
        final today = logic.livedTodayYmd;
        final m = monthSummary(f, today);
        final t = DateTime.parse(today);
        final from = ymdOf(DateTime(t.year, t.month, t.day - 89));
        final tracked = trackedDays(f).where((y) => y.compareTo(from) >= 0 && y.compareTo(today) <= 0).length;
        eyebrow = 'FINANCES';
        // Le solde du compte d'abord (retour user 2026-11-03), dès qu'un solde est posé.
        final acc = accountNow(f, today);
        if (acc != null) {
          value = euros(acc.balance);
          sub = 'sur ton compte · $tracked / 90 jours suivis';
          // 30 jours : la courbe du solde et les barres entré / sorti, comme dans la feuille Finances (retour user 2026-11-04).
          viz = FinanceFlowMini(finances: f, todayYmd: today, height: kLifeVizHeight, targetCents: _euroTargetCents(sg));
        } else {
          value = m.hasIncome ? euros(m.remaining) : (m.spent > 0 ? euros(m.spent) : 'Finances');
          sub = m.hasIncome ? 'reste à vivre · $tracked / 90 jours suivis' : (m.spent > 0 ? 'dépensés ce mois · pose ton solde' : 'note tes dépenses, jour après jour');
          viz = f.expenses.isEmpty && f.incomes.isEmpty ? null : FinanceFlowMini(finances: f, todayYmd: today, height: kLifeVizHeight, targetCents: _euroTargetCents(sg));
        }
        onTap = () => showFinanceSheet(context, logic: logic);
      case DomainNature.work:
      case DomainNature.practice:
      case DomainNature.tracking:
      case DomainNature.upkeep:
        if (w != null) {
          if (n == DomainNature.work || (n != DomainNature.upkeep && w.routinesTotal == 0)) {
            value = w.doneMin == 0 ? '—' : fmtMin(w.doneMin);
            sub = w.hasGoal ? 'sur ${fmtMin(w.expectedMin)} attendues' : 'cette semaine';
          } else {
            value = w.routinesTotal == 0 ? (w.doneMin == 0 ? '—' : fmtMin(w.doneMin)) : '${w.routinesReached} / ${w.routinesTotal}';
            sub = w.routinesTotal == 0 ? 'cette semaine' : 'routines au rythme';
          }
          viz = _domainDays(cs, d, w, n, now, c);
          // Un graphique par nature (maquette validée 2026-11-05).
          final chart = _natureChart(cs, d, w, n, now, c, wide: wide);
          if (chart != null) {
            value = chart.value;
            sub = chart.sub;
            viz = chart.viz;
          }
          if (w.resting) sub = 'en veille';
        }
    }
    // Objectif de saison chiffré : sa trajectoire de saison (fenêtre, pointillés jusqu'à la cible), sauf Finances (courbe du solde + cible).
    SeasonGoalView? sView;
    if (sg != null) {
      final (season, goal, obj) = sg;
      sView = seasonGoalView(season, goal, obj, todayYmd: logic.livedTodayYmd, activities: st.activities, sessions: st.sessions, hits: st.habitHits);
      if (goal.kind == SeasonGoalKind.metric && !(n == DomainNature.money && _euroTargetCents(sg) != null)) {
        viz = SizedBox(
          height: kLifeVizHeight,
          width: double.infinity,
          child: CustomPaint(painter: SeasonMetricPainter(o: obj, s: season, g: goal, line: const Color(0xFF5CC79A), ink: cs.onSurface, now: now)),
        );
      }
    }
    final behind = w != null && w.hasGoal && !w.resting && w.doneMin < w.expectedMin * .95;
    if (forWidget) return _widgetCell(cs, eyebrow, value, sub, viz ?? _bars(const [0, 0, 0, 0, 0, 0, 0], c, cs), c, behind);
    _taps[d.id] = onTap;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _pickNature(d),
        // Toutes les tuiles ont la même hauteur (retour user 2026-11-02) : des
        // places fixes pour la sous-ligne (2 lignes), le mini-graphique des
        // 7 jours et l'objectif (vide s'il n'y en a pas).
        child: Container(
          height: kLifeTileHeight * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 3))),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .7, color: c))),
              Text(kNatureEmoji[n]!, style: const TextStyle(fontSize: 11)),
            ]),
            const SizedBox(height: 3),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: behind ? _kAmber : null)),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: mute, height: 1.3)),
            const Spacer(),
            viz ?? _bars(const [0, 0, 0, 0, 0, 0, 0], c, cs),
            const SizedBox(height: 7),
            Divider(height: 1, color: cs.onSurface.withValues(alpha: .07)),
            SizedBox(
              height: 30,
              child: sg != null && sView != null
                  ? SeasonGoalLine(
                      view: sView,
                      title: sg.$3.title,
                      onTap: () async {
                        await showSeasonGoalSheet(context, logic: logic, season: sg.$1, goal: sg.$2, objective: sg.$3, sync: widget.sync, projects: widget.projects);
                        _reloadObjectives();
                      },
                    )
                  : objs.isEmpty
                  ? Align(alignment: Alignment.centerLeft, child: Text('pas d’objectif', style: TextStyle(fontSize: 11, color: mute.withValues(alpha: .6))))
                  : _objectiveLine(cs, objs.first, progress[objs.first.id], c, more: objs.length - 1),
            ),
          ]),
        ),
      ),
    );
  }

  /// Le cadre hors écran d'une image du widget : thème, localisations et textes de l'app, sans agrandissement.
  Widget _widgetFrame(Widget child) => InheritedTheme.captureAll(
        context,
        MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: Localizations.override(context: context, child: Material(type: MaterialType.transparency, child: child)),
        ),
      );

  /// Une case du widget « Mes domaines » : la tuile sans son pied (pas de place), comme la maquette.
  Widget _widgetCell(ColorScheme cs, String eyebrow, String value, String sub, Widget viz, Color c, bool behind) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .8, color: c)),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: behind ? _kAmber : cs.onSurface)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: .6))),
          const Spacer(),
          viz,
        ]),
      );

  /// Le graphique de la nature du domaine, ou null (on garde alors les barres des 7 jours).
  ({String value, String sub, Widget viz})? _natureChart(ColorScheme cs, Domain d, DomainWeek w, DomainNature n, DateTime now, Color c, {bool wide = false}) {
    final st = logic.state;
    final today = livedDate(now, logic.dayStartMin);
    final day = DateTime(today.year, today.month, today.day);
    final dc = domainColor(d.id, st.activeDomains) ?? c;
    final routines = [for (final a in st.activities) if (!a.deleted && a.isHabit && a.domainId == d.id) a];
    switch (n) {
      case DomainNature.work:
        // ④ Briques du projet du moment, si choisies et s'il y en a un.
        if (_bricks.contains(d.id)) {
          final p = _projectOf(d, now);
          if (p != null) {
            final row = projectBricks(p, day);
            return (
              value: '${row.done} / ${row.total}',
              sub: '${p.title}${row.late > 0 ? ' · ${row.late} en retard' : ''}',
              viz: SizedBox(height: kLifeVizHeight, child: Align(alignment: Alignment.bottomCenter, child: ProgressBricks(row: row, height: 18, gap: 2))),
            );
          }
        }
        // ① Le cumul de la fenêtre face au rythme.
        final start = DateTime(day.year, day.month, day.day - (w.daysElapsed - 1));
        final daily = dailyMinutesByDomain(st.sessions, st.activities, start, w.daysElapsed, now: now)[d.id] ?? List<int>.filled(w.daysElapsed, 0);
        final cc = cumulChart(daily, perDay: w.resting ? 0 : w.goalMinDay, windowDays: w.windowDays);
        return (
          value: cc.done == 0 ? '—' : fmtMin(cc.done),
          sub: '${w.windowDays == 7 ? 'depuis lundi' : 'sur la quinzaine'} · ${cumulLabel(cc, fmtMin)}',
          viz: SizedBox(height: kLifeVizHeight, width: double.infinity, child: CustomPaint(painter: _CumulPainter(cc, dc, cs.onSurface))),
        );
      case DomainNature.practice:
        // ② Le calendrier des 28 derniers jours (le temps, sinon les coches de ses routines).
        final start = DateTime(day.year, day.month, day.day - 27);
        var daily = dailyMinutesByDomain(st.sessions, st.activities, start, 28, now: now)[d.id] ?? List<int>.filled(28, 0);
        var goal = w.goalMinDay;
        if (daily.every((m) => m == 0) && routines.isNotEmpty) {
          final ids = {for (final r in routines) r.id};
          daily = List<int>.filled(28, 0);
          for (final h in st.habitHits) {
            if (!ids.contains(h.habitId)) continue;
            final hd = livedDate(h.ts, logic.dayStartMin);
            final i = DateTime(hd.year, hd.month, hd.day).difference(start).inDays;
            if (i >= 0 && i < 28) daily[i]++;
          }
          goal = 0;
        }
        final weekStart = day.weekday - 1;
        final weekMin = daily.sublist(28 - 1 - weekStart).fold(0, (a, b) => a + b);
        return (
          value: '${activeDays(daily)} / 28 jours',
          sub: w.doneMin > 0 || weekMin > 0 ? '${fmtMin(w.doneMin)} cette semaine' : 'rien cette semaine',
          viz: _calendarViz(cs, calendarLevels(daily, goal: goal), day, dc),
        );
      case DomainNature.upkeep:
      case DomainNature.tracking:
        // ③ Routines × jours, celles qui décrochent d'abord.
        final rows = routineGrid(routines: routines, hits: st.habitHits, now: now, dayStartMin: logic.dayStartMin);
        if (rows.isEmpty) return null;
        final behind = rows.where((r) => r.behind).length;
        return (
          value: '${rows.length - behind} / ${rows.length}',
          sub: behind == 0 ? 'routines au rythme' : 'au rythme · $behind à rattraper',
          viz: _routineGridViz(cs, rows, dc, wide: wide),
        );
      default:
        return null;
    }
  }

  /// ② 28 cases, 4 semaines de 7 jours (la dernière finit aujourd'hui), plus foncées selon le jour.
  Widget _calendarViz(ColorScheme cs, List<int> levels, DateTime today, Color c) {
    const alpha = [0.0, .3, .52, .76, 1.0];
    return SizedBox(
      height: kLifeVizHeight,
      child: Column(children: [
        for (var r = 0; r < 4; r++) ...[
          if (r > 0) const SizedBox(height: 3),
          Expanded(
            child: Row(children: [
              for (var j = 0; j < 7; j++) ...[
                if (j > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: levels[r * 7 + j] == 0 ? cs.onSurface.withValues(alpha: .08) : c.withValues(alpha: alpha[levels[r * 7 + j]]),
                      borderRadius: BorderRadius.circular(3),
                      border: r * 7 + j == 27 ? Border.all(color: cs.onSurface.withValues(alpha: .85), width: 1.2) : null,
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  /// ③ Une ligne par routine (4 au plus, celles qui décrochent d'abord), une case par jour de la semaine.
  Widget _routineGridViz(ColorScheme cs, List<RoutineRow> rows, Color c, {bool wide = false}) {
    final shown = rows.take(4).toList();
    final todayIdx = livedDate(DateTime.now(), logic.dayStartMin).weekday - 1;
    Color cell(RoutineCell k) => switch (k) {
          RoutineCell.done => c,
          RoutineCell.partial => c.withValues(alpha: .4),
          RoutineCell.missed => cs.onSurface.withValues(alpha: .1),
          RoutineCell.future => Colors.transparent,
        };
    return SizedBox(
      height: kLifeVizHeight,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        for (final (i, r) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: 3),
          SizedBox(
            height: (kLifeVizHeight - 3 * (shown.length - 1)) / (shown.length < 4 ? 4 : shown.length),
            child: Row(children: [
              SizedBox(
                width: wide ? 130 : 44,
                child: Text(r.routine.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: wide ? 10.5 : 8.5, height: 1, fontWeight: FontWeight.w700, color: r.behind ? _kAmber : cs.onSurface.withValues(alpha: .7))),
              ),
              for (var j = 0; j < 7; j++) ...[
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cell(r.cells[j]),
                      borderRadius: BorderRadius.circular(2),
                      border: j == todayIdx
                          ? Border.all(color: cs.onSurface.withValues(alpha: .8), width: 1)
                          : (r.cells[j] == RoutineCell.future ? Border.all(color: cs.onSurface.withValues(alpha: .1), width: .8) : null),
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: wide ? 34 : 22,
                child: Text(r.right, textAlign: TextAlign.right,
                    style: TextStyle(fontSize: wide ? 10.5 : 8.5, height: 1, fontWeight: FontWeight.w800, color: r.behind ? _kAmber : cs.onSurface.withValues(alpha: .6))),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// Mini-graphique des 7 derniers jours d'un domaine : le temps chronométré
  /// pour un domaine de temps, sinon les coches des routines du domaine.
  Widget _domainDays(ColorScheme cs, Domain d, DomainWeek w, DomainNature n, DateTime now, Color c) {
    final st = logic.state;
    final today = livedDate(now, logic.dayStartMin);
    final start = DateTime(today.year, today.month, today.day - 6);
    final time = n == DomainNature.work || (n != DomainNature.upkeep && w.routinesTotal == 0);
    if (time) {
      final row = dailyMinutesByDomain(st.sessions, st.activities, start, 7, now: now)[d.id] ?? List<int>.filled(7, 0);
      final mx = row.fold<int>(0, (a, b) => a > b ? a : b);
      return _bars([for (final m in row) m <= 0 ? 0.0 : (m / mx).clamp(0.1, 1.0)], c, cs);
    }
    final routines = {for (final a in st.activities) if (!a.deleted && a.isHabit && a.domainId == d.id) a.id};
    final per = List<int>.filled(7, 0);
    for (final h in st.habitHits) {
      if (!routines.contains(h.habitId)) continue;
      final day = livedDate(h.ts, logic.dayStartMin);
      final i = DateTime(day.year, day.month, day.day).difference(start).inDays;
      if (i >= 0 && i < 7) per[i]++;
    }
    final mx = per.fold<int>(0, (a, b) => a > b ? a : b);
    return _bars([for (final k in per) k <= 0 ? 0.0 : (k / mx).clamp(0.1, 1.0)], c, cs);
  }

  /// Mini grille des repas : une case par midi / soir des 7 jours (équilibré, autre chose, prévu, rien noté).
  Widget _mealGrid(ColorScheme cs, List<String> days, MealCell? Function(String key) cell, String nowKey) {
    Color color(MealCell? c) => switch (c) {
          MealCell.ok => kMealAccent,
          MealCell.other => const Color(0xFF3A2F1B),
          MealCell.planned => const Color(0xFF1D2742),
          MealCell.none => cs.onSurface.withValues(alpha: .12),
          _ => cs.onSurface.withValues(alpha: .06),
        };
    return SizedBox(
      height: kLifeVizHeight,
      child: Column(children: [
        for (final (i, m) in const ['midi', 'soir'].indexed) ...[
          if (i > 0) const SizedBox(height: 4),
          Expanded(
            child: Row(children: [
              for (final (j, d) in days.indexed) ...[
                if (j > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: color(cell(mealKey(d, m))),
                      borderRadius: BorderRadius.circular(4),
                      border: mealKey(d, m) == nowKey
                          ? Border.all(color: cs.onSurface.withValues(alpha: .85), width: 1.2)
                          : (cell(mealKey(d, m)) == MealCell.other ? Border.all(color: _kAmber.withValues(alpha: .6), width: 1) : null),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _bars(List<double> values, Color c, ColorScheme cs) => SizedBox(
        height: kLifeVizHeight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, v) in values.indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: v <= 0 ? 3 : kLifeVizHeight * v,
                decoration: BoxDecoration(color: v <= 0 ? cs.onSurface.withValues(alpha: .08) : c, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        ]),
      );
}

/// ① Le cumul de la fenêtre (trait plein, aire claire) face à la droite attendue (pointillés) ;
/// les jours à venir en fond plus clair.
class _CumulPainter extends CustomPainter {
  final CumulChart c;
  final Color color;
  final Color ink;
  _CumulPainter(this.c, this.color, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final n = c.windowDays;
    final mx = c.scaleMax.toDouble();
    double x(int i) => size.width * i / n;
    double y(num v) => size.height - 2 - (size.height - 6) * (v / mx);
    final past = c.cumul.length;
    canvas.drawRect(Rect.fromLTWH(x(past), 0, size.width - x(past), size.height), Paint()..color = ink.withValues(alpha: .05));
    if (c.perDay > 0) {
      final dash = Paint()
        ..color = ink.withValues(alpha: .45)
        ..strokeWidth = 1.4;
      final end = Offset(size.width, y(c.perDay * n));
      final start = Offset(0, y(0));
      const seg = 4.0;
      final len = (end - start).distance;
      for (var t = 0.0; t < len; t += seg * 2) {
        final a = start + (end - start) * (t / len);
        final b = start + (end - start) * ((t + seg).clamp(0, len) / len);
        canvas.drawLine(a, b, dash);
      }
    }
    final pts = [Offset(0, y(0)), for (var i = 0; i < past; i++) Offset(x(i + 1), y(c.cumul[i]))];
    final area = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(pts.last.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: .18));
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(pts.last, 3.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CumulPainter o) => o.c.cumul.join(',') != c.cumul.join(',') || o.c.perDay != c.perDay || o.color != color;
}
