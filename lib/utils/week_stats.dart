import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/mode.dart' show isResting;
import 'package:productivitwo_v1/utils/budget_window.dart' show budgetWindowStart, budgetDayIndex;
import 'package:productivitwo_v1/utils/engagement_stats.dart';

/// Onglet Stats « une carte, une fiche » (lot 3, 2026-10) : logique pure de
/// la carte MA SEMAINE et des lignes par domaine. Semaine CALENDAIRE (lundi →
/// maintenant), même lecture que les objectifs : fait / minimum vital avec le
/// repère « attendu à ce jour » = minimum quotidien × jours écoulés.

/// Minutes de chrono par activité entre [from] et [to] (sessions fermées, et
/// session ouverte jusqu'à [to]) ; les sessions supprimées ne comptent pas.
Map<String, int> minutesByActivity(List<Session> sessions, DateTime from, DateTime to) {
  final out = <String, int>{};
  for (final s in sessions) {
    if (s.deleted) continue;
    final end = s.endAt ?? to;
    final a = s.startAt.isBefore(from) ? from : s.startAt;
    final z = end.isAfter(to) ? to : end;
    final m = z.difference(a).inMinutes;
    if (m > 0) out[s.activityId] = (out[s.activityId] ?? 0) + m;
  }
  return out;
}

class DomainWeek {
  final Domain domain;
  final int doneMin; // depuis lundi
  final int goalMinDay; // minimum vital quotidien (0 = aucun)
  final int daysElapsed; // jour courant dans la fenêtre (lundi = 1 … 7, ou 1 … 14)
  /// Fenêtre de budget (Modes et coups lot 4) : 7 = semaine calendaire, 14 = quinzaine à départ fixe.
  final int windowDays;
  final int routinesReached;
  final int routinesTotal;
  /// Domaine en veille (Modes et coups) : `YYYY-MM-DD` de fin, le minimum ne compte plus.
  final String? restUntil;
  const DomainWeek({
    required this.domain,
    required this.doneMin,
    required this.goalMinDay,
    required this.daysElapsed,
    required this.routinesReached,
    required this.routinesTotal,
    this.restUntil,
    this.windowDays = 7,
  });

  bool get resting => restUntil != null;

  int get weekMin => goalMinDay * windowDays;
  int get expectedMin => goalMinDay * daysElapsed;
  bool get hasGoal => goalMinDay > 0;
  /// Part de l'attendu à ce jour (jauge Objectifs) ; sans minimum, 100.
  int get pctInt => !hasGoal ? 100 : ((doneMin / expectedMin) * 100).round();
  int get deltaMin => doneMin - expectedMin;
}

/// Minimum vital quotidien d'un domaine : le sien s'il est réglé à la main,
/// sinon la somme des objectifs quotidiens de ses activités-temps.
int domainGoalMinDay(Domain d, Iterable<Activity> activities) {
  if (!d.autoGoal) return d.goalMinDay ?? 0;
  return activities.where((a) => a.domainId == d.id && !a.isHabit && !a.deleted).fold<int>(0, (s, a) => s + a.goalMin);
}

