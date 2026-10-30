import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/fiche_cache.dart';
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show EngagementStat, ymdOf;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show showModeSheet;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';
import 'package:productivitwo_v1/utils/held_weeks.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart' show kBadgeBrass, kBadgeLockedBand, kBadgeLockedRim, kBadgeGaugeFill, kFrozenColor;
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/status_row.dart';

/// Onglet Stats « une carte, une fiche » (lot 3, 2026-10) : la carte MA
/// SEMAINE (anneau = engagements des objectifs tenus, chrono de la semaine),
/// une ligne par domaine (temps fait / minimum vital avec le repère « attendu
/// à ce jour », routines tenues), et la fiche « Ma semaine » qui reprend les
/// lectures détaillées (jauges du jour, courbe de la semaine, élan, temps).
/// La fiche d'un domaine reste la feuille existante (`onOpenDomain`).
class WeekStatsView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Future<bool?> Function(Domain domain, {String focus}) onOpenDomain;
  final VoidCallback onManageDomains;
  /// Centre de badges (facultatif) : programmes pour la ligne Élan et la feuille du mode.
  final BadgeCenter? badges;
  const WeekStatsView({
    super.key,
    required this.logic,
    required this.sync,
    required this.onOpenDomain,
    required this.onManageDomains,
    this.badges,
  });

  @override
  State<WeekStatsView> createState() => _WeekStatsViewState();
}

class _WeekStatsViewState extends State<WeekStatsView> {
  static List<StrategicObjective>? _cache;
  List<StrategicObjective> _objectives = const [];
  List<DailySchedule> _schedules = const [];

