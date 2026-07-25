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

/// Engagements de la semaine commençant à [weekStart] (lundi).
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

/// Tendance S-3 → S : % d'engagements tenus par semaine.
/// [hits] doit couvrir au moins 4 semaines.
List<({String startYmd, int pct})> fourWeekTrend({
  required List<Activity> activities,
  required List<HabitHit> hits,
  Set<String>? domainIds,
}) {
  final habits = _weeklyHabits(activities, domainIds: domainIds);
  final monday = mondayOf(DateTime.now());
  return [
    for (var back = 3; back >= 0; back--)
      () {
        final ws = monday.subtract(Duration(days: 7 * back));
        final kept = habits
            .where((h) => _doneInWeek(h.id, hits, ws) >= _weekTarget(h))
            .length;
        return (
          startYmd: ymdOf(ws),
          pct: habits.isEmpty ? 0 : ((kept / habits.length) * 100).round(),
        );
      }(),
  ];
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
