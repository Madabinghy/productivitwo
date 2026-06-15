import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/time_scope.dart';

/// Sheet d'une activité-temps, calqué sur le sheet du FAB mobile (stats semaine
/// + progression, aujourd'hui/mois, courbe 60 j, heatmap 12 sem). Réutilisable
/// hors main.dart (web + mobile). Le lancement de minuteur (alarme) reste mobile
/// → pas de CTA ici. `showHeatmap` masque la heatmap quand le château la montre.
Future<void> showActivitySheet(
    BuildContext context, AppLogic logic, String activityId,
    {bool showHeatmap = true}) async {
  Activity? found;
  for (final x in logic.state.activeActivities) {
    if (x.id == activityId) {
      found = x;
      break;
    }
  }
  if (found == null) return;
  final a = found;
  final color =
      domainColor(a.domainId, logic.state.activeDomains) ?? const Color(0xFF4FA3FF);
  final domain =
      logic.state.activeDomains.where((d) => d.id == a.domainId).firstOrNull;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);
  final durDay = logic.totalForRangeByActivity(a.id, today, now);
  final durWeek = logic.totalForRangeByActivity(a.id, weekStart, now);
  final durMonth = logic.totalForRangeByActivity(a.id, monthStart, now);

  final weeklyTargetH = logic.timeSliding(a.id, 7).targetMin / 60.0;
  final weekProgress = weeklyTargetH > 0
      ? (durWeek.inMinutes / 60.0 / weeklyTargetH).clamp(0.0, 1.0)
      : 0.0;

  String fmt(Duration d) {
    if (d.inMinutes == 0) return '—';
    if (d.inHours == 0) return '${d.inMinutes}min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h${m.toString().padLeft(2, '0')}';
  }

  // Courbe 60 j (moyennes glissantes 7 j / 30 j).
  final start = today.subtract(const Duration(days: 59));
  final end = today.add(const Duration(days: 1));
  final mbd = timeByDayForActivity(
      sessions: logic.state.sessions,
      activityId: a.id,
      start: start,
      end: end,
      now: now);
  final s7 = movingAvgHoursSeries(
      minutesByDay: mbd, today: now, windowDays: 7, points: 30);
  final s30 = movingAvgHoursSeries(
      minutesByDay: mbd, today: now, windowDays: 30, points: 30);
  final goalH = (logic.timeSliding(a.id, 7).targetMin / 7.0) / 60.0;

  // Heatmap DÉTAIL par jour sur 12 semaines (7 lignes × 12 colonnes), unités =
  // 30 min. Référence = 90e percentile des jours actifs (intensité relative).
  const cellSize = 12.0, gap = 2.0, weeks = 12;
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final startMonday = thisMonday.subtract(const Duration(days: 77));
  final Map<String, int> countByYmd = {};
  for (final s in logic.state.sessions.where((s) => s.activityId == a.id)) {
    final sEnd = s.endAt ?? now;
    if (s.startAt.isAfter(now) || sEnd.isBefore(startMonday)) continue;
    var cursor = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
    while (!cursor.isAfter(today)) {
      final dayEnd = cursor.add(const Duration(days: 1));
      final segStart = cursor.isBefore(s.startAt) ? s.startAt : cursor;
      final segEnd = dayEnd.isAfter(sEnd) ? sEnd : dayEnd;
      final mins = segEnd.difference(segStart).inMinutes;
      if (mins > 0) {
        final ymd =
            '${cursor.year}${cursor.month.toString().padLeft(2, '0')}${cursor.day.toString().padLeft(2, '0')}';
        countByYmd[ymd] = (countByYmd[ymd] ?? 0) + (mins / 30).ceil();
      }
      cursor = dayEnd;
    }
  }
  final referenceCount =
      percentileOf(countByYmd.values.toList(), 0.90).clamp(1.0, double.infinity);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget miniStat(String label, String value) => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(.4))),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(.85))),
            ],
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header.
                Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 10),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 20)),
                        if (domain != null)
                          Text(domain.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // Hero semaine + progression, stats secondaires.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SEMAINE',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: cs.onSurface.withOpacity(.4))),
                          Text(fmt(durWeek),
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  height: 1.0)),
                          if (weeklyTargetH > 0) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: weekProgress,
                                minHeight: 6,
                                backgroundColor: color.withOpacity(.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    weekProgress >= 1.0
                                        ? Colors.green
                                        : color),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text('${(weekProgress * 100).round()}% de l\'objectif',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withOpacity(.4))),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        miniStat("AUJOURD'HUI", fmt(durDay)),
                        const SizedBox(height: 6),
                        miniStat('CE MOIS', fmt(durMonth)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Courbe 60 j.
                SizedBox(
                  height: 80,
                  child: MiniAvgLineChart(
                      series7: s7,
                      series30: s30,
                      goalHoursPerDay: goalH,
                      color: color),
                ),
                if (showHeatmap) ...[
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(
                                weeks,
                                (col) => Padding(
                                      padding: const EdgeInsets.only(right: gap),
                                      child: Column(
                                        children: List.generate(7, (row) {
                                          final d = startMonday.add(
                                              Duration(days: col * 7 + row));
                                          if (d.isAfter(today)) {
                                            return const SizedBox(
                                                height: cellSize + gap,
                                                width: cellSize);
                                          }
                                          final ymd =
                                              '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
                                          final count = countByYmd[ymd] ?? 0;
                                          final intensity = count == 0
                                              ? 0.0
                                              : (count / referenceCount)
                                                  .clamp(0.15, 1.0);
                                          final emptyColor =
                                              cs.onSurface.withOpacity(.10);
                                          final cellColor = count == 0
                                              ? emptyColor
                                              : Color.lerp(emptyColor, color,
                                                  intensity)!;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: gap),
                                            child: Container(
                                              width: cellSize,
                                              height: cellSize,
                                              decoration: BoxDecoration(
                                                color: cellColor,
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('12 sem.',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(.35))),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
