import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

const _kCharge = Color(0xFF4FC26B);

/// Sheet compact d'une activité-temps (détail lecture) : objectif, temps
/// jour/semaine/mois, heatmap 12 semaines. Version réutilisable hors main.dart
/// (le sheet riche du « Maintenant » reste couplé à l'app principale).
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
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);

  String fmt(Duration d) {
    if (d.inMinutes == 0) return '—';
    if (d.inHours == 0) return '${d.inMinutes}min';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h${m.toString().padLeft(2, '0')}';
  }

  Widget stat(String label, Duration d) => Expanded(
        child: Column(children: [
          Text(fmt(d),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.name,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Objectif : ${a.goalMin} min/jour',
                style: const TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 18),
            Row(children: [
              stat("Aujourd'hui",
                  logic.totalForRangeByActivity(a.id, today, now)),
              stat('Semaine',
                  logic.totalForRangeByActivity(a.id, weekStart, now)),
              stat('Mois',
                  logic.totalForRangeByActivity(a.id, monthStart, now)),
            ]),
            if (showHeatmap) ...[
              const SizedBox(height: 20),
              const Text('12 semaines (jours objectif atteint)',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (final n in logic.activityTimeWeeklyHeatmap(a.id))
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: n > 0
                            ? _kCharge.withOpacity(0.2 + 0.8 * (n / 7).clamp(0.0, 1.0))
                            : Colors.white.withOpacity(.04),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.white.withOpacity(.06)),
                      ),
                      alignment: Alignment.center,
                      child: n > 0
                          ? Text('$n',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12))
                          : const Text('🕸️', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
