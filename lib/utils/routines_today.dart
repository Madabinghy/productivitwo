import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';

/// Routines du jour (onglet Aujourd'hui web, même règle que « Le meilleur à
/// faire » du mobile, `best_to_do_card.dart`) : routines quotidiennes et
/// hebdomadaires actives ; quotidienne = cible du jour, hebdo = cible des 7
/// derniers jours. Les mensuelles sont hors liste.
class RoutineToDo {
  final Activity activity;
  final int dayDone;
  final int? dayTarget; // null = hebdo
  final int weekDone;
  final int weekTarget;
  final bool reached;
  final double score; // max(avancement du jour, avancement 7 j), 0..1

  const RoutineToDo({
    required this.activity,
    required this.dayDone,
    required this.dayTarget,
    required this.weekDone,
    required this.weekTarget,
    required this.reached,
    required this.score,
  });

  /// « 1 / 2 aujourd'hui » ou « 3 / 5 sur 7 j ».
  String get progressLabel => dayTarget != null
      ? '$dayDone / $dayTarget aujourd\'hui'
      : '$weekDone / $weekTarget sur 7 j';
}

/// Ordre : non atteintes (les plus avancées d'abord : elles se bouclent vite),
/// puis atteintes. À égalité, ordre alphabétique.
List<RoutineToDo> routinesForToday(
    List<Activity> activities, List<HabitHit> hits, DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day);
  final out = <RoutineToDo>[];
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq == HabitFreq.monthly) continue;
    final week = rollingStatFor(a, hits, now: now);
    if (week == null) continue;
    final weekRatio = (week.done / week.target).clamp(0.0, 1.0).toDouble();
    var dayDone = 0;
    int? dayTarget;
    var dayRatio = 0.0;
    if (a.habitFreq == HabitFreq.daily) {
      final t = a.habitTarget ?? 1;
      dayTarget = t <= 0 ? 1 : t;
      dayDone = hits.where((h) => h.habitId == a.id && !h.ts.isBefore(midnight)).length;
      dayRatio = (dayDone / dayTarget).clamp(0.0, 1.0).toDouble();
    }
    final reached = dayTarget != null ? dayDone >= dayTarget : week.done >= week.target;
    out.add(RoutineToDo(
      activity: a,
      dayDone: dayDone,
      dayTarget: dayTarget,
      weekDone: week.done,
      weekTarget: week.target,
      reached: reached,
      score: dayRatio > weekRatio ? dayRatio : weekRatio,
    ));
  }
  out.sort((x, y) {
    if (x.reached != y.reached) return x.reached ? 1 : -1;
    final c = y.score.compareTo(x.score);
    return c != 0 ? c : x.activity.name.toLowerCase().compareTo(y.activity.name.toLowerCase());
  });
  return out;
}
