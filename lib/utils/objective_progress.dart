import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/progression.dart';

// ─── PROGRESSION DES OBJECTIFS STRATÉGIQUES ──────────────────────────────────
//
// Même sémantique que functions/src/objectives.ts (serveur) : fenêtre =
// semaine courante (lundi → maintenant), seuil onTrack = 70 % du cumul
// attendu au prorata des jours écoulés (identique à activity_behind_target).
// Fonctions pures, aucune dépendance Firestore — compilables web ET mobile.

class CommitmentProgress {
  final String type; // 'time' | 'routine'
  final String activityId;
  final String name;
  final int target; // minutes/sem (time) ou cible hebdo équivalente (routine)
  final int done; // minutes ou hits depuis lundi
  final bool onTrack;

  CommitmentProgress({
    required this.type,
    required this.activityId,
    required this.name,
    required this.target,
    required this.done,
    required this.onTrack,
  });

  double get pct => target <= 0 ? 0 : (done / target).clamp(0.0, 1.0);
}

class ObjectiveProgress {
  final double? weekPercent; // 0..1 — moyenne des engagements (null si aucun)
  final double? horizonPct; // 0..1 — temps écoulé sur [startDate, endDate]
  final int? daysLeft; // jours restants avant endDate
  final List<CommitmentProgress> items;

  ObjectiveProgress({
    required this.weekPercent,
    required this.horizonPct,
    required this.daysLeft,
    required this.items,
  });
}

/// Cible hebdo équivalente d'une routine (daily ×7, weekly ×1, monthly ×7/30).
int weeklyRoutineTarget(Activity a) {
  final target = a.effHabitTarget < 1 ? 1 : a.effHabitTarget;
  switch (a.effHabitFreq) {
    case HabitFreq.daily:
      return target * 7;
    case HabitFreq.weekly:
      return target;
    case HabitFreq.monthly:
      final t = ((target * 7) / 30).round();
      return t < 1 ? 1 : t;
  }
}

ObjectiveProgress computeObjectiveProgress(
  StrategicObjective o,
  List<Activity> activities,
  List<Session> sessions,
  List<HabitHit> habitHits,
  DateTime now,
) {
  final monday = mondayOf(now);
  final prorate = (now.weekday / 7) * 0.7;
  final actById = {for (final a in activities) a.id: a};

  // Minutes loggées depuis lundi, par activité
  final minSinceMonday = <String, int>{};
  for (final s in sessions) {
    final end = s.endAt;
    if (end == null || s.startAt.isBefore(monday)) continue;
    final mins = end.difference(s.startAt).inMinutes;
    if (mins > 0) {
      minSinceMonday[s.activityId] = (minSinceMonday[s.activityId] ?? 0) + mins;
    }
  }

  // Hits de routine depuis lundi
  final hitsSinceMonday = <String, int>{};
  for (final h in habitHits) {
    if (h.ts.isBefore(monday)) continue;
    hitsSinceMonday[h.habitId] = (hitsSinceMonday[h.habitId] ?? 0) + 1;
  }

  final items = <CommitmentProgress>[];
  for (final c in o.timeCommitments) {
    final a = actById[c.activityId];
    final target = c.weeklyMin < 1 ? 1 : c.weeklyMin;
    final done = minSinceMonday[c.activityId] ?? 0;
    items.add(CommitmentProgress(
      type: 'time',
      activityId: c.activityId,
      name: a?.name ?? c.activityId,
      target: target,
      done: done,
      onTrack: done >= target * prorate,
    ));
  }
  for (final c in o.routineCommitments) {
    final a = actById[c.activityId];
    final target = a != null ? weeklyRoutineTarget(a) : 1;
    final done = hitsSinceMonday[c.activityId] ?? 0;
    items.add(CommitmentProgress(
      type: 'routine',
      activityId: c.activityId,
      name: a?.name ?? c.activityId,
      target: target,
      done: done,
      onTrack: done >= target * prorate,
    ));
  }

  double? weekPercent;
  if (items.isNotEmpty) {
    weekPercent =
        items.map((i) => i.pct).reduce((a, b) => a + b) / items.length;
  }

  double? horizonPct;
  int? daysLeft;
  final start = o.startDate, end = o.endDate;
  if (end != null) {
    daysLeft = DateTime(end.year, end.month, end.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (start != null && end.isAfter(start)) {
      horizonPct = (now.difference(start).inMinutes /
              end.difference(start).inMinutes)
          .clamp(0.0, 1.0);
    }
  }

  return ObjectiveProgress(
    weekPercent: weekPercent,
    horizonPct: horizonPct,
    daysLeft: daysLeft,
    items: items,
  );
}