  @override
  void initState() {
    super.initState();
    _objectives = _cache ?? const [];
    final bc = widget.badges;
    if (bc != null) {
      bc.load().then((_) {
        if (mounted) setState(() => _schedules = bc.schedules);
      }).catchError((_) {});
    } else {
      final now = DateTime.now();
      widget.sync.fetchDailySchedulesRange(ymdOf(now.subtract(const Duration(days: 8))), ymdOf(now)).then((s) {
        if (mounted) setState(() => _schedules = s);
      }).catchError((_) {});
    }
    widget.sync.fetchStrategicObjectives().then((all) {
      if (!mounted) return;
      _cache = all;
      FicheCache.objectives = all;
      setState(() => _objectives = all);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = widget.logic.state;
    final now = DateTime.now();
    final week = weekSummary(
        activities: st.activeActivities, hits: st.habitHits, sessions: st.sessions, objectives: _objectives, now: now);
    final days = widget.logic.budgetWindowDays;
    final rows = domainWeeks(
        domains: st.activeDomains, activities: st.activeActivities, sessions: st.sessions, hits: st.habitHits, now: now, rest: widget.logic.restDomains, windowDays: days);
    // Temps par jour et par domaine sur la fenêtre (mêmes données que « Répartition »).
    final perDay = dailyMinutesByDomain(st.sessions, st.activeActivities, budgetWindowStart(now, days), days, now: now);
    final todayIdx = budgetDayIndex(now, days) - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Onglet « Domaines » (ex-Stats, 2026-10-30) : une liste, une fiche.
        Row(children: [
          Expanded(child: Text('Domaines', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface))),
          TextButton(onPressed: widget.onManageDomains, child: const Text('Gérer')),
        ]),
        const SizedBox(height: 8),
        _weekLine(cs, week, now,
            heldWeeks(
                activities: st.activities,
                hits: st.habitHits,
                objectives: _objectives,
                now: now,
                dayStartMin: widget.logic.dayStartMin,
                frozenOf: (a) => widget.logic.frozenOf(a.id))),
        ListSectionTitle('${days == 14 ? 'SUR 14 JOURS' : 'CETTE SEMAINE'} · ${rows.length}'),
        for (final r in rows) _domainRow(cs, r, perDay[r.domain.id], todayIdx, days),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Aucun domaine : crée-en un avec « Gérer ».', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .5))),
          ),
      ]),
    );
  }

  /// MA SEMAINE en une ligne (2026-10-30) : « 5 / 6 au rythme · 5 semaines
  /// tenues », l'élan, les sept jours en petit ; tap = fiche Ma semaine.
  Widget _weekLine(ColorScheme cs, WeekSummary w, DateTime now, HeldWeeks hw) {
    final pct = w.engagements.isEmpty ? null : w.pct;
    const days = ['LUNDI', 'MARDI', 'MERCREDI', 'JEUDI', 'VENDREDI', 'SAMEDI', 'DIMANCHE'];
    final n = w.engagements.length;
    final maxHits = w.dayHits.fold<int>(1, (m, v) => v > m ? v : m);
    final elan = _elanMean(now);
    final muted = cs.onSurface.withValues(alpha: .55);
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openWeekFiche(w, hw),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('MA SEMAINE · ${days[now.weekday - 1]}', style: TextStyle(fontSize: 10.5, letterSpacing: .6, fontWeight: FontWeight.w700, color: muted))),
              GestureDetector(
                onTap: () => showModeSheet(context, widget.logic, badges: widget.badges),
                child: Text(elan == null ? 'Élan' : 'Élan $elan / 5', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .75))),
              ),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(pct == null ? 'Pas d\'engagement' : '${w.kept} / $n au rythme',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pct == null ? muted : cs.onSurface)),
              const SizedBox(width: 10),
              if (hw.current > 0)
                Text('${hw.current} semaine${hw.current > 1 ? 's' : ''} tenue${hw.current > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBadgeBrass)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: muted),
            ]),
            if (n > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 22,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: i < w.daysElapsed ? (3 + 19 * (w.dayHits[i] / maxHits)).clamp(3.0, 22.0) : 3,
                        decoration: BoxDecoration(
                          color: i < w.daysElapsed ? kPalierGreen.withValues(alpha: i == w.daysElapsed - 1 ? .45 : 1) : cs.onSurface.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(2),
                          border: i == w.daysElapsed - 1 ? Border.all(color: kPalierGreen) : null,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// SEMAINES TENUES (lot 2, 2026-10-30) : la série, les 10 dernières semaines
  /// (tenue · sous 80 % · en veille · en cours) et ce qu'il reste cette semaine.
  Widget _heldWeeksStrip(ColorScheme cs, HeldWeeks hw) {
    final last = hw.weeks.length > 10 ? hw.weeks.sublist(hw.weeks.length - 10) : hw.weeks;
    final muted = cs.onSurface.withValues(alpha: .55);
    final w = hw.thisWeek;
    final pct = w?.pct == null ? null : (w!.pct! * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text('SEMAINES TENUES', style: TextStyle(fontSize: 10.5, letterSpacing: .6, fontWeight: FontWeight.w700, color: muted))),
          Text('${hw.current}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kBadgeBrass)),
          const SizedBox(width: 5),
          Text('d’affilée${hw.longest > hw.current ? ' · record ${hw.longest}' : ''}', style: TextStyle(fontSize: 12, color: muted)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < last.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _weekCell(last[i])),
          ],
          for (var i = last.length; i < 10; i++) ...[const SizedBox(width: 4), const Expanded(child: SizedBox())],
        ]),
        if (pct != null) ...[
          const SizedBox(height: 6),
          Text(
            hw.missing == 0
                ? 'Cette semaine : $pct % du contrat · tenue, une braise dimanche soir'
                : 'Cette semaine : $pct % du contrat · encore ${hw.missing} coche${hw.missing > 1 ? 's' : ''} d’ici dimanche',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ]),
    );
  }

  Widget _weekCell(HeldWeek w) {
    final (Color? fill, Color border) = switch (w.state) {
      WeekState.held => (kBadgeBrass, kBadgeBrass),
      WeekState.missed => (kBadgeLockedBand, kBadgeLockedRim),
      WeekState.current => (kBadgeGaugeFill.withValues(alpha: .18), kBadgeGaugeFill),
      WeekState.neutral => w.rest ? (kFrozenColor.withValues(alpha: .22), kFrozenColor) : (null, kBadgeLockedRim),
    };
    return Container(
      height: 16,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3), border: Border.all(color: border, width: w.state == WeekState.current ? 1.5 : 1)),
    );
  }

  /// Élan moyen de la semaine (pondéré par le temps tenu), « 2,9 » ; null sans pointage.
  String? _elanMean(DateTime now) {
    final st = widget.logic.state;
    final byYmd = {for (final s in _schedules) s.date: s};
    final days = buildElanDays(
      marks: widget.logic.elanMarksWithRecharge(byYmd),
      schedulesByYmd: byYmd,
      hits: st.habitHits,
      activities: st.activities,
      now: now,
      dayStartMin: widget.logic.dayStartMin,
    );
    final m = elanMetrics(days);
    if (m.count == 0) return null;
    return m.mean.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Ligne Élan (2026-10) : moyenne des 7 jours, pointages, face à la flemme,
  /// créneau difficile, mini-courbe par jour. Tap = la feuille du mode.
  /// Les jours de la fenêtre sous la barre d'un domaine : hauteur = temps du
  /// jour (échelle propre au domaine), aujourd'hui plus vif, jours à venir en filet.
  Widget _dayBars(ColorScheme cs, Color color, List<int>? mins, int today, int days) {
    final m = mins ?? List<int>.filled(days, 0);
    final max = m.fold<int>(60, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days; i++) ...[
          if (i > 0) SizedBox(width: days > 7 ? 2 : 4),
          Expanded(
            child: Container(
              height: i > today ? 2 : (3 + 19 * m[i] / max).clamp(3.0, 22.0),
              decoration: BoxDecoration(
                color: i > today ? cs.onSurface.withValues(alpha: .10) : color.withValues(alpha: m[i] == 0 ? .15 : (i == today ? 1 : .6)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _domainRow(ColorScheme cs, DomainWeek r, List<int>? perDay, int today, int days) {
    final color = domainColor(r.domain.id, widget.logic.state.activeDomains) ?? cs.primary;
    final restUntil = r.restUntil == null ? null : DateTime.tryParse(r.restUntil!);
    final sub = <String>[
      if (r.resting) 'en veille${restUntil == null ? '' : ' jusqu\'au ${dayMonthFr(restUntil)}'} · minimum suspendu',
      r.hasGoal
          ? '${fmtMin(r.doneMin)} · minimum ${fmtMin(r.weekMin)}${r.windowDays == 14 ? ' sur 14 j' : ''} · attendu ${fmtMin(r.expectedMin)}'
          : (r.doneMin > 0 ? '${fmtMin(r.doneMin)} ${r.windowDays == 14 ? 'sur 14 j' : 'cette semaine'}' : (r.resting ? '' : 'pas de temps tracé')),
      if (r.routinesTotal > 0) '${r.routinesReached} / ${r.routinesTotal} routine${r.routinesTotal > 1 ? 's' : ''} au rythme',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        title: r.domain.name,
        sub: sub.split(' · ').where((x) => x.isNotEmpty).join(' · '),
        bar: r.hasGoal ? (done: r.doneMin, total: r.weekMin, expected: r.expectedMin) : null,
        pct: r.pctInt,
        muted: r.resting,
        chip: r.resting ? 'en veille' : null,
        delta: r.hasGoal ? '${r.pctInt} %' : null,
        trailing: r.hasGoal || r.resting ? null : Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)),
        onTap: () => widget.onOpenDomain(r.domain, focus: 'time'),
        onLongPress: r.routinesTotal > 0 ? () => widget.onOpenDomain(r.domain, focus: 'habit') : null,
        below: _dayBars(cs, color, perDay, today, days),
      ),
    );
  }

  /// Fiche « Ma semaine » (2026-10-30, le contrat seul) : les engagements à ce
  /// jour (attendu au prorata + rappel de la semaine entière) puis les semaines
  /// tenues. Répartition, jauges, temps, élan et retards vivent ailleurs
  /// (lignes de domaine, Aujourd'hui, fiche d'activité, feuille du mode, Actions).
  /// Ordre « au plus près de la cible » (`comparePct`) : sous l'attendu à ce
  /// jour, le plus proche en tête ; à l'attendu ou au-delà, en ordre croissant.
  /// Pourcentage NON plafonné, pour départager ce qui dépasse.
  List<EngagementStat> _byNearest(WeekSummary w) {
    int pctOf(EngagementStat e) {
      final x = w.expectedOf(e);
      return x <= 0 ? 100 : (e.done / x * 100).round();
    }
    return [...w.engagements]..sort((a, b) => comparePct(pctOf(a), pctOf(b)));
  }

  void _openWeekFiche(WeekSummary w, HeldWeeks hw) {
    final pct = w.engagements.isEmpty ? null : w.pct;
    final n = w.engagements.length;
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            FicheHeader(
              title: 'Ma semaine',
              chip: pct == null ? 'sans engagement' : '$pct % du rythme',
              chipColor: pct == null ? kPalierMuted : palierColor(pct),
              kpi: 'Jour ${w.daysElapsed} / 7${w.chronoMin > 0 ? ' · ${fmtMin(w.chronoMin)} de chrono' : ''}',
            ),
            FicheTitle(w.fromObjectives ? 'ENGAGEMENTS DES OBJECTIFS · À CE JOUR' : 'ROUTINES DE LA SEMAINE · À CE JOUR',
                trailing: n == 0 ? null : FicheDelta('${w.kept} / $n au rythme', color: palierColor(pct ?? 0))),
            if (n == 0)
              const FicheNote('Rattache des routines à un objectif pour que la semaine les juge ; sinon toutes les routines comptent.')
            else ...[
              for (final e in _byNearest(w)) ...[
                FicheStep(
                  title: e.label,
                  detail: '${e.done} / ${w.expectedOf(e)} attendu${w.expectedOf(e) > 1 ? 's' : ''} à ce jour · ${e.target} sur la semaine',
                  done: w.onTrack(e),
                  trailing: Text('${(w.ratioOf(e) * 100).round()} %',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palierColor((w.ratioOf(e) * 100).round()))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: ExpectedBar(done: e.done, total: e.target, expected: w.expectedOf(e), color: palierColor((w.ratioOf(e) * 100).round()), height: 6),
                ),
              ],
              FicheNote(
                  'Attendu au prorata du jour (jour ${w.daysElapsed} / 7). Semaine entière : ${w.pctWeek} % · ${w.keptWeek} / $n tenu${w.keptWeek > 1 ? 's' : ''}.'),
            ],
            if (hw.weeks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _heldWeeksStrip(cs, hw),
            ],
          ],
        );
      });
    });
  }
}
