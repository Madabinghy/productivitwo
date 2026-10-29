import 'package:flutter/material.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show objectiveStart;
import 'package:productivitwo_v1/widgets/badge_painter.dart';
import 'package:productivitwo_v1/widgets/badge_track_view.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Lignes de badges dans les fiches et rangée d'Objectifs (lot 3, design
/// « Badges Productivitwo », section Écrans) : badge à 40 px avec sa jauge,
/// le fait en chiffres, jamais un jugement.

String _n(num v) => v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

/// Chevron plein de 12 px, le marquage de niveau hors du badge.
class _Chevron extends StatelessWidget {
  final Color fill;
  final Color stroke;
  const _Chevron({required this.fill, required this.stroke});
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(12, 12), painter: _ChevronPainter(fill, stroke));
}

class _ChevronPainter extends CustomPainter {
  final Color fill, stroke;
  _ChevronPainter(this.fill, this.stroke);
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(1.5, 9)
      ..lineTo(6, 2.5)
      ..lineTo(10.5, 9)
      ..lineTo(10.5, 11)
      ..lineTo(6, 6)
      ..lineTo(1.5, 11)
      ..close();
    if (fill.a > 0) c.drawPath(p, Paint()..color = fill);
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round
          ..color = stroke);
  }

  @override
  bool shouldRepaint(_ChevronPainter o) => o.fill != fill || o.stroke != stroke;
}

/// Fiche routine : « Série · 34 jours », « 34 / 66 j », la rangée des cinq
/// paliers, puis « Élan moyen 2,8 · 5 victoires sur la flemme ».
class RoutineTiersLine extends StatelessWidget {
  final Activity activity;
  final List<HabitHit> hits;
  final List<MoodMark> marks;
  final int dayStartMin;
  final Color accent;
  /// Jours comblés par une braise (`AppLogic.bridgedOf`).
  final Set<String> bridged;
  const RoutineTiersLine({
    super.key,
    required this.activity,
    required this.hits,
    required this.marks,
    required this.dayStartMin,
    required this.accent,
    this.bridged = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = routineSeries(activity, hits, DateTime.now(), dayStartMin: dayStartMin, bridged: bridged);
    final level = kRoutineTiers.where((t) => s.longest >= t).length;
    final state = BadgeState(
      def: BadgeDef(id: 'serie-${activity.id}', family: BadgeFamily.routines, name: activity.name, symbol: 'flame', tiers: kRoutineTiers, unit: 'j', unitLong: 'jours', subjectId: activity.id),
      level: level,
      value: s.current,
      tierDates: s.tierDates,
    );
    final next = state.nextTarget;
    final elan = routineElanFacts(activity, marks, hits, dayStartMin: dayStartMin);
    final muted = cs.onSurface.withValues(alpha: .55);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: .08)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Opacity(opacity: state.acquired ? 1 : .6, child: BadgeView(state: state, size: 48)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Série · ${s.current} jour${s.current > 1 ? 's' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                next == null ? 'complet' : '${s.current} / $next j${s.longest > s.current ? ' · record ${s.longest}' : ''}',
                style: TextStyle(fontSize: 12.5, color: muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 0; i < kRoutineTiers.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _Chevron(
                    fill: i < level ? kBadgeChevron : Colors.transparent,
                    stroke: i < level ? kBadgeChevronDark : (i == level ? accent : cs.onSurface.withValues(alpha: .3)),
                  ),
                  const SizedBox(width: 3),
                  Text('${kRoutineTiers[i]}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: i < level ? cs.onSurface.withValues(alpha: .85) : (i == level ? accent : muted))),
                ]),
            ]),
            if (elan.count > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Élan moyen ${_n(elan.mean!)} · ${elan.victories} victoire${elan.victories > 1 ? 's' : ''} sur la flemme',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
            const SizedBox(height: 8),
            BadgeTrackView(track: _recentTrack(), cell: 10, text3: muted, showLegend: false),
          ]),
        ),
      ]),
    );
  }

  /// Les 14 derniers jours vécus : atteint, manqué, aujourd'hui en cours.
  BadgeTrack _recentTrack() {
    final reached = routineReachedDays(activity, hits, dayStartMin: dayStartMin);
    final today = livedDate(DateTime.now(), dayStartMin);
    final cells = <TrackCell>[];
    for (var i = 13; i >= 0; i--) {
      final y = ymdOf(today.subtract(Duration(days: i)));
      cells.add(reached.contains(y) ? TrackCell.hit : (i == 0 ? TrackCell.current : (bridged.contains(y) ? TrackCell.bridged : TrackCell.miss)));
    }
    return BadgeTrack(cells: cells, caption: '14 derniers jours · ${cells.where((c) => c == TrackCell.hit).length} atteints');
  }
}

