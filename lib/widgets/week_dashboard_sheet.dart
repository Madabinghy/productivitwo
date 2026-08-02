import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';

/// « Ma semaine » sur MOBILE — la même lecture que la console coach 8a,
/// sur ses propres données (transparence : le coaché voit ce que le coach
/// voit ; le coach, lui, ne voit que les domaines partagés).
/// Fenêtre GLISSANTE de 7 jours (un lundi matin, la semaine calendaire
/// serait quasi vide) ; tendance = semaines révolues S-3 → S-1 + 7 j.
/// Calculs partagés : lib/utils/engagement_stats.dart (mêmes règles que le
/// dashboard serveur).

/// Carte compacte pour l'Accueil : chiffre 7 j + mini-tendance, tap → sheet.
class WeekDashboardCard extends StatelessWidget {
  final AppLogic logic;

  const WeekDashboardCard({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = logic.state;
    final engagements =
        rollingWeekEngagements(activities: st.activities, hits: st.habitHits);
    if (engagements.isEmpty) return const SizedBox.shrink();
    final weeks =
        fourWeekTrend(activities: st.activities, hits: st.habitHits);
    final kept = engagements.where((e) => e.kept).length;
    final total = engagements.length;
    final pct = total == 0 ? 0 : ((kept / total) * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showWeekDashboardSheet(context, logic),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.insights_rounded,
                        size: 15, color: cs.primary),
                    const SizedBox(width: 6),
                    Text('MA SEMAINE · 7 DERNIERS JOURS',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: cs.onSurface.withOpacity(.5))),
                  ]),
                  const SizedBox(height: 6),
                  Text('$kept / $total engagements tenus',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: palierColor(pct))),
                ],
              ),
            ),
            // Mini-histogramme de tendance : la HAUTEUR encode le %, la
            // couleur encode le palier — deux lectures d'un coup d'œil.
            SizedBox(
              height: 26,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final w in weeks)
                    Container(
                      width: 9,
                      // Plancher 4 px : une semaine à 0 % reste visible.
                      height: 4 + (w.pct.clamp(0, 100) / 100) * 22,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: palierColor(w.pct).withOpacity(.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                size: 18, color: cs.onSurface.withOpacity(.35)),
          ]),
        ),
      ),
    );
  }
}

Future<void> showWeekDashboardSheet(BuildContext context, AppLogic logic) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final st = logic.state;
      final engagements = rollingWeekEngagements(
          activities: st.activities, hits: st.habitHits);
      final weeks =
          fourWeekTrend(activities: st.activities, hits: st.habitHits);
      final kept = engagements.where((e) => e.kept).length;
      final total = engagements.length;
      final pct = total == 0 ? 0 : ((kept / total) * 100).round();
      final delta = weeks.length >= 2
          ? weeks.last.pct - weeks[weeks.length - 2].pct
          : 0;
      final last = lastActivityAt(sessions: st.sessions, hits: st.habitHits);
      final domains = st.activeDomains;
      final byDomain = <String, List<EngagementStat>>{};
      for (final e in engagements) {
        byDomain.putIfAbsent(e.domainId, () => []).add(e);
      }

      String lastLabel() {
        if (last == null) return '—';
        final days = DateTime.now().difference(last).inDays;
        return days <= 0 ? 'auj.' : (days == 1 ? 'hier' : 'il y a $days j');
      }

      Widget bigNumber(String label, String value, Color? color) =>
          Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color ?? cs.onSurface)),
            Text(label,
                style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(.45))),
          ]);

      Widget sectionLabel(String t) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8),
            child: Text(t,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                    color: cs.onSurface.withOpacity(.45))),
          );

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const Text('Ma semaine',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                'Sur les 7 derniers jours, au fil de l\'eau. La même lecture '
                'que ton coach — lui ne voit que les domaines que tu partages.',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              bigNumber('ENGAGEMENTS · 7 J', '$kept / $total',
                  palierColor(pct)),
              bigNumber('TENDANCE', '${delta >= 0 ? '+' : ''}$delta pts',
                  delta >= 0 ? kPalierGreen : kPalierCoral),
              bigNumber('DERNIÈRE ACTIVITÉ', lastLabel(), null),
            ]),
            sectionLabel('TENDANCE — SEMAINES RÉVOLUES + 7 J GLISSANTS'),
            Row(children: [
              for (var i = 0; i < weeks.length; i++) ...[
                Expanded(
                  child: Column(children: [
                    Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palierColor(weeks[i].pct).withOpacity(.2),
                        borderRadius: BorderRadius.circular(9),
                        border:
                            Border.all(color: palierColor(weeks[i].pct)),
                      ),
                      child: Text('${weeks[i].pct} %',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    const SizedBox(height: 3),
                    Text(weeks[i].label,
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withOpacity(.45))),
                  ]),
                ),
                if (i < weeks.length - 1) const SizedBox(width: 6),
              ],
            ]),
            if (engagements.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                    'Aucun engagement hebdo — crée des routines pour voir ta '
                    'semaine se mesurer ici.',
                    style: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurface.withOpacity(.55))),
              ),
            for (final d in domains)
              if (byDomain.containsKey(d.id)) ...[
                sectionLabel(d.name.toUpperCase()),
                for (final e in byDomain[d.id]!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(
                          e.kept
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: e.kept
                              ? kPalierGreen
                              : cs.onSurface.withOpacity(.35)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(e.label,
                              style: const TextStyle(fontSize: 13.5))),
                      Text('${e.done} / ${e.target}',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: e.kept
                                  ? kPalierGreen
                                  : cs.onSurface.withOpacity(.7))),
                    ]),
                  ),
              ],
          ],
        ),
      );
    },
  );
}
