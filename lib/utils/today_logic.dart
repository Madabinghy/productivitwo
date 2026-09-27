import 'dart:math' as math;

import 'package:productivitwo_v1/models.dart';

/// Logique pure de la vue Aujourd'hui (refonte web § 2) — testable sans widget.
/// Les minutes sont comptées depuis minuit ; les blocs `deleted` doivent avoir
/// été filtrés en amont (cf. `DailySchedule` : soft-delete).

/// Minute de début d'un bloc ("HH:mm" → minutes). Format invalide → 0.
int blockStartMin(ScheduleBlock b) {
  final parts = b.startTime.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

int blockEndMin(ScheduleBlock b) => blockStartMin(b) + b.durationMin;

/// Bloc focal : le premier bloc `pending` dont le créneau contient l'heure
/// courante (`current: true`), sinon le prochain à venir, sinon null.
({ScheduleBlock block, bool current})? focusBlock(
    List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    final s = blockStartMin(b);
    if (b.status == 'pending' && s <= nowMin && nowMin < s + b.durationMin) {
      return (block: b, current: true);
    }
  }
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.status != 'pending' || blockStartMin(b) <= nowMin) continue;
    if (next == null || blockStartMin(b) < blockStartMin(next)) next = b;
  }
  return next == null ? null : (block: next, current: false);
}

/// Premier bloc `pending` qui commence à la fin de [block] ou après.
ScheduleBlock? nextBlockAfter(List<ScheduleBlock> blocks, ScheduleBlock block) {
  final end = blockEndMin(block);
  ScheduleBlock? next;
  for (final b in blocks) {
    if (b.id == block.id || b.status != 'pending') continue;
    if (blockStartMin(b) < end) continue;
    if (next == null || blockStartMin(b) < blockStartMin(next)) next = b;
  }
  return next;
}

/// Minutes planifiées restantes : blocs `pending` dont la fin est après
/// maintenant, tronqués à maintenant.
int remainingPlannedMin(List<ScheduleBlock> blocks, int nowMin) {
  var total = 0;
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    final end = blockEndMin(b);
    if (end <= nowMin) continue;
    total += end - math.max(blockStartMin(b), nowMin);
  }
  return total;
}

/// Bornes de la frise, en heures pleines : de min(premier bloc, maintenant)
/// à max(dernier bloc, maintenant), plafonnées à 24 h.
({int startH, int endH}) timelineHours(List<ScheduleBlock> blocks, int nowMin) {
  var first = nowMin;
  var last = nowMin + 1;
  for (final b in blocks) {
    first = math.min(first, blockStartMin(b));
    last = math.max(last, blockEndMin(b));
  }
  final startH = (first ~/ 60).clamp(0, 23);
  final endH = ((last + 59) ~/ 60).clamp(startH + 1, 24);
  return (startH: startH, endH: endH);
}

/// Échelle en px/min : remplit [availablePx] mais jamais sous [minPpm]
/// (au-delà, la frise défile).
double timelinePxPerMin(double availablePx, int rangeMin,
    {double minPpm = 0.75}) {
  if (rangeMin <= 0) return minPpm;
  return math.max(availablePx / rangeMin, minPpm);
}

/// Minutes par catégorie (project · routine · personal · break), dans cet ordre,
/// sans les catégories vides.
List<({String category, int min})> minutesByCategory(List<ScheduleBlock> blocks) {
  final byCat = <String, int>{};
  for (final b in blocks) {
    byCat[b.category] = (byCat[b.category] ?? 0) + b.durationMin;
  }
  return [
    for (final c in const ['project', 'routine', 'personal', 'break'])
      if ((byCat[c] ?? 0) > 0) (category: c, min: byCat[c]!),
  ];
}
