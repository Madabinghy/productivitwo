import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show faithfulReadings;
import 'package:productivitwo_v1/utils/objective_trajectory.dart';

/// Un relevé de métrique dû aujourd'hui (2026-10-30) : la série de relevés
/// (badge Relevé fidèle) tient tant que l'écart entre deux relevés reste
/// ≤ `checkInEvery` + 1 jour. Le dernier jour, elle se perd ce soir.
class ReadingDue {
  final StrategicObjective objective;
  /// Jours depuis le dernier relevé (ou le début de l'objectif).
  final int daysSince;
  final int every;
  /// Relevés sans trou en cours (0 = aucune série à sauver).
  final int series;
  const ReadingDue({required this.objective, required this.daysSince, required this.every, required this.series});

  /// Dernier jour pour garder la série : demain, l'écart dépassera la tolérance.
  bool get lastDay => series > 0 && daysSince >= every + 1;
  String get name => objective.metric?.label.isNotEmpty == true ? objective.metric!.label : objective.title;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Relevés dus aujourd'hui, ceux dont la série se perd ce soir d'abord.
List<ReadingDue> readingsDue(List<StrategicObjective> objectives, DateTime now) {
  final out = <ReadingDue>[];
  for (final o in objectives) {
    if (!isReadingDue(o, now)) continue;
    final every = o.checkInEvery < 1 ? 7 : o.checkInEvery;
    final last = latestReading(o);
    final ref = last == null ? objectiveStart(o) : (DateTime.tryParse(last.date) ?? objectiveStart(o));
    final days = _day(now).difference(_day(ref)).inDays;
    // Au-delà de la tolérance, la série est déjà cassée.
    final series = last == null || days > every + 1 ? 0 : faithfulReadings(o).current;
    out.add(ReadingDue(objective: o, daysSince: days, every: every, series: series));
  }
  out.sort((a, b) {
    if (a.lastDay != b.lastDay) return a.lastDay ? -1 : 1;
    return b.series.compareTo(a.series);
  });
  return out;
}
