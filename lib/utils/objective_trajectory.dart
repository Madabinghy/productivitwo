import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

// ─── TRAJECTOIRE D'UN OBJECTIF ───────────────────────────────────────────────
//
// Deux lectures « où devrait-on en être aujourd'hui ? », même sémantique que
// functions/src/objective_trajectory.ts (garder alignés) :
//  • MOYENS  : minutes cumulées sur les activités engagées depuis le début de
//              l'objectif vs Σ weeklyMin × semaines écoulées (linéaire).
//  • RÉSULTAT : relevés de la métrique vs droite startValue → targetValue entre
//              startDate et endDate (linéaire). Sans métrique : pas de résultat.
// Début de l'objectif = startDate, sinon createdAt. Fonctions pures.

enum TrajectoryStatus { ahead, onTrack, behind, unknown }

class MeansTrajectory {
  final int doneMin; // minutes cumulées depuis le début
  final int expectedMin; // minutes attendues à ce jour
  final int totalMin; // minutes attendues sur tout l'horizon (0 = pas d'échéance)
  final TrajectoryStatus status;
  const MeansTrajectory({required this.doneMin, required this.expectedMin, required this.totalMin, required this.status});

  double get pctOfExpected => expectedMin <= 0 ? 0 : doneMin / expectedMin;
  double get pctOfTotal => totalMin <= 0 ? 0 : (doneMin / totalMin).clamp(0.0, 1.0);
}

class ResultTrajectory {
  final double startValue;
  final double targetValue;
  final double? latestValue; // dernier relevé (null si aucun)
  final String? latestDate;
  final double expectedValue; // valeur attendue aujourd'hui
  final TrajectoryStatus status;
  const ResultTrajectory({
    required this.startValue,
    required this.targetValue,
    required this.latestValue,
    required this.latestDate,
    required this.expectedValue,
    required this.status,
  });

  /// Progression réelle 0..1 (clampée) de start vers target.
  double get pct => _pct(startValue, targetValue, latestValue ?? startValue);

  /// Progression attendue 0..1.
  double get expectedPct => _pct(startValue, targetValue, expectedValue);

  /// Écart réel − attendu, signé dans le sens du progrès (> 0 = en avance).
  double get delta {
    final v = latestValue;
    if (v == null) return 0;
    final raw = v - expectedValue;
    return targetValue < startValue ? -raw : raw;
  }
}

class ObjectiveTrajectory {
  final DateTime start;
  final DateTime? end;
  final double? timePct; // 0..1 temps écoulé sur l'horizon (null sans échéance)
  final MeansTrajectory means;
  final ResultTrajectory? result;
  final int? daysSinceReading; // null = aucun relevé
  final bool readingDue;
  const ObjectiveTrajectory({
    required this.start,
    required this.end,
    required this.timePct,
    required this.means,
    required this.result,
    required this.daysSinceReading,
    required this.readingDue,
  });
}

double _pct(double start, double target, double v) {
  final span = target - start;
  if (span == 0) return v == target ? 1 : 0;
  return ((v - start) / span).clamp(0.0, 1.0);
}

