import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
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
  /// Lectures détaillées, construites par l'appelant (jauges + courbe, élan,
  /// temps, camembert, retards) : affichées dans la fiche « Ma semaine ».
  final List<Widget> Function(BuildContext ctx) weekDetails;
  const WeekStatsView({
    super.key,
    required this.logic,
    required this.sync,
    required this.onOpenDomain,
    required this.onManageDomains,
    required this.weekDetails,
  });

  @override
  State<WeekStatsView> createState() => _WeekStatsViewState();
}

class _WeekStatsViewState extends State<WeekStatsView> {
  static List<StrategicObjective>? _cache;
  List<StrategicObjective> _objectives = const [];

  @override
  void initState() {
    super.initState();
    _objectives = _cache ?? const [];
    widget.sync.fetchStrategicObjectives().then((all) {
      if (!mounted) return;
      _cache = all;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _weekCard(cs, week, now),
        ListSectionTitle(days == 14 ? 'DOMAINES · SUR 14 JOURS' : 'DOMAINES · CETTE SEMAINE', action: 'Gérer', onAction: widget.onManageDomains),
        for (final r in rows) _domainRow(cs, r),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Aucun domaine : crée-en un avec « Gérer ».', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .5))),
          ),
      ]),
    );
  }

  Widget _weekCard(ColorScheme cs, WeekSummary w, DateTime now) {
    final pct = w.engagements.isEmpty ? null : w.pct;
    final st = pct == null ? kPalierMuted : palierColor(pct);
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    final sub = <String>[
      if (w.chronoMin > 0) '${fmtMin(w.chronoMin)} de chrono',
      if (w.engagements.isNotEmpty) '${w.kept} / ${w.engagements.length} engagement${w.engagements.length > 1 ? 's' : ''} tenu${w.kept > 1 ? 's' : ''}',
      if (w.engagements.isEmpty) 'aucune routine engagée',
    ].join(' · ');
    final mode = widget.logic.mode;
    final modeLine = switch (mode) { DayMode.low => 'journée malgré tout · ', DayMode.high => 'journée à fond · ', DayMode.normal => '' };
    return MomentCard(
      accent: kPalierGreen,
      eyebrow: 'MA SEMAINE',
      pill: '${days[now.weekday - 1]} · jour ${w.daysElapsed} / 7',
      ring: pct == null ? 0 : pct / 100,
      ringColor: st,
      ringBig: pct == null ? '—' : '$pct %',
      ringSmall: 'TENUS',
      context_: w.fromObjectives ? 'Engagements des objectifs' : 'Toutes les routines de la semaine',
      contextIcon: Icons.flag_rounded,
      title: pct == null
          ? 'Pas d\'engagement cette semaine'
          : pct >= 85
              ? 'Semaine au rythme'
              : pct >= 60
                  ? 'Semaine à tenir'
                  : 'Semaine en retard',
      sub: modeLine + sub,
      subColor: pct != null && pct < 60 ? st : null,
      primaryLabel: 'Détail de la semaine',
      primaryIcon: Icons.insights_rounded,
      onPrimary: () => _openWeekFiche(w),
    );
  }

  /// Répartition du chrono par domaine et par jour sur la fenêtre de budget
  /// (Modes et coups lot 4) : une barre par jour, le repère du jour courant.
  Widget _distribution(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final st = widget.logic.state;
    final now = DateTime.now();
    final days = widget.logic.budgetWindowDays;
    final start = budgetWindowStart(now, days);
    final data = dailyMinutesByDomain(st.sessions, st.activeActivities, start, days, now: now);
    final domains = st.activeDomains.where((d) => data.containsKey(d.id)).toList();
    if (domains.isEmpty) {
      return FicheNote(days == 14
          ? 'Rien de tracé sur la quinzaine. Avec 14 jours, pousser 3 jours sur un sujet puis le lâcher reste « au rythme ».'
          : 'Rien de tracé cette semaine. Dans Paramètres, « Budget des minimums » passe la fenêtre à 14 jours.');
    }
    final today = budgetDayIndex(now, days) - 1;
    var max = 1;
    for (final row in data.values) {
      for (final v in row) {
        if (v > max) max = v;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final d in domains)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: domainColor(d.id, st.activeDomains) ?? cs.primary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Text(fmtMin(data[d.id]!.fold(0, (a, b) => a + b)),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6), fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < days; i++) ...[
                  Expanded(
                    child: Container(
                      height: (4 + 24 * data[d.id]![i] / max).clamp(4.0, 28.0),
                      decoration: BoxDecoration(
                        color: i > today
                            ? Colors.transparent
                            : (domainColor(d.id, st.activeDomains) ?? cs.primary).withValues(alpha: data[d.id]![i] == 0 ? .15 : (i == today ? 1 : .7)),
                        borderRadius: BorderRadius.circular(2),
                        border: i > today ? Border.all(color: cs.onSurface.withValues(alpha: .08)) : null,
                      ),
                    ),
                  ),
                  if (i < days - 1) const SizedBox(width: 2),
                ],
              ]),
            ),
          ]),
        ),
      Row(children: [
        Text('jour 1', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
        const Spacer(),
        Text('jour $days', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: .45))),
      ]),
    ]);
  }

  Widget _domainRow(ColorScheme cs, DomainWeek r) {
    final color = domainColor(r.domain.id, widget.logic.state.activeDomains) ?? cs.primary;
    final restUntil = r.restUntil == null ? null : DateTime.tryParse(r.restUntil!);
    final sub = <String>[
      if (r.resting) 'en veille${restUntil == null ? '' : ' jusqu\'au ${dayMonthFr(restUntil)}'} · minimum suspendu',
      r.hasGoal
          ? '${fmtMin(r.doneMin)} · minimum ${fmtMin(r.weekMin)}${r.windowDays == 14 ? ' sur 14 j' : ''} · attendu ${fmtMin(r.expectedMin)}'
          : (r.doneMin > 0 ? '${fmtMin(r.doneMin)} ${r.windowDays == 14 ? 'sur 14 j' : 'cette semaine'}' : (r.resting ? '' : 'pas de temps tracé')),
      if (r.routinesTotal > 0) '${r.routinesReached} / ${r.routinesTotal} routine${r.routinesTotal > 1 ? 's' : ''}',
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
      ),
    );
  }

  /// Fiche « Ma semaine » : engagements, puis les lectures détaillées de
  /// l'ancien onglet (jauges du jour + courbe de la semaine, élan, temps).
  void _openWeekFiche(WeekSummary w) {
    final pct = w.engagements.isEmpty ? null : w.pct;
    showFiche<void>(context, builder: (ctx, scroll) {
      final cs = Theme.of(ctx).colorScheme;
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          FicheHeader(
            title: 'Ma semaine',
            chip: pct == null ? 'sans engagement' : '$pct % tenus',
            chipColor: pct == null ? kPalierMuted : palierColor(pct),
            kpi: 'Jour ${w.daysElapsed} / 7${w.chronoMin > 0 ? ' · ${fmtMin(w.chronoMin)} de chrono' : ''}',
          ),
          FicheTitle(w.fromObjectives ? 'ENGAGEMENTS DES OBJECTIFS' : 'ROUTINES DE LA SEMAINE',
              trailing: w.engagements.isEmpty ? null : FicheDelta('${w.kept} / ${w.engagements.length} tenus', color: palierColor(pct ?? 0))),
          if (w.engagements.isEmpty)
            const FicheNote('Rattache des routines à un objectif pour que la semaine les juge ; sinon toutes les routines comptent.')
          else
            for (final e in w.engagements)
              FicheStep(
                title: e.label,
                detail: '${e.done} / ${e.target} · ${(e.ratio * 100).round()} %',
                done: e.kept,
                trailing: Text('${(e.ratio * 100).round()} %',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palierColor((e.ratio * 100).round()))),
              ),
          FicheTitle('RÉPARTITION SUR ${widget.logic.budgetWindowDays} J',
              trailing: FicheDelta(budgetWindowLabel(DateTime.now(), widget.logic.budgetWindowDays), color: cs.onSurface.withValues(alpha: .6))),
          _distribution(ctx),
          const FicheTitle('AUJOURD\'HUI ET LA SEMAINE'),
          ...widget.weekDetails(ctx),
          const SizedBox(height: 8),
          Text('Les lectures détaillées vivent ici ; l\'onglet garde l\'essentiel.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .45))),
        ],
      );
    });
  }
}
