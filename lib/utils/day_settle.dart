import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin, loggedMinForBlock;

/// « Règlement du soir » (2026-10) : à la bascule de journée vécue, les blocs
/// de la journée qui vient de finir dont le CHRONO a couvert au moins 60 % du
/// créneau (plancher 10 min) passent « fait ». Pendant la journée, ce temps
/// n'est qu'une proposition « Marquer fait ? » (décision 2026-10) ; une fois
/// la journée close, plus personne ne peut confirmer — et le bloc Sommeil
/// (22:00 → 05:00, à cheval sur la bascule) n'était jamais validé, donc jamais
/// de journée parfaite. Jamais un bloc décoché à la main (`noAutoWin`), ni un
/// bloc sans source, ni un bloc qui n'a pas commencé. [date] = jour
/// calendaire du programme (les heures des blocs sont des heures d'horloge
/// de ce jour ; Sommeil 22:00 + 420 min finit le lendemain 05:00).
List<ScheduleBlock> blocksSettledByChrono({
  required Iterable<ScheduleBlock> blocks,
  required Iterable<Session> sessions,
  required DateTime date,
  required DateTime now,
}) {
  final midnight = DateTime(date.year, date.month, date.day);
  final out = <ScheduleBlock>[];
  for (final b in blocks) {
    if (b.status != 'pending' || b.noAutoWin) continue;
    if (b.actionId == null && b.taskId == null && b.activityId == null && b.timeBlock == null) continue;
    final start = midnight.add(Duration(minutes: blockStartMin(b)));
    if (!start.isBefore(now)) continue;
    final end = midnight.add(Duration(minutes: blockEndMin(b)));
    final logged = loggedMinForBlock(b, sessions, start, end.isAfter(now) ? now : end, now: now);
    final threshold = (b.durationMin * 0.6).round();
    if (logged >= (threshold < 10 ? 10 : threshold)) out.add(b);
  }
  return out;
}
