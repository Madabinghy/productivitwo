import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show kKeptRatio, mondayOf, ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Semaines tenues (lot 2 de la gamification moyen terme, 2026-10-30) : une
/// semaine calendaire close (lundi → dimanche) est TENUE quand le Contrat
/// d'Engagement atteint [kKeptRatio] — moyenne des parts faites des routines
/// engagées (celles des objectifs qui couvraient la semaine ; aucune → toutes
/// les routines qui existaient). Les jours gelés par une veille réduisent la
/// cible ; une semaine sans rien d'attendu est neutre (ni tenue ni ratée).
/// Chaque semaine tenue forge une braise (`embers.dart`, `heldWeekYmds`).
const kHeldWeekTiers = [4, 12, 26, 52];

enum WeekState { held, missed, neutral, current }

class HeldWeek {
  /// Lundi de la semaine (`YYYY-MM-DD`).
  final String monday;
  final WeekState state;
  /// Part du contrat faite (0..1), null pour une semaine neutre.
  final double? pct;
  /// Neutre parce qu'en veille (au moins un jour gelé).
  final bool rest;
  const HeldWeek(this.monday, this.state, {this.pct, this.rest = false});
  String get sunday => _shift(monday, 6);
}

class HeldWeeks {
  /// De la plus ancienne à la semaine en cours (incluse, état `current`).
  final List<HeldWeek> weeks;
  /// Semaines tenues d'affilée jusqu'à la dernière semaine close (neutres enjambées).
  final int current;
  final int longest;
  /// Dimanche de la semaine où chaque palier de [kHeldWeekTiers] tombe.
  final List<DateTime?> tierDates;
  /// Coches qui manquent encore à la semaine en cours pour atteindre le seuil (0 = tenue).
  final int missing;
  /// Routines engagées de la semaine en cours.
  final Set<String> engagedNow;
  const HeldWeeks({this.weeks = const [], this.current = 0, this.longest = 0, this.tierDates = const [null, null, null, null], this.missing = 0, this.engagedNow = const {}});

  HeldWeek? get thisWeek => weeks.isNotEmpty && weeks.last.state == WeekState.current ? weeks.last : null;
  int get heldCount => weeks.where((w) => w.state == WeekState.held).length;
  int get closedCount => weeks.where((w) => w.state == WeekState.held || w.state == WeekState.missed).length;
  /// Dimanches des semaines tenues (sources de braises).
  List<String> get heldSundays => [for (final w in weeks) if (w.state == WeekState.held) w.sunday];
  static const empty = HeldWeeks();
}

String _shift(String ymd, int days) {
  final d = DateTime.parse(ymd);
  return ymdOf(DateTime(d.year, d.month, d.day + days));
}

bool _isRoutine(Activity a) => !a.deleted && a.isHabit && a.habitFreq != null && a.habitFreq != HabitFreq.monthly;

/// Routines engagées sur la semaine [monday] : celles des objectifs (actifs ou
/// atteints) dont la période la couvre ; aucune → null (toutes les routines).
Set<String>? engagedForWeek(Iterable<StrategicObjective> objectives, DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  final ids = <String>{};
  for (final o in objectives) {
    if (o.status == 'archived') continue;
    final start = o.startDate ?? o.createdAt;
    final end = o.endDate;
    if (DateTime(start.year, start.month, start.day).isAfter(sunday)) continue;
    if (end != null && DateTime(end.year, end.month, end.day).isBefore(monday)) continue;
    for (final c in o.routineCommitments) {
      ids.add(c.activityId);
    }
  }
  return ids.isEmpty ? null : ids;
}

/// Cible d'une routine sur une semaine dont [open] jours ne sont pas gelés.
int weekTargetFor(Activity a, int open) {
  final base = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
  if (a.habitFreq == HabitFreq.daily) return base * open;
  return (base * open / 7).ceil();
}

