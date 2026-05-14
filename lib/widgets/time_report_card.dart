import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

class TimeReportCard extends StatelessWidget {
  final AppLogic logic;
  final int days; // 7 ou 30

  const TimeReportCard({super.key, required this.logic, required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final domains = logic.state.domains;

    // ── Données donut ──────────────────────────────────────────────────────
    final totals = logic.timeTotalsByDomain(start, now);
    final grandTotal =
        totals.values.fold(Duration.zero, (s, d) => s + d);

    if (grandTotal.inMinutes == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'Aucune session enregistrée sur cette période.',
            style: TextStyle(color: cs.onSurface.withOpacity(.45)),
          ),
        ),
      );
    }

    // ── Données barres 12 semaines ─────────────────────────────────────────
    const kWeeks = 12;
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    // semaines[0] = la plus ancienne, semaines[kWeeks-1] = cette semaine
    final weekStarts = List.generate(
      kWeeks,
      (i) => monday.subtract(Duration(days: 7 * (kWeeks - 1 - i))),
    );

    // minutesPerDomainPerWeek[weekIdx][domainId]
    final weekData = List.generate(kWeeks, (wi) {
      final ws = weekStarts[wi];
      final we = ws.add(const Duration(days: 7));
      return {
        for (final d in domains)
          d.id: logic.totalForRange(ws, we, domainId: d.id).inMinutes
              .toDouble()
      };
    });

    final maxWeekMinutes = weekData
        .map((w) => w.values.fold(0.0, (s, v) => s + v))
        .fold(0.0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Titre ──────────────────────────────────────────────────────────
        Text(
          'Répartition du temps',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cs.onSurface.withOpacity(.6),
          ),
        ),
        const SizedBox(height: 16),

        // ── Donut + légende ────────────────────────────────────────────────
        _DonutSection(
          domains: domains,
          totals: totals,
          grandTotal: grandTotal,
          cs: cs,
        ),
        const SizedBox(height: 28),

        // ── Barres 12 semaines ─────────────────────────────────────────────
        Text(
          '12 dernières semaines (heures)',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cs.onSurface.withOpacity(.6),
          ),
        ),
        const SizedBox(height: 12),
        _WeeklyBarsSection(
          domains: domains,
          weekStarts: weekStarts,
          weekData: weekData,
          maxMinutes: maxWeekMinutes,
          cs: cs,
        ),
        const SizedBox(height: 28),

        // ── Heatmap par domaine ────────────────────────────────────────────
        Text(
          'Heatmap par domaine',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: cs.onSurface.withOpacity(.6),
          ),
        ),
        const SizedBox(height: 12),
        _DomainHeatmapSection(logic: logic, cs: cs),
      ],
    );
  }
}

// ── Donut ──────────────────────────────────────────────────────────────────────

class _DonutSection extends StatelessWidget {
  final List<Domain> domains;
  final Map<String, Duration> totals;
  final Duration grandTotal;
  final ColorScheme cs;