List<DomainWeek> domainWeeks({
  required List<Domain> domains,
  required List<Activity> activities,
  required List<Session> sessions,
  required List<HabitHit> hits,
  required DateTime now,
  Map<String, String> rest = const {},
  int windowDays = 7,
}) {
  final monday = mondayOf(now);
  final windowStart = budgetWindowStart(now, windowDays);
  final byActivity = minutesByActivity(sessions, windowStart, now);
  final domainOf = {for (final a in activities) a.id: a.domainId};
  final doneByDomain = <String, int>{};
  byActivity.forEach((id, m) {
    final d = domainOf[id];
    if (d != null) doneByDomain[d] = (doneByDomain[d] ?? 0) + m;
  });
  final eng = weekEngagements(activities: activities, hits: hits, weekStart: monday);
  final out = <DomainWeek>[];
  for (final d in domains) {
    if (d.deleted) continue;
    final mine = eng.where((e) => e.domainId == d.id).toList();
    final resting = isResting(d.id, rest, now);
    out.add(DomainWeek(
      domain: d,
      doneMin: doneByDomain[d.id] ?? 0,
      goalMinDay: resting ? 0 : domainGoalMinDay(d, activities),
      restUntil: resting ? rest[d.id] : null,
      daysElapsed: budgetDayIndex(now, windowDays),
      windowDays: windowDays,
      // Au rythme à ce jour (prorata du jour de la semaine), pas sur la cible entière.
      routinesReached: mine.where((e) => _onTrackToDate(e, now.weekday)).length,
      routinesTotal: mine.length,
    ));
  }
  // Les plus en retard d'abord (avec minimum), puis les autres par temps fait.
  out.sort((a, b) {
    if (a.resting != b.resting) return a.resting ? 1 : -1;
    if (a.hasGoal != b.hasGoal) return a.hasGoal ? -1 : 1;
    if (a.hasGoal) return a.pctInt.compareTo(b.pctInt);
    return b.doneMin.compareTo(a.doneMin);
  });
  return out;
}

/// MA SEMAINE : engagements des objectifs en cours (décision 2026-10-26 : les
/// routines rattachées à un objectif ; aucune → toutes), chrono de la semaine.
bool _onTrackToDate(EngagementStat e, int daysElapsed) {
  final x = expectedToDate(e.target, daysElapsed);
  return x <= 0 || (e.done / x) >= kKeptRatio;
}

/// Attendu À CE JOUR d'un engagement hebdo (2026-10) : cible × jours écoulés
/// / 7, arrondi — un lundi, « 3 fois par semaine » n'attend rien encore, le
/// mercredi 1, le dimanche 3. Avant, la semaine était jugée sur la cible
/// entière dès le lundi (« Semaine en retard » à 9 h le premier jour).
int expectedToDate(int target, int daysElapsed) => (target * daysElapsed / 7).round().clamp(0, target);

class WeekSummary {
  final List<EngagementStat> engagements;
  final int chronoMin;
  final int daysElapsed;
  /// Vrai quand les engagements sont ceux des objectifs (sinon : toutes les routines).
  final bool fromObjectives;
  const WeekSummary({required this.engagements, required this.chronoMin, required this.daysElapsed, required this.fromObjectives});

  int expectedOf(EngagementStat e) => expectedToDate(e.target, daysElapsed);

  /// Part de l'attendu à ce jour (plafonnée à 1 ; rien d'attendu → 1).
  double ratioOf(EngagementStat e) {
    final x = expectedOf(e);
    return x <= 0 ? 1.0 : (e.done / x).clamp(0.0, 1.0).toDouble();
  }

  /// Au rythme = [kKeptRatio] de l'attendu à ce jour (même seuil que « tenu »).
  bool onTrack(EngagementStat e) => ratioOf(e) >= kKeptRatio;

  /// Moyenne des parts faites À CE JOUR (carte MA SEMAINE, anneau).
  int get pct =>
      engagements.isEmpty ? 0 : ((engagements.fold<double>(0, (s, e) => s + ratioOf(e)) / engagements.length) * 100).round();
  int get kept => engagements.where(onTrack).length;

  /// Lecture sur la SEMAINE ENTIÈRE (fiche : ce qu'il reste d'ici dimanche).
  int get pctWeek => engagementPct(engagements);
  int get keptWeek => engagements.where((e) => e.kept).length;
}

WeekSummary weekSummary({
  required List<Activity> activities,
  required List<HabitHit> hits,
  required List<Session> sessions,
  required Iterable<StrategicObjective> objectives,
  required DateTime now,
}) {
  final monday = mondayOf(now);
  final only = engagedRoutineIds(objectives);
  final eng = weekEngagements(activities: activities, hits: hits, weekStart: monday, onlyIds: only);
  final chrono = minutesByActivity(sessions, monday, now).values.fold<int>(0, (s, m) => s + m);
  return WeekSummary(engagements: eng, chronoMin: chrono, daysElapsed: now.weekday, fromObjectives: only != null && only.isNotEmpty);
}