/// Coches minimales pour porter la moyenne des parts à [kKeptRatio] (les plus
/// petites cibles d'abord : chaque coche y pèse le plus).
int missingHits(List<(int done, int target)> parts) {
  if (parts.isEmpty) return 0;
  final need = kKeptRatio * parts.length;
  var sum = parts.fold<double>(0, (s, p) => s + (p.$1 / p.$2).clamp(0.0, 1.0));
  if (sum >= need - 1e-9) return 0;
  final left = [for (final p in parts) if (p.$1 < p.$2) (p.$2 - p.$1, p.$2)]..sort((a, b) => a.$2.compareTo(b.$2));
  var n = 0;
  for (final (room, target) in left) {
    for (var k = 0; k < room; k++) {
      sum += 1 / target;
      n++;
      if (sum >= need - 1e-9) return n;
    }
  }
  return n;
}

HeldWeeks heldWeeks({
  required List<Activity> activities,
  required List<HabitHit> hits,
  required Iterable<StrategicObjective> objectives,
  required DateTime now,
  int dayStartMin = kDefaultDayStartMin,
  Set<String> Function(Activity a)? frozenOf,
}) {
  final routines = activities.where(_isRoutine).toList();
  if (routines.isEmpty) return HeldWeeks.empty;
  final byId = {for (final a in routines) a.id: a};
  final count = <String, Map<String, int>>{}; // id → ymd → hits
  DateTime? first;
  for (final h in hits) {
    if (!byId.containsKey(h.habitId)) continue;
    final d = livedDate(h.ts, dayStartMin);
    final y = ymdOf(d);
    final m = count.putIfAbsent(h.habitId, () => {});
    m[y] = (m[y] ?? 0) + 1;
    if (first == null || d.isBefore(first)) first = d;
  }
  if (first == null) return HeldWeeks.empty;
  final today = livedDate(now, dayStartMin);
  final thisMonday = mondayOf(today);
  final weeks = <HeldWeek>[];
  var missing = 0;
  var engagedNow = <String>{};
  for (var m = mondayOf(first); !m.isAfter(thisMonday); m = DateTime(m.year, m.month, m.day + 7)) {
    final isCurrent = m == thisMonday;
    final sunday = DateTime(m.year, m.month, m.day + 6);
    final engaged = engagedForWeek(objectives, m);
    final pool = [
      for (final a in routines)
        if (engaged == null ? !DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day).isAfter(sunday) : engaged.contains(a.id)) a
    ];
    final days = [for (var i = 0; i < 7; i++) ymdOf(DateTime(m.year, m.month, m.day + i))];
    final parts = <(int, int)>[];
    var anyRest = false;
    for (final a in pool) {
      final frozen = frozenOf?.call(a) ?? const <String>{};
      final open = days.where((y) => !frozen.contains(y)).length;
      if (open < 7) anyRest = true;
      final t = weekTargetFor(a, open);
      if (t <= 0) continue;
      final c = count[a.id];
      final done = c == null ? 0 : days.fold<int>(0, (s, y) => s + (c[y] ?? 0));
      parts.add((done, t));
    }
    final pct = parts.isEmpty ? null : parts.fold<double>(0, (s, p) => s + (p.$1 / p.$2).clamp(0.0, 1.0)) / parts.length;
    final y = ymdOf(m);
    if (isCurrent) {
      weeks.add(HeldWeek(y, WeekState.current, pct: pct, rest: anyRest));
      missing = missingHits(parts);
      engagedNow = {for (final a in pool) a.id};
    } else if (pct == null) {
      weeks.add(HeldWeek(y, WeekState.neutral, rest: anyRest));
    } else {
      weeks.add(HeldWeek(y, pct >= kKeptRatio - 1e-9 ? WeekState.held : WeekState.missed, pct: pct, rest: anyRest));
    }
  }
  // Séries sur les semaines closes, neutres enjambées.
  final tierDates = List<DateTime?>.filled(kHeldWeekTiers.length, null);
  var run = 0, longest = 0;
  for (final w in weeks) {
    if (w.state == WeekState.held) {
      run++;
      if (run > longest) longest = run;
      for (var i = 0; i < kHeldWeekTiers.length; i++) {
        if (tierDates[i] == null && run >= kHeldWeekTiers[i]) tierDates[i] = DateTime.parse(w.sunday);
      }
    } else if (w.state == WeekState.missed) {
      run = 0;
    }
  }
  return HeldWeeks(weeks: weeks, current: run, longest: longest, tierDates: tierDates, missing: missing, engagedNow: engagedNow);
}
