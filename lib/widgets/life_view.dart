import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/run_session_store.dart' show RunSessionStore;
import 'package:productivitwo_v1/utils/domain_colors.dart' show domainColor;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/guerilla.dart' show kGuerillaKind;
import 'package:productivitwo_v1/utils/life_natures.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/meal_day.dart' show mealWeekView, currentMealMoment;
import 'package:productivitwo_v1/utils/meal_plan.dart' show mealKey;
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/offensive.dart' show kOffensiveKind;
import 'package:productivitwo_v1/utils/sleep_stats.dart';
import 'package:productivitwo_v1/utils/sport_stats.dart';
import 'package:productivitwo_v1/utils/week_stats.dart' show domainWeeks, DomainWeek, weekSummary;
import 'package:productivitwo_v1/utils/budget_window.dart' show dailyMinutesByDomain;
import 'package:productivitwo_v1/widgets/badge_gallery_screen.dart' show showBadgeGallerySheet;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/guerilla_screen.dart' show kGuerillaAccent, showGuerillaScreen;
import 'package:productivitwo_v1/widgets/meal_sheet.dart' show showMealSheet;
import 'package:productivitwo_v1/widgets/finance_sheet.dart' show kMoneyAccent, showFinanceSheet;
import 'package:productivitwo_v1/utils/finances.dart' show euros, monthSummary, trackedDays;
import 'package:productivitwo_v1/widgets/objective_trajectory_sheet.dart' show showObjectiveTrajectorySheet;
import 'package:productivitwo_v1/widgets/objectives_card.dart';
import 'package:productivitwo_v1/widgets/offensive_screen.dart' show kOffensiveAccent, showOffensiveScreen;
import 'package:productivitwo_v1/widgets/sniper_screen.dart' show kSniperAccent, showSniperScreen;
import 'package:productivitwo_v1/utils/sniper.dart' show kSniperKind;
import 'package:productivitwo_v1/widgets/plan_screen.dart' show kPlanAccent, showPlanScreen;
import 'package:productivitwo_v1/widgets/season_view.dart' show SeasonTile;
import 'package:productivitwo_v1/widgets/sport_sheet.dart' show showSportSheet;
import 'package:productivitwo_v1/widgets/week_review_screen.dart' show kReviewAccent, showWeekReviewScreen;
import 'package:productivitwo_v1/widgets/week_stats_view.dart';

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
const kLifeTileHeight = 172.0;

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

  Future<void> _run(String kind) async {
    final p = RunSessionStore.current;
    final pending = p != null && p.kind == kind && p.isLive(DateTime.now(), logic.livedTodayYmd) ? p : null;
    if (kind == kGuerillaKind) {
      await showGuerillaScreen(context, logic, resume: pending);
    } else if (kind == kSniperKind) {
      await showSniperScreen(context, logic, badges: widget.badges, resume: pending);
    } else {
      await showOffensiveScreen(context, logic, resume: pending);
    }
    if (mounted) setState(() {});
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

    Widget launcher(String label, IconData icon, Color c, VoidCallback onTap, {bool dot = false}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: .14), border: Border.all(color: c.withValues(alpha: .7), width: 1.5)),
                    child: Icon(icon, color: c, size: 22),
                  ),
                  if (dot) Positioned(right: 0, top: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                ]),
                const SizedBox(height: 5),
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: mute)),
              ]),
            ),
          ),
        );
    final pending = RunSessionStore.current;
    bool live(String kind) => pending != null && pending.kind == kind && pending.isLive(now, logic.livedTodayYmd);

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
          Expanded(child: Text('Ma vie', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface))),
          TextButton(onPressed: widget.onManageDomains, child: const Text('Gérer')),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(_sentence(now, weeks), style: TextStyle(fontSize: 15.5, height: 1.35, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: .85))),
        ),
        _section(mute, 'MES MODES'),
        Row(children: [
          launcher('Guérilla', Icons.bolt_rounded, kGuerillaAccent, () => _run(kGuerillaKind), dot: live(kGuerillaKind)),
          launcher('Sniper', Icons.gps_fixed, kSniperAccent, () => _run(kSniperKind), dot: live(kSniperKind)),
          launcher('Offensive', Icons.north_east_rounded, kOffensiveAccent, () => _run(kOffensiveKind), dot: live(kOffensiveKind)),
          launcher('Planifier', Icons.explore_outlined, kPlanAccent, () => showPlanScreen(context, logic, badges: widget.badges)),
          launcher('Revue', Icons.event_repeat_rounded, kReviewAccent, () => showWeekReviewScreen(context, logic, badges: widget.badges)),
        ]),
        _section(mute, 'CETTE SEMAINE'),
        WeekStatsView(logic: logic, sync: widget.sync, badges: widget.badges, onOpenDomain: (d, {focus = 'time'}) => widget.onOpenDomain(d), onManageDomains: widget.onManageDomains, onlyWeekLine: true),
        _section(mute, 'MES DOMAINES', right: 'appui long = nature'),
        LayoutBuilder(builder: (ctx, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
        if (orphan.isNotEmpty) ...[
          _section(mute, 'OBJECTIFS SANS DOMAINE'),
          for (final o in orphan) _objectiveLine(cs, o, progress[o.id], cs.primary),
        ],
        const SizedBox(height: 14),
        Row(children: [
          if (widget.badges case final bc?) ...[
            Expanded(child: SeasonTile(logic: logic, center: bc)),
            const SizedBox(width: 8),
            Expanded(
              child: _smallTile(cs, 'BADGES', ListenableBuilder(
                listenable: bc,
                builder: (_, __) => Text(bc.deck == null ? '…' : '${bc.deck!.acquired} / ${bc.deck!.total} ›', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ), () => showBadgeGallerySheet(context, logic: logic, sync: widget.sync, center: bc)),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: _smallTile(cs, 'OBJECTIFS', Text('${active.length} actifs ›', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), _openAllObjectives)),
        ]),
      ]),
    );
  }

  String _sentence(DateTime now, Map<String, DomainWeek> weeks) {
    final st = logic.state;
    final w = weekSummary(activities: st.activeActivities, hits: st.habitHits, sessions: st.sessions, objectives: _objectives.where((o) => o.status == 'active'), now: now);
    final natures = {for (final d in st.activeDomains) d.id: _natureOf(d)};
    int? sleepAvg;
    var target = 450;
    if (natures.values.contains(DomainNature.night)) {
      final nights = sleepNightList(sessions: st.sessions, activities: st.activities, now: now, dayStartMin: logic.dayStartMin, nights: 7);
      target = sleepTargetMin(sleepActivityOf(st.activities));
      sleepAvg = sleepStats(nights, target).avgMin;
    }
    int? sport;
    if (natures.values.contains(DomainNature.sessions)) {
      final pick = resolveSportPick(st.activities, st.domains, logic.sportOverrides);
      final today = ymdOf(livedDate(now, logic.dayStartMin));
      sport = sportDays(pick: pick, sessions: st.sessions, hits: st.habitHits, fromYmd: mondayOf(today), toYmd: today, now: now, dayStartMin: logic.dayStartMin)
          .fold<int>(0, (s, x) => s + x.sessions);
    }
    final behind = [
      for (final d in st.activeDomains)
        if (weeks[d.id] case final r? when r.hasGoal && !r.resting && r.expectedMin > 0 && r.doneMin < r.expectedMin * .7 && !{DomainNature.night, DomainNature.meals, DomainNature.money}.contains(natures[d.id]))
          d.name,
    ];
    return lifeSentence(kept: w.kept, engagements: w.engagements.length, sleepAvgMin: sleepAvg, sleepTargetMin: target, sportSessions: sport, behindDomains: behind);
  }

  Widget _section(Color mute, String t, {String? right}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
          if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
        ]),
      );

  Widget _smallTile(ColorScheme cs, String eyebrow, Widget child, VoidCallback onTap) => Material(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .7, color: cs.onSurface.withValues(alpha: .55))),
              const SizedBox(height: 4),
              child,
            ]),
          ),
        ),
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
        viz = _bars([for (final x in nights) x == null ? 0.0 : (x.minutes / 540).clamp(0.05, 1.0)], c, cs);
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
        onTap = () => showSportSheet(context, logic: logic, sync: widget.sync);
      case DomainNature.meals:
        final t = logic.livedToday;
        final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
        final days = [for (var i = 0; i < 7; i++) ymdOf(DateTime(monday.year, monday.month, monday.day + i))];
        final week = logic.mealWeek(days.first);
        final v = mealWeekView(days: days, week: week, activities: st.activities, hits: st.habitHits, sessions: st.sessions, now: now, dayStartMin: logic.dayStartMin);
        final moment = currentMealMoment(now);
        final next = week.slots[mealKey(ymdOf(t), moment)];
        eyebrow = 'REPAS';
        value = v.counted == 0 ? 'Repas' : '${v.balanced} / ${v.counted}';
        sub = next != null ? '${moment == 'midi' ? 'ce midi' : 'ce soir'} : ${next.title}' : (v.counted == 0 ? 'menu, plats, courses' : 'repas équilibrés');
        // Une barre par jour de la semaine : repas équilibrés (0, 1 ou 2).
        viz = _bars([
          for (final d in days)
            () {
              final ok = ['midi', 'soir'].where((m) => v.cells[mealKey(d, m)]?.name == 'ok').length;
              return ok / 2;
            }(),
        ], c, cs);
        onTap = () => showMealSheet(context, logic: logic, sync: widget.sync);
      case DomainNature.money:
        final f = logic.finances;
        final today = logic.livedTodayYmd;
        final m = monthSummary(f, today);
        final t = DateTime.parse(today);
        final from = ymdOf(DateTime(t.year, t.month, t.day - 89));
        final tracked = trackedDays(f).where((y) => y.compareTo(from) >= 0 && y.compareTo(today) <= 0).length;
        eyebrow = 'FINANCES';
        value = m.hasIncome ? euros(m.remaining) : (m.spent > 0 ? euros(m.spent) : 'Finances');
        sub = m.hasIncome ? 'reste à vivre · $tracked / 90 jours suivis' : (m.spent > 0 ? 'dépensés ce mois · $tracked / 90 suivis' : 'note tes dépenses, jour après jour');
        // 7 derniers jours : la dépense de chaque jour ; un jour « rien dépensé » = petit trait.
        final spentDays = [
          for (var i = 6; i >= 0; i--)
            () {
              final y = ymdOf(DateTime(t.year, t.month, t.day - i));
              return f.expenses.values.where((x) => x.ymd == y).fold<int>(0, (s, x) => s + x.amount);
            }(),
        ];
        final maxSpent = spentDays.fold<int>(0, (a, b) => a > b ? a : b);
        viz = _bars([
          for (var i = 0; i < 7; i++)
            spentDays[i] > 0
                ? (spentDays[i] / maxSpent).clamp(0.08, 1.0)
                : (f.nothing.contains(ymdOf(DateTime(t.year, t.month, t.day - 6 + i))) ? 0.05 : 0.0),
        ], c, cs);
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
              child: objs.isEmpty
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

  Widget _bars(List<double> values, Color c, ColorScheme cs) => SizedBox(
        height: 28,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (i, v) in values.indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: v <= 0 ? 3 : 28 * v,
                decoration: BoxDecoration(color: v <= 0 ? cs.onSurface.withValues(alpha: .08) : c, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        ]),
      );
}
