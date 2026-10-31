import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/acquired.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

/// Montre suisse et Métronome (maquette validée 2026-10-30) : les deux moitiés
/// de la Journée parfaite. Montre suisse = à la bascule, chaque activité avec
/// un minimum vital a fait 7 × son minimum sur les 7 derniers jours (fenêtre
/// GLISSANTE, maquette « Montre suisse glissante » : pas de mur le lundi, le
/// week-end compte encore) ; Métronome = toutes les routines quotidiennes
/// du jour atteintes. Hors domaines en veille et routines acquises ; un jour
/// sans rien à tenir est neutre. On compte les journées gagnées (paliers
/// [kHalfDayTiers]) et le record d'affilée. Aucune braise. Logique pure.
const kHalfDayTiers = [5, 20, 50, 100];

/// Fenêtre glissante de Montre suisse, aujourd'hui compris.
const kWatchWindowDays = 7;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Une activité-temps face à sa fenêtre glissante, à la fin d'un jour (ou maintenant).
class ActivityPace {
  final Activity activity;
  /// Minutes sur la fenêtre, aujourd'hui compris.
  final int doneMin;
  /// Minimum × jours comptés de la fenêtre (jours gelés et jours d'avant la création exclus).
  final int expectedMin;
  /// Dont aujourd'hui (le reste vient des jours passés de la fenêtre).
  final int todayMin;
  /// Minutes du jour le plus ancien, qui sort de la fenêtre ce soir.
  final int leavingMin;
  const ActivityPace(this.activity, this.doneMin, this.expectedMin, {this.todayMin = 0, this.leavingMin = 0});
  bool get onPace => doneMin >= expectedMin;
  int get missingMin => onPace ? 0 : expectedMin - doneMin;
  int get pastMin => doneMin - todayMin;
  int get aheadMin => onPace ? doneMin - expectedMin : 0;
  /// Cible du jour = ce qu'il reste à faire aujourd'hui après les 6 jours
  /// passés (le retard pris s'y ajoute, l'avance la réduit).
  int get dayTargetMin {
    final t = expectedMin - pastMin;
    return t > 0 ? t : 0;
  }
  /// Ce qu'il faudra demain pour rester couverte, si rien d'autre n'est fait
  /// aujourd'hui (le jour le plus ancien sort, demain entre avec son minimum).
  int get tomorrowNeedMin {
    final need = expectedMin - (doneMin - leavingMin);
    return need > 0 ? need : 0;
  }
}

/// Minutes de chrono par activité et par jour calendaire (session coupée à minuit).
Map<String, Map<String, int>> minutesByActivityDay(List<Session> sessions, DateTime now) {
  final out = <String, Map<String, int>>{};
  for (final s in sessions) {
    if (s.deleted) continue;
    var from = s.startAt;
    final end = s.endAt ?? now;
    while (end.isAfter(from)) {
      final next = _day(from).add(const Duration(days: 1));
      final stop = end.isBefore(next) ? end : next;
      final m = stop.difference(from).inMinutes;
      if (m > 0) {
        final byDay = out.putIfAbsent(s.activityId, () => {});
        final k = ymdOf(from);
        byDay[k] = (byDay[k] ?? 0) + m;
      }
      from = stop;
    }
  }
  return out;
}

/// Les activités qui comptent pour Montre suisse le jour [day] (temps, minimum
/// vital > 0, créées avant, domaine pas en veille ce jour) et leur fenêtre des
/// [kWatchWindowDays] derniers jours : un jour gelé ou d'avant la création ne
/// réclame rien.
List<ActivityPace> paceOn(
  DateTime day, {
  required List<Activity> activities,
  required Map<String, Map<String, int>> minutes,
  Set<String> Function(Activity a)? frozenOf,
}) {
  final d = _day(day);
  final ymd = ymdOf(d);
  final out = <ActivityPace>[];
  for (final a in activities) {
    if (a.deleted || a.isHabit || a.goalMin <= 0) continue;
    final created = _day(a.createdAt);
    if (created.isAfter(d)) continue;
    final frozen = frozenOf?.call(a) ?? const <String>{};
    if (frozen.contains(ymd)) continue;
    final byDay = minutes[a.id] ?? const {};
    var done = 0, counted = 0, leaving = 0;
    for (var i = kWatchWindowDays - 1; i >= 0; i--) {
      final x = d.subtract(Duration(days: i));
      final k = ymdOf(x);
      final m = byDay[k] ?? 0;
      done += m;
      if (i == kWatchWindowDays - 1) leaving = m;
      if (!x.isBefore(created) && !frozen.contains(k)) counted++;
    }
    out.add(ActivityPace(a, done, a.goalMin * counted, todayMin: byDay[ymd] ?? 0, leavingMin: leaving));
  }
  return out;
}

/// Journées gagnées d'un badge de demi-journée.
class HalfDays {
  final List<String> won;
  final int neutral;
  final int missed;
  final int current;
  final int longest;
  final List<DateTime?> tierDates;
  const HalfDays({required this.won, required this.neutral, required this.missed, required this.current, required this.longest, required this.tierDates});
  static const empty = HalfDays(won: [], neutral: 0, missed: 0, current: 0, longest: 0, tierDates: [null, null, null, null]);
}

/// [outcome] : true = gagnée, false = manquée, null = neutre ; jours en ordre.
HalfDays halfDaysFrom(List<(String, bool?)> outcomes) {
  final won = <String>[];
  var neutral = 0, missed = 0, run = 0, longest = 0;
  for (final (ymd, o) in outcomes) {
    if (o == null) {
      neutral++;
      continue; // neutre : enjambé sans casser
    }
    if (o) {
      won.add(ymd);
      run++;
      if (run > longest) longest = run;
    } else {
      missed++;
      run = 0;
    }
  }
  return HalfDays(
    won: won,
    neutral: neutral,
    missed: missed,
    current: run,
    longest: longest,
    tierDates: [for (final t in kHalfDayTiers) won.length >= t ? DateTime.parse(won[t - 1]) : null],
  );
}

/// Montre suisse sur les jours [ymds] (clos, en ordre).
HalfDays watchDays({
  required List<String> ymds,
  required List<Activity> activities,
  required List<Session> sessions,
  required DateTime now,
  Set<String> Function(Activity a)? frozenOf,
}) {
  final minutes = minutesByActivityDay(sessions, now);
  return halfDaysFrom([
    for (final ymd in ymds)
      () {
        final pace = paceOn(DateTime.parse(ymd), activities: activities, minutes: minutes, frozenOf: frozenOf);
        return (ymd, pace.isEmpty ? null : pace.every((p) => p.onPace));
      }(),
  ]);
}

/// Métronome sur les jours [ymds] (clos, en ordre).
HalfDays metronomeDays({
  required List<String> ymds,
  required List<Activity> activities,
  required Map<String, Set<String>> reachedDaysByRoutine,
  Set<String> Function(Activity a)? frozenOf,
  Map<String, Acquired> acquired = const {},
}) {
  final routines = activities.where((a) => !a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily).toList();
  return halfDaysFrom([
    for (final ymd in ymds)
      () {
        final d = DateTime.parse(ymd);
        var due = 0, reached = 0;
        for (final a in routines) {
          if (_day(a.createdAt).isAfter(d)) continue;
          if (isAcquiredOn(acquired, a.id, ymd)) continue;
          if (frozenOf != null && frozenOf(a).contains(ymd)) continue;
          due++;
          if (reachedDaysByRoutine[a.id]?.contains(ymd) ?? false) reached++;
        }
        return (ymd, due == 0 ? null : reached == due);
      }(),
  ]);
}
