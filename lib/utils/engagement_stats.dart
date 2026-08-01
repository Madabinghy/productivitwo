import 'package:productivitwo_v1/models.dart';

/// Statistiques d'engagements hebdo — MÊMES règles que le dashboard serveur
/// (functions/src/coaching.ts, buildDashboard) : routines daily/weekly des
/// domaines considérés, cible daily ramenée à la semaine (×7), monthly hors
/// tendance. Utilisé par le tableau de bord du coaché (« ce que voit ton
/// coach, sur TES données ») — une seule vérité de calcul côté client.

class EngagementStat {
  final String id;
  final String domainId;
  final String label;
  final int target;
  final int done;

  EngagementStat({
    required this.id,
    required this.domainId,
    required this.label,
    required this.target,
    required this.done,
  });

  bool get kept => done >= target;
}

DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String ymdOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<Activity> _weeklyHabits(Iterable<Activity> activities,
        {Set<String>? domainIds}) =>
    activities
        .where((a) =>
            !a.deleted &&
            a.isHabit &&
            a.habitFreq != null &&
            a.habitFreq != HabitFreq.monthly &&
            (domainIds == null || domainIds.contains(a.domainId)))
        .toList();

int _weekTarget(Activity h) {
  final base = h.habitTarget ?? 1;
  final t = h.habitFreq == HabitFreq.daily ? base * 7 : base;
  return t <= 0 ? 1 : t;
}

int _doneInWeek(String habitId, List<HabitHit> hits, DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 7));
  return hits
      .where((h) =>
          h.habitId == habitId && !h.ts.isBefore(weekStart) && h.ts.isBefore(end))
      .length;
}

int _doneInRange(
    String habitId, List<HabitHit> hits, DateTime from, DateTime to) {
  return hits
      .where((h) =>
          h.habitId == habitId && !h.ts.isBefore(from) && h.ts.isBefore(to))
      .length;
}

/// Engagements de la semaine commençant à [weekStart] (lundi) — semaines
/// calendaires révolues de la tendance.
List<EngagementStat> weekEngagements({
  required List<Activity> activities,
  required List<HabitHit> hits,
  required DateTime weekStart,
  Set<String>? domainIds,
}) {
  return [
    for (final h in _weeklyHabits(activities, domainIds: domainIds))
      EngagementStat(
        id: h.id,
        domainId: h.domainId,
        label: h.name,
        target: _weekTarget(h),
        done: _doneInWeek(h.id, hits, weekStart),
      ),
  ];
}

/// Suivi AU FIL DE L'EAU : fenêtre GLISSANTE de 7 jours — un lundi matin,
/// la semaine calendaire serait quasi vide (chiffres anxiogènes sans info).
List<EngagementStat> rollingWeekEngagements({
  required List<Activity> activities,
  required List<HabitHit> hits,
  Set<String>? domainIds,
}) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 7));
  return [
    for (final h in _weeklyHabits(activities, domainIds: domainIds))
      EngagementStat(
        id: h.id,
        domainId: h.domainId,
        label: h.name,
        target: _weekTarget(h),
        done: _doneInRange(h.id, hits, from, now.add(const Duration(minutes: 1))),
      ),
  ];
}

/// Tendance : 3 semaines calendaires RÉVOLUES (S-3 → S-1), puis les 7 jours
/// glissants comme dernier bloc — cohérent avec [rollingWeekEngagements].
/// [hits] doit couvrir au moins 4 semaines.
List<({String label, int pct})> fourWeekTrend({
  required List<Activity> activities,
  required List<HabitHit> hits,
  Set<String>? domainIds,
}) {
  final habits = _weeklyHabits(activities, domainIds: domainIds);
  final monday = mondayOf(DateTime.now());
  int pctOf(int kept) =>
      habits.isEmpty ? 0 : ((kept / habits.length) * 100).round();
  final out = <({String label, int pct})>[
    for (var back = 3; back >= 1; back--)
      (
        label: 'S-$back',
        pct: pctOf(habits
            .where((h) =>
                _doneInWeek(h.id, hits,
                    monday.subtract(Duration(days: 7 * back))) >=
                _weekTarget(h))
            .length),
      ),
  ];
  final rolling = rollingWeekEngagements(
      activities: activities, hits: hits, domainIds: domainIds);
  out.add((
    label: '7 j',
    pct: pctOf(rolling.where((e) => e.kept).length),
  ));
  return out;
}

