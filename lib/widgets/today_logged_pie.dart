import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

/// Camembert des activités loggées aujourd'hui (couleur = domaine, légende
/// avec minutes). Sans titre — il vit dans Maintenant, le contexte suffit.
/// Invisible tant que rien n'est loggué.
class TodayLoggedPie extends StatelessWidget {
  final AppLogic logic;
  const TodayLoggedPie({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final byActivity = <String, double>{};
    for (final s in logic.state.sessions) {
      final start = s.startAt.isAfter(todayStart) ? s.startAt : todayStart;
      final end = s.endAt ?? now;
      if (end.isBefore(todayStart)) continue;
      final minutes = end.difference(start).inSeconds / 60.0;
      if (minutes <= 0) continue;
      byActivity[s.activityId] = (byActivity[s.activityId] ?? 0) + minutes;
    }
    if (byActivity.isEmpty) return const SizedBox.shrink();
    final totalMin = byActivity.values.fold(0.0, (a, b) => a + b);
    final activities = logic.state.activeActivities;
    final entries = byActivity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cs = Theme.of(context).colorScheme;
    final sections = entries.map((e) {
      final act = activities.where((a) => a.id == e.key).firstOrNull;
      final col =
          domainColor(act?.domainId, logic.state.activeDomains) ?? cs.primary;
      final pct = e.value / totalMin;
      return PieChartSectionData(
        value: e.value,
        color: col,
        radius: 70,
        showTitle: pct > 0.08,
        title: '${(pct * 100).round()}%',
        titleStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
      );
    }).toList();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            child: PieChart(PieChartData(
                sections: sections, sectionsSpace: 2, centerSpaceRadius: 36)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: entries.map((e) {
              final act = activities.where((a) => a.id == e.key).firstOrNull;
              final col =
                  domainColor(act?.domainId, logic.state.activeDomains) ??
                      cs.primary;
              final mins = e.value.round();
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: col, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(
                  '${act?.name ?? '?'}  ${mins >= 60 ? '${(mins / 60).toStringAsFixed(1)}h' : '${mins}m'}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withOpacity(.6)),
                ),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }
}
