import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

/// « Le matin en trois choses » (audit lot 3) : avant 9 h, une carte en tête
/// d'Aujourd'hui avec le bloc clé de la journée, la routine la plus en retard
/// sur la semaine et l'action en retard la plus ancienne. Chaque ligne se
/// lance d'un tap. Logique pure, testée.

class MorningThree {
  final ScheduleBlock? keyBlock;
  final Activity? routine;
  final ({Project project, ProjectTask task})? overdue;
  const MorningThree({this.keyBlock, this.routine, this.overdue});

  int get count => (keyBlock != null ? 1 : 0) + (routine != null ? 1 : 0) + (overdue != null ? 1 : 0);
  bool get isEmpty => count == 0;
}

/// Fenêtre d'affichage : de 5 h à 9 h.
bool isMorningWindow(DateTime now) => now.hour >= 5 && now.hour < 9;

/// Bloc clé = le plus long bloc « projet » encore à faire ; à défaut le plus
/// long bloc à faire, quelle que soit sa catégorie.
ScheduleBlock? keyBlockOf(List<ScheduleBlock> blocks) {
  final live = blocks.where((b) => b.status == 'pending').toList();
  if (live.isEmpty) return null;
  final projects = live.where((b) => b.category == 'project' || b.projectId != null).toList();
  final pool = projects.isNotEmpty ? projects : live;
  pool.sort((a, b) {
    final d = b.durationMin.compareTo(a.durationMin);
    return d != 0 ? d : blockStartMin(a).compareTo(blockStartMin(b));
  });
  return pool.first;
}

/// Routine quotidienne la plus en retard sur 7 jours (ratio fait/attendu le
/// plus bas), parmi celles pas encore atteintes aujourd'hui.
Activity? laggingRoutineOf(
  List<Activity> activities, {
  required int Function(Activity a) weekDone,
  required int Function(Activity a) weekTarget,
  required bool Function(Activity a) reachedToday,
}) {
  Activity? best;
  double bestRatio = 2;
  for (final a in activities) {
    if (!a.isHabit || a.habitFreq != HabitFreq.daily || reachedToday(a)) continue;
    final t = weekTarget(a);
    if (t <= 0) continue;
    final r = weekDone(a) / t;
    if (r < bestRatio) {
      bestRatio = r;
      best = a;
    }
  }
  return best;
}

/// Action (tâche) en retard la plus ancienne, projets actifs non en pause.
({Project project, ProjectTask task})? oldestOverdueOf(List<Project> projects, DateTime today) {
  final d0 = DateTime(today.year, today.month, today.day);
  ({Project project, ProjectTask task})? best;
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      if (t.isMilestone || t.status == 'done' || t.status == 'skipped') continue;
      final e = t.endDate;
      if (e == null || !e.isBefore(d0)) continue;
      if (best == null || e.isBefore(best.task.endDate!)) best = (project: p, task: t);
    }
  }
  return best;
}
