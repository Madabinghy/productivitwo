import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;

/// Graphiques des tuiles d'Organisation selon la nature du domaine (maquette validée 2026-11-05) :
/// ① travail = cumul de la fenêtre face au rythme, ② pratique = calendrier de 28 jours,
/// ③ entretien / suivi = routines × jours ; ④ briques du projet du moment = `projectBricks`.

/// ① Le temps cumulé jour après jour depuis le début de la fenêtre, face à l'attendu.
class CumulChart {
  /// Cumul en fin de chaque jour écoulé (aujourd'hui compris).
  final List<int> cumul;
  /// Minimum par jour (0 = pas de droite attendue).
  final int perDay;
  final int windowDays;
  const CumulChart({required this.cumul, required this.perDay, required this.windowDays});

  int get done => cumul.isEmpty ? 0 : cumul.last;
  int get expected => perDay * cumul.length;
  int get delta => done - expected;
  /// Haut de l'échelle : la fenêtre entière attendue, ou ce qui est fait s'il dépasse.
  int get scaleMax {
    final w = perDay * windowDays;
    return [w, done, 1].reduce((a, b) => a > b ? a : b);
  }
}

CumulChart cumulChart(List<int> daily, {required int perDay, required int windowDays}) {
  var s = 0;
  return CumulChart(cumul: [for (final m in daily) s += m < 0 ? 0 : m], perDay: perDay, windowDays: windowDays);
}

/// « +32 min sur le rythme » / « −1h10 sur le rythme » / « pile au rythme ».
String cumulLabel(CumulChart c, String Function(int) fmt) {
  if (c.perDay <= 0) return 'cette semaine';
  final d = c.delta;
  if (d.abs() < 5) return 'pile au rythme';
  return '${d > 0 ? '+' : '−'}${fmt(d.abs())} sur le rythme';
}

/// ② Intensité d'une case du calendrier (0 rien … 4 fort) : face au minimum du jour s'il y en a un,
/// sinon face au meilleur jour de la période.
List<int> calendarLevels(List<int> daily, {int goal = 0}) {
  final mx = daily.fold<int>(0, (a, b) => a > b ? a : b);
  int level(int m) {
    if (m <= 0) return 0;
    final r = goal > 0 ? m / goal : m / (mx == 0 ? 1 : mx);
    if (goal > 0) return r < .5 ? 1 : (r < 1 ? 2 : (r < 1.5 ? 3 : 4));
    return r < .25 ? 1 : (r < .5 ? 2 : (r < .8 ? 3 : 4));
  }

  return [for (final m in daily) level(m)];
}

int activeDays(List<int> daily) => daily.where((m) => m > 0).length;

/// ③ Une case de la grille routines × jours.
enum RoutineCell { done, partial, missed, future }

class RoutineRow {
  final Activity routine;
  final List<RoutineCell> cells; // lundi → dimanche
  final int count; // jours tenus (quotidienne) ou coches de la semaine (hebdo)
  final int target; // jours écoulés (quotidienne) ou cible de la semaine (hebdo)
  final bool behind;
  const RoutineRow({required this.routine, required this.cells, required this.count, required this.target, required this.behind});

  String get right => '$count/$target';
}

/// Les routines quotidiennes et hebdomadaires de [routines] sur la semaine (lundi vécu → dimanche) :
/// une case par jour, celles qui décrochent d'abord. Une routine mensuelle n'y figure pas.
List<RoutineRow> routineGrid({
  required List<Activity> routines,
  required List<HabitHit> hits,
  required DateTime now,
  required int dayStartMin,
}) {
  final t = livedDate(now, dayStartMin);
  final today = DateTime(t.year, t.month, t.day);
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final todayIdx = today.weekday - 1;
  final ids = {for (final r in routines) r.id};
  final per = <String, List<int>>{for (final id in ids) id: List<int>.filled(7, 0)};
  for (final h in hits) {
    if (!ids.contains(h.habitId)) continue;
    final d = livedDate(h.ts, dayStartMin);
    final i = DateTime(d.year, d.month, d.day).difference(monday).inDays;
    if (i >= 0 && i < 7) per[h.habitId]![i]++;
  }
  final rows = <RoutineRow>[];
  for (final r in routines) {
    if (r.deleted || !r.isHabit || r.habitFreq == HabitFreq.monthly) continue;
    final k = per[r.id]!;
    final target = (r.habitTarget ?? 1) < 1 ? 1 : (r.habitTarget ?? 1);
    if (r.habitFreq == HabitFreq.weekly) {
      final count = k.fold(0, (a, b) => a + b);
      final cells = [for (var i = 0; i < 7; i++) i > todayIdx ? RoutineCell.future : (k[i] > 0 ? RoutineCell.done : RoutineCell.missed)];
      // Attendu à ce jour, au prorata des jours PASSÉS (aujourd'hui n'est pas encore perdu).
      final expected = (target * todayIdx / 7).floor();
      rows.add(RoutineRow(routine: r, cells: cells, count: count, target: target, behind: count < expected));
    } else {
      final cells = [
        for (var i = 0; i < 7; i++)
          i > todayIdx ? RoutineCell.future : (k[i] >= target ? RoutineCell.done : (k[i] > 0 ? RoutineCell.partial : RoutineCell.missed)),
      ];
      final doneDays = cells.where((c) => c == RoutineCell.done).length;
      final missedPast = [for (var i = 0; i < todayIdx; i++) cells[i]].where((c) => c != RoutineCell.done).length;
      rows.add(RoutineRow(routine: r, cells: cells, count: doneDays, target: todayIdx + 1, behind: missedPast > 0));
    }
  }
  rows.sort((a, b) {
    if (a.behind != b.behind) return a.behind ? -1 : 1;
    return a.routine.name.toLowerCase().compareTo(b.routine.name.toLowerCase());
  });
  return rows;
}
