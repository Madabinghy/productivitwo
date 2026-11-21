import 'package:flutter/material.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show objectiveStart;
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Lignes de badges dans les fiches et rangée d'Objectifs (lot 3, design
/// « Badges Productivitwo », section Écrans) : badge à 40 px avec sa jauge,
/// le fait en chiffres, jamais un jugement.

String _n(num v) => v == v.roundToDouble() ? fmtInt(v) : v.toStringAsFixed(1).replaceAll('.', ',');

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
