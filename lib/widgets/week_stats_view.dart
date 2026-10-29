import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/elan_view.dart' show fmtElan, hardestBucket;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/widgets/elan_rows.dart' show elanColor;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show showModeSheet;
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
import 'package:shared_preferences/shared_preferences.dart';

/// Section nommée de la fiche « Ma semaine » (repliable).
typedef WeekDetailSection = ({String title, Widget child});

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
  /// temps, camembert, retards) : sections repliables de la fiche « Ma semaine ».
  final List<WeekDetailSection> Function(BuildContext ctx) weekDetails;
  /// Centre de badges (facultatif) : programmes pour la ligne Élan et la feuille du mode.
  final BadgeCenter? badges;
  const WeekStatsView({
    super.key,
    required this.logic,
    required this.sync,
    required this.onOpenDomain,
    required this.onManageDomains,
    required this.weekDetails,
    this.badges,
  });

  @override
  State<WeekStatsView> createState() => _WeekStatsViewState();
}

class _WeekStatsViewState extends State<WeekStatsView> {
  static List<StrategicObjective>? _cache;
  static const _kOpenKey = 'week_fiche_open';
  List<StrategicObjective> _objectives = const [];
  /// Sections de la fiche ouvertes (titres) ; ENGAGEMENTS l'est toujours.
  Set<String> _open = {};
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
    SharedPreferences.getInstance().then((p) {
      final v = p.getStringList(_kOpenKey);
      if (v != null && mounted) setState(() => _open = v.toSet());
    });
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
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final n = w.engagements.length;
    final mode = widget.logic.mode;
    final modeLine = switch (mode) { DayMode.low => 'journée malgré tout', DayMode.high => 'journée à fond', DayMode.normal => null };
    // Grammaire de Projets (2026-10) : le titre est le chiffre qui compte, la
    // semaine se voit jour par jour, l'élan remonte en lien.
    final behind = w.engagements.where((e) => !w.onTrack(e)).length;
    final maxHits = w.dayHits.fold<int>(1, (m, v) => v > m ? v : m);
    final elan = _elanMean(now);
    return MomentCard(
      accent: kPalierGreen,
      eyebrow: 'MA SEMAINE',
      pill: '${days[now.weekday - 1]} · jour ${w.daysElapsed} / 7',
      ring: pct == null ? 0 : pct / 100,
      ringColor: st,
      ringBig: pct == null ? '—' : '$pct %',
      ringSmall: 'DU RYTHME',
      context_: w.fromObjectives ? 'Engagements des objectifs' : 'Toutes les routines',
      contextIcon: Icons.flag_rounded,
      title: pct == null ? 'Pas d\'engagement cette semaine' : '${w.kept} / $n au rythme',
      sub: [
        if (pct != null) 'attendu à ce jour',
        if (w.chronoMin > 0) '${fmtMin(w.chronoMin)} de chrono',
        if (modeLine != null) modeLine,
      ].join(' · '),
      subColor: pct != null && pct < 60 ? st : null,
      visual: n == 0
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 30,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: i < w.daysElapsed ? (4 + 26 * (w.dayHits[i] / maxHits)).clamp(4.0, 30.0) : 4,
                        decoration: BoxDecoration(
                          color: i < w.daysElapsed ? kPalierGreen.withValues(alpha: i == w.daysElapsed - 1 ? 1 : .75) : cs.onSurface.withValues(alpha: .10),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          border: i == w.daysElapsed - 1 ? Border.all(color: cs.onSurface.withValues(alpha: .9), width: 1.2) : null,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 3),
              Row(children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                      child: Text(letters[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: i == w.daysElapsed - 1 ? .9 : .4)))),
                ],
              ]),
              MomentLegend('Routines tenues par jour · aujourd\'hui en cours',
                  right: behind == 0 ? 'tout au rythme' : 'à rattraper : $behind'),
            ]),
      primaryLabel: 'Détail',
      primaryIcon: Icons.insights_rounded,
      onPrimary: () => _openWeekFiche(w),
      chainLabel: elan == null ? 'Élan' : 'Élan · $elan / 5',
      onChain: () => showModeSheet(context, widget.logic, badges: widget.badges),
      moreTitle: 'Ma semaine',
      moreActions: [
        MomentAction('Mode du jour', icon: Icons.wb_sunny_outlined, hint: 'flemme · normal · en forme', onTap: () => showModeSheet(context, widget.logic, badges: widget.badges)),
        MomentAction('Gérer les domaines', icon: Icons.tune_rounded, onTap: widget.onManageDomains),
      ],
    );
  }

  /// Élan moyen de la semaine (pondéré par le temps tenu), « 2,9 » ; null sans pointage.
  String? _elanMean(DateTime now) {
    final st = widget.logic.state;
    final days = buildElanDays(
      marks: st.moodMarks,
      schedulesByYmd: {for (final s in _schedules) s.date: s},
      hits: st.habitHits,
      activities: st.activities,
      now: now,
      dayStartMin: widget.logic.dayStartMin,
    );
    final m = elanMetrics(days);
    if (m.count == 0) return null;
    return m.mean.toStringAsFixed(1).replaceAll('.', ',');
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

  /// Ligne Élan (2026-10) : moyenne des 7 jours, pointages, face à la flemme,
  /// créneau difficile, mini-courbe par jour. Tap = la feuille du mode.
  Widget _domainRow(ColorScheme cs, DomainWeek r) {
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
      ),
    );
  }

  Future<void> _toggleSection(String key, void Function(void Function()) setLocal) async {
    setLocal(() => _open.contains(key) ? _open.remove(key) : _open.add(key));
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOpenKey, _open.toList());
  }

  /// Fiche « Ma semaine » (2026-10) : ENGAGEMENTS à ce jour (toujours ouvert,
  /// attendu au prorata + rappel de la semaine entière), puis des sections
  /// REPLIABLES — répartition, jauges + courbe, élan, temps, camembert,
  /// retards — au lieu des lectures empilées en vrac.
  void _openWeekFiche(WeekSummary w) {
    final pct = w.engagements.isEmpty ? null : w.pct;
    final n = w.engagements.length;
    showFiche<void>(context, builder: (ctx, scroll) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        List<Widget> section(String title, List<Widget> body, {Widget? trailing}) {
          final open = _open.contains(title);
          return [
            FicheTitle(title, trailing: trailing, expanded: open, onToggle: () => _toggleSection(title, setLocal)),
            if (open) ...body,
          ];
        }

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
              for (final e in w.engagements) ...[
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
            ...section(
              'RÉPARTITION SUR ${widget.logic.budgetWindowDays} J',
              [_distribution(ctx)],
              trailing: FicheDelta(budgetWindowLabel(DateTime.now(), widget.logic.budgetWindowDays), color: cs.onSurface.withValues(alpha: .6)),
            ),
            for (final d in widget.weekDetails(ctx)) ...section(d.title, [d.child]),
            const SizedBox(height: 8),
            Text('Touche un titre pour déplier une lecture ; l\'onglet garde l\'essentiel.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .45))),
          ],
        );
      });
    });
  }
}
