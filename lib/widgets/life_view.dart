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
import 'package:productivitwo_v1/widgets/freedom_screens.dart';

const _kNight = Color(0xFF7FB2E8);
const _kAmber = Color(0xFFF0B44C);
const _natureColors = {
  DomainNature.night: _kNight,
  DomainNature.sessions: Color(0xFFF07C4C),
  DomainNature.meals: Color(0xFF7CC96A),
  DomainNature.money: kMoneyAccent,
};
const _kNaturesPref = 'life_natures';
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
  State<LifeView> createState() => _LifeViewState();
}

class _LifeViewState extends State<LifeView> {
  AppLogic get logic => widget.logic;
  List<StrategicObjective> _objectives = FicheCache.objectives ?? const [];
  Map<String, DomainNature> _overrides = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kNaturesPref);
      if (raw != null && mounted) setState(() => _overrides = parseNatures(Map<String, dynamic>.from(jsonDecode(raw) as Map)));
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

  Future<void> _pickNature(Domain d) async {
    final cur = _natureOf(d);
    final n = await showModalBottomSheet<DomainNature>(
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
    if (n == null || n == cur) return;
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
      if (o != null && _domainOf(o) == d.id) return (s, g, o);
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

    final tiles = <Widget>[];
    for (final d in sorted) {
      final n = _natureOf(d);
      if (_natureColors.containsKey(n)) {
        if (seenSheet.contains(n)) continue;
        seenSheet.add(n);
      }
      tiles.add(_tile(cs, d, n, weeks[d.id], byDomain[d.id] ?? const [], progress, now));
    }

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
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        _freedomTile(cs, mute),
        if (orphan.isNotEmpty) ...[
          _section(mute, 'OBJECTIFS SANS DOMAINE'),
          for (final o in orphan) _objectiveLine(cs, o, progress[o.id], cs.primary),
        ],
      ]),
    );
  }

  // Liberté (2026-11-04) : une seule chose à quitter ; rien d'affiché tant qu'elle n'existe pas, sauf un lien discret.
  Widget _freedomTile(ColorScheme cs, Color mute) {
    final f = logic.freedom;
    final p = f.plan;
    if (p == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('life-freedom-start'),
          onPressed: () => showFreedomSetup(context, logic: logic).then((_) => mounted ? setState(() {}) : null),
          child: Text('Quitter une habitude ›', style: TextStyle(color: mute)),
        ),
      );
    }
    final now = DateTime.now();
    final stop = p.goal == FreedomGoal.stop;
    final head = stop ? 'libre depuis ${freeLabel(now.difference(freeSince(f)))}' : '${usedThisPeriod(f, now)} / ${p.limit ?? '?'} ${p.unit} ${p.period == FreedomPeriod.day ? "aujourd'hui" : 'cette semaine'}';
    final n = urgesOvercome(f);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const ValueKey('life-freedom'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => showFreedomSheet(context, logic: logic).then((_) => mounted ? setState(() {}) : null),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('LIBERTÉ · ${p.name.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kFreeAccent)),
                  const SizedBox(height: 2),
                  Text(head, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  Text('$n envie${n > 1 ? 's' : ''} surmontée${n > 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: mute)),
                ]),
              ),
              FilledButton(
                key: const ValueKey('life-freedom-urge'),
                style: FilledButton.styleFrom(backgroundColor: kUrgeAccent, foregroundColor: const Color(0xFF2A1606)),
                onPressed: () => showUrgeScreen(context, logic: logic).then((_) => mounted ? setState(() {}) : null),
                child: const Text("J'ai une envie", style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
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

  Widget _tile(ColorScheme cs, Domain d, DomainNature n, DomainWeek? w, List<StrategicObjective> objs, Map<String, ObjectiveProgress> progress, DateTime now) {
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
        sub = next != null ? '${moment == 'midi' ? 'ce midi' : 'ce soir'} : ${next.title}' : (v.counted == 0 ? 'menu, plats, courses' : 'repas équilibrés');
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
          if (w.resting) sub = 'en veille';
          viz = _domainDays(cs, d, w, n, now, c);
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
