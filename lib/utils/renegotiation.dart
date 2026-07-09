import 'package:productivitwo_v1/models.dart';

// ─── RENÉGOCIATION TACTIQUE (maquette 12a) ───────────────────────────────────
//
// Un bloc coince : trois issues GÉNÉRÉES DEPUIS LE RÉEL (créneaux libres du
// jour, historique de reports), chacune avec sa conséquence affichée — on
// choisit en connaissance de cause. Fonctions pures, testables. 0 LLM.

/// Minutes « utiles » restantes aujourd'hui (jusqu'à [dayEndHour]).
int usefulMinutesLeft(DateTime now, {int dayEndHour = 22}) {
  final end = dayEndHour * 60;
  final cur = now.hour * 60 + now.minute;
  return cur >= end ? 0 : end - cur;
}

/// Le DERNIER créneau libre du jour pouvant contenir [durationMin] minutes,
/// entre maintenant et [dayEndHour], en évitant les blocs `pending` restants.
/// Retourne "HH:mm" ou null si plus rien ne rentre.
String? findLastFreeSlot(
  DateTime now,
  List<ScheduleBlock> blocks,
  int durationMin, {
  int dayEndHour = 22,
  String? excludeBlockId,
}) {
  int hm(String s) {
    final p = s.split(':');
    return (int.tryParse(p.first) ?? 0) * 60 +
        (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  final nowMin = now.hour * 60 + now.minute;
  final dayEnd = dayEndHour * 60;
  // Occupations restantes : blocs pending (hors celui qu'on renégocie).
  final busy = blocks
      .where((b) =>
          b.status == 'pending' &&
          b.id != excludeBlockId &&
          !b.isPrep)
      .map((b) => (start: hm(b.startTime), end: hm(b.startTime) + b.durationMin))
      .where((b) => b.end > nowMin)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  // Parcours des trous, on garde LE DERNIER qui contient durationMin.
  int cursor = nowMin;
  int? lastFit;
  for (final b in busy) {
    final gapEnd = b.start.clamp(cursor, dayEnd);
    if (gapEnd - cursor >= durationMin) {
      lastFit = gapEnd - durationMin; // au plus tard dans ce trou
    }
    if (b.end > cursor) cursor = b.end;
    if (cursor >= dayEnd) break;
  }
  if (dayEnd - cursor >= durationMin) {
    lastFit = dayEnd - durationMin;
  }
  if (lastFit == null) return null;
  final h = lastFit ~/ 60;
  final m = lastFit % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Nombre de reports de CET engagement sur les blocs fournis (7 derniers
/// jours) — pour « 2ᵉ report cette semaine — demain il passe en premier ».
int weeklyReportCount(ScheduleBlock b, List<ScheduleBlock> weekBlocks) {
  bool same(ScheduleBlock w) {
    if (w.isPrep || w.category == 'break') return false;
    if (b.taskId != null) return w.taskId == b.taskId;
    if (b.activityId != null) return w.activityId == b.activityId;
    return w.title.trim().toLowerCase() == b.title.trim().toLowerCase();
  }

  return weekBlocks.where((w) => same(w) && w.skipReason == 'reporte').length;
}