  const _DonutSection({
    required this.domains,
    required this.totals,
    required this.grandTotal,
    required this.cs,
  });

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];
    final legendItems = <_LegendItem>[];

    for (int i = 0; i < domains.length; i++) {
      final d = domains[i];
      final dur = totals[d.id] ?? Duration.zero;
      if (dur.inMinutes == 0) continue;
      final ratio = dur.inMinutes / grandTotal.inMinutes;
      final color = kDomainPalette[i % kDomainPalette.length];

      sections.add(PieChartSectionData(
        value: dur.inMinutes.toDouble(),
        color: color,
        radius: 48,
        title: ratio > 0.08 ? '${(ratio * 100).round()}%' : '',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
      legendItems.add(_LegendItem(
        color: color,
        label: d.name,
        value: _fmt(dur),
      ));
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 44,
              sectionsSpace: 2,
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: legendItems
              .map((item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(item.label,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        item.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.7),
                        ),
                      ),
                    ],
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _LegendItem {
  final Color color;
  final String label;
  final String value;
  const _LegendItem({required this.color, required this.label, required this.value});
}

// ── Barres 12 semaines ─────────────────────────────────────────────────────────

class _WeeklyBarsSection extends StatelessWidget {
  final List<Domain> domains;
  final List<DateTime> weekStarts;
  final List<Map<String, double>> weekData; // [weekIdx][domainId] = minutes
  final double maxMinutes;
  final ColorScheme cs;

  const _WeeklyBarsSection({
    required this.domains,
    required this.weekStarts,
    required this.weekData,
    required this.maxMinutes,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    if (maxMinutes == 0) {
      return Text(
        'Aucune donnée sur 12 semaines.',
        style: TextStyle(color: cs.onSurface.withOpacity(.4), fontSize: 12),
      );
    }

    // Minimum 2h d'échelle pour que les petites valeurs restent visibles
    final maxH = ((maxMinutes / 60).ceilToDouble()).clamp(2.0, double.infinity);

    final barGroups = List.generate(weekData.length, (wi) {
      final rodSegments = <BarChartRodStackItem>[];
      double cursor = 0;
      for (int di = 0; di < domains.length; di++) {
        final d = domains[di];
        final minutes = weekData[wi][d.id] ?? 0;
        if (minutes == 0) continue;
        final hours = minutes / 60;
        final color = kDomainPalette[di % kDomainPalette.length];
        rodSegments.add(BarChartRodStackItem(cursor, cursor + hours, color));
        cursor += hours;
      }
      return BarChartGroupData(
        x: wi,
        barRods: [
          BarChartRodData(
            toY: cursor,
            width: 14,
            rodStackItems: rodSegments,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
      );
    });

    final now = DateTime.now();
    final thisWeekIdx = weekData.length - 1;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxH == 0 ? 1 : maxH,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: cs.outlineVariant.withOpacity(.3), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (val, _) {
                  if (val % 1 != 0) return const SizedBox.shrink();
                  return Text(
                    '${val.toInt()}h',
                    style: TextStyle(
                        fontSize: 9, color: cs.onSurface.withOpacity(.45)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (val, _) {
                  final i = val.toInt();
                  if (i < 0 || i >= weekStarts.length)
                    return const SizedBox.shrink();
                  final ws = weekStarts[i];
                  final isThisWeek = i == thisWeekIdx;
                  // n'afficher que 1 label sur 2 pour éviter la surcharge
                  if (!isThisWeek && i % 2 != 0)
                    return const SizedBox.shrink();
                  final label = isThisWeek
                      ? 'cette\nsem.'
                      : '${ws.day}/${ws.month}';
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: isThisWeek
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isThisWeek
                            ? cs.primary
                            : cs.onSurface.withOpacity(.45),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: barGroups,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final ws = weekStarts[group.x];
                final totalH = rod.toY;
                return BarTooltipItem(
                  '${ws.day}/${ws.month}\n${totalH.toStringAsFixed(1)}h',
                  const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Heatmap par domaine ────────────────────────────────────────────────────────

class _DomainHeatmapSection extends StatelessWidget {
  final AppLogic logic;
  final ColorScheme cs;

  const _DomainHeatmapSection({required this.logic, required this.cs});

  @override
  Widget build(BuildContext context) {
    const cellSize = 13.0;
    const gap = 3.0;
    const weeks = 12;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDay = today.subtract(const Duration(days: 83));
    final offsetToMonday = (firstDay.weekday - 1) % 7;
    final startMonday = firstDay.subtract(Duration(days: offsetToMonday));

    final start = startMonday;
    final end = today.add(const Duration(days: 1));

    final minutesMap = logic.timeMinutesPerDomainPerDay(start, end);
    final domains = logic.state.domains;

    // Max global pour normaliser les intensités (comparaison entre domaines)
    int globalMax = 1;
    for (final dayMap in minutesMap.values) {
      for (final m in dayMap.values) {
        if (m > globalMax) globalMax = m;
      }
    }

    // Filtre les domaines qui ont au moins une session
    final activeDomains =
        domains.where((d) => minutesMap.containsKey(d.id)).toList();

    if (activeDomains.isEmpty) {
      return Text(
        'Aucune session enregistrée.',
        style: TextStyle(color: cs.onSurface.withOpacity(.4), fontSize: 12),
      );
    }

    String fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

    String fmtMin(int m) {
      if (m == 0) return '—';
      if (m < 60) return '${m}min';
      final h = m ~/ 60;
      final rem = m % 60;
      return rem == 0 ? '${h}h' : '${h}h${rem.toString().padLeft(2, '0')}';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête mois
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Row(
              children: List.generate(weeks, (col) {
                final ws = startMonday.add(Duration(days: col * 7));
                final showLabel = col == 0 || ws.day <= 7;
                return SizedBox(
                  width: cellSize + gap,
                  child: showLabel
                      ? Text(
                          _monthAbbr(ws.month),
                          style: TextStyle(
                            fontSize: 9,
                            color: cs.onSurface.withOpacity(.4),
                          ),
                        )
                      : null,
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          // Une ligne par domaine actif
          for (int di = 0; di < activeDomains.length; di++) ...[
            if (di > 0) const SizedBox(height: gap),
            Row(
              children: [
                // Label domaine
                SizedBox(
                  width: 56,
                  child: Text(
                    activeDomains[di].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withOpacity(.6),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Cellules
                Row(
                  children: List.generate(weeks, (col) {
                    return Padding(
                      padding: const EdgeInsets.only(right: gap),
                      child: Row(
                        children: List.generate(7, (row) {
                          final d = startMonday
                              .add(Duration(days: col * 7 + row));
                          if (d.isAfter(today)) {
                            return SizedBox(width: cellSize, height: cellSize);
                          }
                          final ymd =
                              '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                          final mins =
                              minutesMap[activeDomains[di].id]?[ymd] ?? 0;
                          final intensity =
                              mins == 0 ? 0.0 : (mins / globalMax).clamp(0.12, 1.0);
                          final domColor =
                              kDomainPalette[di % kDomainPalette.length];
                          final color = mins == 0
                              ? cs.onSurface.withOpacity(.07)
                              : domColor.withOpacity(intensity);
                          return Tooltip(
                            message:
                                '${activeDomains[di].name} · ${fmtDate(d)}\n${fmtMin(mins)}',
                            child: Container(
                              width: cellSize,
                              height: cellSize,
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Légende intensité
          Row(
            children: [
              const SizedBox(width: 60),
              Text('moins',
                  style: TextStyle(
                      fontSize: 9, color: cs.onSurface.withOpacity(.35))),
              const SizedBox(width: 4),
              for (final op in [0.15, 0.35, 0.55, 0.75, 1.0])
                Container(
                  width: cellSize,
                  height: cellSize,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: kDomainPalette[0].withOpacity(op),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: 4),
              Text('plus',
                  style: TextStyle(
                      fontSize: 9, color: cs.onSurface.withOpacity(.35))),
            ],
          ),
        ],
      ),
    );
  }

  static const _months = [
    '', 'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
    'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
  ];
  static String _monthAbbr(int m) => _months[m];
}