/// Engagements DU JOUR : les routines QUOTIDIENNES uniquement (les hebdo se
/// jugent sur 7 jours, pas sur une journée) — coches d'aujourd'hui vs cible
/// quotidienne. Alimente l'étage AUJOURD'HUI de l'onglet Objectifs.
List<EngagementStat> todayEngagements({
  required List<Activity> activities,
  required List<HabitHit> hits,
  Set<String>? domainIds,
}) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  return [
    for (final a in activities)
      if (!a.deleted &&
          a.isHabit &&
          a.habitFreq == HabitFreq.daily &&
          (domainIds == null || domainIds.contains(a.domainId)))
        EngagementStat(
          id: a.id,
          domainId: a.domainId,
          label: a.name,
          target: (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1),
          done: _doneInRange(
              a.id, hits, midnight, now.add(const Duration(minutes: 1))),
        ),
  ];
}

/// Stat 7 jours glissants d'UNE routine (carte contexte de l'onglet
/// Maintenant). Cible hebdo-isée comme partout (daily ×7 ; monthly = cible
/// brute, à titre indicatif). Null si l'activité n'est pas une routine.
EngagementStat? rollingStatFor(Activity a, List<HabitHit> hits) {
  if (!a.isHabit) return null;
  final base = a.habitTarget ?? 1;
  final target = a.habitFreq == HabitFreq.daily ? base * 7 : base;
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 7));
  return EngagementStat(
    id: a.id,
    domainId: a.domainId,
    label: a.name,
    target: target <= 0 ? 1 : target,
    done: _doneInRange(a.id, hits, from, now.add(const Duration(minutes: 1))),
  );
}

/// Dernière coche d'une routine (toutes périodes confondues).
DateTime? lastHitOf(String habitId, List<HabitHit> hits) {
  DateTime? last;
  for (final h in hits) {
    if (h.habitId != habitId) continue;
    if (last == null || h.ts.isAfter(last)) last = h.ts;
  }
  return last;
}

/// Dernière activité (session démarrée ou routine cochée), bornée au
/// périmètre [activityIds] si fourni.
DateTime? lastActivityAt({
  required List<Session> sessions,
  required List<HabitHit> hits,
  Set<String>? activityIds,
}) {
  DateTime? last;
  for (final s in sessions) {
    if (activityIds != null && !activityIds.contains(s.activityId)) continue;
    if (last == null || s.startAt.isAfter(last)) last = s.startAt;
  }
  for (final h in hits) {
    if (activityIds != null && !activityIds.contains(h.habitId)) continue;
    if (last == null || h.ts.isAfter(last)) last = h.ts;
  }
  return last;
}

/// Minutes des 7 derniers jours par activité-temps (nom → minutes).
Map<String, int> weekMinutesByActivity({
  required List<Activity> activities,
  required List<Session> sessions,
  Set<String>? domainIds,
}) {
  final weekAgo = DateTime.now().subtract(const Duration(days: 7));
  final timeActs = {
    for (final a in activities)
      if (!a.deleted &&
          !a.isHabit &&
          (domainIds == null || domainIds.contains(a.domainId)))
        a.id: a,
  };
  final out = <String, int>{};
  for (final s in sessions) {
    if (s.startAt.isBefore(weekAgo)) continue;
    final act = timeActs[s.activityId];
    if (act == null) continue;
    final end = s.endAt;
    if (end == null || !end.isAfter(s.startAt)) continue;
    out[act.name] = (out[act.name] ?? 0) + end.difference(s.startAt).inMinutes;
  }
  return out;
}