/// Fiche objectif : une ligne par badge mesurable (Sur la trajectoire, Relevé
/// fidèle, Temps investi) et la ligne d'élan.
class ObjectiveBadgeLines extends StatelessWidget {
  final StrategicObjective objective;
  final List<Session> sessions;
  final List<MoodMark> marks;
  final Color accent;
  const ObjectiveBadgeLines({super.key, required this.objective, required this.sessions, required this.marks, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final o = objective;
    final lines = <Widget>[];
    if (o.metric != null || o.timeCommitments.isNotEmpty) {
      final t = trajectoryWeeks(o, sessions, now);
      final lv = kTrajectoryTiers.where((x) => t.longest >= x).length;
      lines.add(_line(cs, BadgeState(def: const BadgeDef(id: 'trajectoire', family: BadgeFamily.objectives, name: 'Sur la trajectoire', symbol: 'trajectory', tiers: kTrajectoryTiers, unit: 'sem.', unitLong: 'semaines'), level: lv, value: t.current),
          'Sur la trajectoire', 'semaines'));
    }
    if (o.metric != null) {
      final f = faithfulReadings(o);
      final lv = kReadingTiers.where((x) => f.longest >= x).length;
      lines.add(_line(cs, BadgeState(def: const BadgeDef(id: 'releve-fidele', family: BadgeFamily.objectives, name: 'Relevé fidèle', symbol: 'ledger', tiers: kReadingTiers, unit: 'relevés', unitLong: 'relevés'), level: lv, value: f.current),
          'Relevé fidèle', 'relevés'));
    }
    if (o.timeCommitments.isNotEmpty) {
      final h = investedHours(o, sessions, now);
      final lv = kTimeTiersHours.where((x) => h.hours >= x).length;
      lines.add(_line(cs, BadgeState(def: const BadgeDef(id: 'temps', family: BadgeFamily.time, name: 'Temps investi', symbol: 'hourglass', tiers: kTimeTiersHours, unit: 'h', unitLong: 'heures'), level: lv, value: double.parse(h.hours.toStringAsFixed(1))),
          'Temps investi', 'h'));
    }
    final elan = objectiveElanFacts(o, marks, sessions);
    if (lines.isEmpty && elan.count == 0) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withValues(alpha: .08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) Divider(height: 1, color: cs.onSurface.withValues(alpha: .08)),
          lines[i],
        ],
        if (elan.count > 0) ...[
          if (lines.isNotEmpty) Divider(height: 1, color: cs.onSurface.withValues(alpha: .08)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Text('Élan moyen ${_n(elan.mean!)} · ${elan.victories} victoire${elan.victories > 1 ? 's' : ''} sur la flemme',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _line(ColorScheme cs, BadgeState b, String name, String unit) {
    final next = b.nextTarget;
    final segs = next != null && next <= 12 ? next : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Opacity(opacity: b.acquired ? 1 : .6, child: BadgeView(state: b, size: 48)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name, style: TextStyle(fontSize: 14, fontWeight: b.acquired ? FontWeight.w600 : FontWeight.w400)),
              const Spacer(),
              Text(
                next == null ? '${fmtInt(b.def.tiers.last)} $unit · complet' : '${_n(b.value)} / ${fmtInt(next)} $unit',
                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .55), fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
            const SizedBox(height: 6),
            if (segs > 0)
              Row(children: [
                for (var i = 0; i < segs; i++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: i < segs - 1 ? 4 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i < b.value ? kBadgeGaugeFill : cs.onSurface.withValues(alpha: .1),
                      ),
                    ),
                  ),
              ])
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: b.progress ?? 1,
                  minHeight: 6,
                  backgroundColor: cs.onSurface.withValues(alpha: .1),
                  valueColor: const AlwaysStoppedAnimation<Color>(kBadgeGaugeFill),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Onglet Objectifs : « Badges · 14 / 38 › » et une bande de six badges à
/// 40 px (derniers obtenus d'abord, puis verrouillés en progression).
class BadgesRow extends StatelessWidget {
  final BadgeCenter center;
  final VoidCallback onOpen;
  const BadgesRow({super.key, required this.center, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: center,
      builder: (ctx, _) {
        final d = center.deck;
        final all = d?.badges ?? const <BadgeState>[];
        final acquired = all.where((b) => b.acquired).toList()
          ..sort((a, b) => (b.obtained ?? DateTime(2000)).compareTo(a.obtained ?? DateTime(2000)));
        final locked = all.where((b) => !b.acquired && b.showGauge && b.def.measured).toList();
        final strip = [...acquired, ...locked].take(6).toList();
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.military_tech_outlined, size: 16, color: kBadgeBrass),
                  const SizedBox(width: 6),
                  const Text('Badges', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(d == null ? '…' : '${d.acquired} / ${d.total}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBadgeBrass)),
                  if (d != null && d.seriesRunning > 0) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('· ${d.seriesRunning} série${d.seriesRunning > 1 ? 's' : ''} en cours',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .55))),
                    ),
                  ] else
                    const Spacer(),
                  Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: .4)),
                ]),
                if (strip.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    for (final b in strip)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Opacity(opacity: b.acquired ? 1 : .55, child: BadgeView(state: b, size: 40)),
                      ),
                  ]),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Aujourd'hui : « Badge obtenu · Semaine solide », montré une fois.