TrajectoryStatus _statusOf(double ratio) {
  if (ratio.isNaN) return TrajectoryStatus.unknown;
  if (ratio >= 1.1) return TrajectoryStatus.ahead;
  if (ratio >= 0.85) return TrajectoryStatus.onTrack;
  return TrajectoryStatus.behind;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime objectiveStart(StrategicObjective o) => _day(o.startDate ?? o.createdAt);

/// Valeur attendue de la métrique à `at` : droite start → target sur
/// [start, end] ; sans échéance, on reste à startValue (rien à attendre).
double expectedMetricAt(ObjectiveMetric m, DateTime start, DateTime? end, DateTime at) {
  if (end == null || !end.isAfter(start)) return m.startValue;
  final t = (at.difference(start).inMinutes / end.difference(start).inMinutes).clamp(0.0, 1.0);
  return m.startValue + (m.targetValue - m.startValue) * t;
}

/// Minutes attendues à `at` : Σ weeklyMin × semaines écoulées (fractionnaires),
/// bornées à l'horizon.
int expectedMinutesAt(StrategicObjective o, DateTime start, DateTime? end, DateTime at) {
  var until = at;
  if (end != null && until.isAfter(end)) until = end;
  if (!until.isAfter(start)) return 0;
  final weeks = until.difference(start).inMinutes / (7 * 24 * 60);
  final perWeek = o.timeCommitments.fold<int>(0, (s, c) => s + c.weeklyMin);
  return (perWeek * weeks).round();
}

/// Minutes réellement passées depuis `start` sur les activités engagées.
int committedMinutesSince(StrategicObjective o, List<Session> sessions, DateTime start, DateTime now) {
  final ids = o.timeCommitments.map((c) => c.activityId).toSet();
  if (ids.isEmpty) return 0;
  var total = 0;
  for (final s in sessions) {
    if (s.deleted || !ids.contains(s.activityId)) continue;
    final end = s.endAt ?? now;
    if (end.isBefore(start) || s.startAt.isAfter(now)) continue;
    final from = s.startAt.isBefore(start) ? start : s.startAt;
    final to = end.isAfter(now) ? now : end;
    final m = to.difference(from).inMinutes;
    if (m > 0) total += m;
  }
  return total;
}

ObjectiveReading? latestReading(StrategicObjective o) {
  ObjectiveReading? best;
  for (final r in o.readings) {
    if (best == null || r.date.compareTo(best.date) > 0 ||
        (r.date == best.date && r.createdAt.isAfter(best.createdAt))) {
      best = r;
    }
  }
  return best;
}

/// Un relevé est dû quand la métrique existe et que le dernier relevé (ou le
/// début de l'objectif) date de `checkInEvery` jours ou plus.
bool isReadingDue(StrategicObjective o, DateTime now) {
  if (o.metric == null || o.status != 'active') return false;
  final every = o.checkInEvery < 1 ? 7 : o.checkInEvery;
  final last = latestReading(o);
  final ref = last == null ? objectiveStart(o) : (DateTime.tryParse(last.date) ?? objectiveStart(o));
  return _day(now).difference(_day(ref)).inDays >= every;
}

ObjectiveTrajectory computeObjectiveTrajectory(StrategicObjective o, List<Session> sessions, DateTime now) {
  final start = objectiveStart(o);
  final end = o.endDate == null ? null : _day(o.endDate!);
  double? timePct;
  if (end != null && end.isAfter(start)) {
    timePct = (now.difference(start).inMinutes / end.difference(start).inMinutes).clamp(0.0, 1.0);
  }

  final done = committedMinutesSince(o, sessions, start, now);
  final expected = expectedMinutesAt(o, start, end, now);
  final total = end == null ? 0 : expectedMinutesAt(o, start, end, end);
  final means = MeansTrajectory(
    doneMin: done,
    expectedMin: expected,
    totalMin: total,
    status: o.timeCommitments.isEmpty
        ? TrajectoryStatus.unknown
        : expected <= 0
            ? TrajectoryStatus.onTrack
            : _statusOf(done / expected),
  );

  ResultTrajectory? result;
  final m = o.metric;
  final last = latestReading(o);
  if (m != null) {
    final exp = expectedMetricAt(m, start, end, now);
    TrajectoryStatus st;
    if (last == null) {
      st = TrajectoryStatus.unknown;
    } else {
      final expPct = _pct(m.startValue, m.targetValue, exp);
      final realPct = _pct(m.startValue, m.targetValue, last.value);
      st = expPct <= 0 ? TrajectoryStatus.onTrack : _statusOf(realPct / expPct);
    }
    result = ResultTrajectory(
      startValue: m.startValue,
      targetValue: m.targetValue,
      latestValue: last?.value,
      latestDate: last?.date,
      expectedValue: exp,
      status: st,
    );
  }

  int? since;
  if (last != null) {
    final d = DateTime.tryParse(last.date);
    if (d != null) since = _day(now).difference(_day(d)).inDays;
  }

  return ObjectiveTrajectory(
    start: start,
    end: end,
    timePct: timePct,
    means: means,
    result: result,
    daysSinceReading: since,
    readingDue: isReadingDue(o, now),
  );
}

/// Points de la courbe attendue (un par jour entre start et end, bornés à
/// `maxPoints`) — pour tracer la ligne « où on devrait en être ».
List<({DateTime date, double value})> expectedCurve(ObjectiveMetric m, DateTime start, DateTime end,
    {int maxPoints = 60}) {
  if (!end.isAfter(start)) return [(date: start, value: m.startValue)];
  final days = end.difference(start).inDays;
  final step = days <= maxPoints ? 1 : (days / maxPoints).ceil();
  final out = <({DateTime date, double value})>[];
  for (var d = 0; d < days; d += step) {
    final at = start.add(Duration(days: d));
    out.add((date: at, value: expectedMetricAt(m, start, end, at)));
  }
  out.add((date: end, value: m.targetValue));
  return out;
}

/// Ajoute ou remplace le relevé du jour `date` (un seul par jour).
List<ObjectiveReading> upsertReading(List<ObjectiveReading> readings, ObjectiveReading r) {
  final out = readings.where((x) => x.date != r.date).toList()..add(r);
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

String todayYmd(DateTime now) => ymdOf(now);