class UnlockSignalCard extends StatelessWidget {
  final List<BadgeState> badges;
  final Set<String> hunted; // badges qui étaient visés
  final VoidCallback onView;
  final VoidCallback onClose;
  final Color surface, text, text3, accent;
  const UnlockSignalCard({
    super.key,
    required this.badges,
    this.hunted = const {},
    required this.onView,
    required this.onClose,
    required this.surface,
    required this.text,
    required this.text3,
    required this.accent,
  });

  String _detail(BadgeState b) {
    if (b.def.tiers.length > 1) return '${fmtInt(b.def.tiers[b.level - 1])} ${b.def.unitLong}';
    return b.def.family == BadgeFamily.days ? 'journée' : '';
  }

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final first = badges.first;
    final title = badges.length == 1 ? first.def.name : badges.map((b) => b.def.name).join(', ');
    final detail = badges.length == 1 ? _detail(first) : '';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBadgeBrassDark),
      ),
      child: Row(children: [
        BadgeView(state: first, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                badges.any((b) => hunted.contains(b.def.id))
                    ? (badges.length == 1 ? 'BADGE VISÉ OBTENU' : '${badges.length} BADGES OBTENUS · DONT UN VISÉ')
                    : (badges.length == 1 ? 'BADGE OBTENU' : '${badges.length} BADGES OBTENUS'),
                style: const TextStyle(fontSize: 11, letterSpacing: .6, color: kBadgeBrass)),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: text)),
            if (detail.isNotEmpty) Text(detail, style: TextStyle(fontSize: 13, color: text3)),
          ]),
        ),
        TextButton(onPressed: onView, child: Text('Voir', style: TextStyle(fontWeight: FontWeight.w600, color: accent))),
        IconButton(visualDensity: VisualDensity.compact, onPressed: onClose, icon: Icon(Icons.close, size: 20, color: text3)),
      ]),
    );
  }
}

/// Date de départ d'un objectif, pour les faits (exposée pour les fiches).
DateTime objectiveStartOf(StrategicObjective o) => objectiveStart(o);
