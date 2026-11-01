import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;
import 'package:productivitwo_v1/utils/meal_plan.dart';

/// Repas — lot 3 : la feuille Repas lit ce qui existe (routine Repas
/// équilibré, chronos Manger et Cuisiner, menu de la semaine).

bool isBalancedMealRoutine(Activity a) => a.isHabit && !a.deleted && RegExp(r'repas|équilibr|equilibr', caseSensitive: false).hasMatch(a.name);
bool isCookActivity(Activity a) => a.type == 'time' && !a.deleted && RegExp(r'cuisin', caseSensitive: false).hasMatch(a.name);
bool isEatActivity(Activity a) => a.type == 'time' && !a.deleted && RegExp(r'^(manger|repas|déjeuner|dîner|diner)', caseSensitive: false).hasMatch(a.name.trim());

/// Midi ou soir d'un instant : avant 16 h = midi.
String momentOfMeal(DateTime t) => t.hour < 16 ? 'midi' : 'soir';

/// Repas « en cours » : le midi jusqu'à 15 h, puis le soir.
String currentMealMoment(DateTime now) => now.hour < 15 ? 'midi' : 'soir';

enum MealCell { ok, other, none, planned, empty }

class MealWeekView {
  final Map<String, MealCell> cells; // clé repas → état
  final int balanced; // repas équilibrés passés ou en cours
  final int counted; // repas passés ou en cours
  final int skippedLunches; // midis passés sans rien
  final int cookMin; // chrono Cuisiner de la semaine
  final int? lunchClock; // heure moyenne du déjeuner (minutes depuis minuit)
  final int? dinnerClock;
  const MealWeekView(this.cells, this.balanced, this.counted, this.skippedLunches, this.cookMin, this.lunchClock, this.dinnerClock);
}

int? _avgClock(List<DateTime> ts) => ts.isEmpty ? null : (ts.fold(0, (s, t) => s + t.hour * 60 + t.minute) / ts.length).round();

MealWeekView mealWeekView({
  required List<String> days,
  required MealWeek week,
  required List<Activity> activities,
  required List<HabitHit> hits,
  required List<Session> sessions,
  required DateTime now,
  required int dayStartMin,
}) {
  final routineIds = {for (final a in activities) if (isBalancedMealRoutine(a)) a.id};
  final cookIds = {for (final a in activities) if (isCookActivity(a)) a.id};
  final eatIds = {for (final a in activities) if (isEatActivity(a)) a.id};
  final set = days.toSet();
  final okKeys = <String>{};
  for (final h in hits) {
    if (!routineIds.contains(h.habitId)) continue;
    final y = ymdOf(livedDate(h.ts, dayStartMin));
    if (set.contains(y)) okKeys.add(mealKey(y, momentOfMeal(h.ts)));
  }
  final ateKeys = <String>{};
  final lunches = <DateTime>[], dinners = <DateTime>[];
  var cook = 0;
  for (final s in sessions) {
    if (s.deleted) continue;
    final y = ymdOf(livedDate(s.startAt, dayStartMin));
    if (!set.contains(y)) continue;
    if (cookIds.contains(s.activityId)) cook += (s.endAt ?? now).difference(s.startAt).inMinutes;
    if (eatIds.contains(s.activityId)) {
      final m = momentOfMeal(s.startAt);
      ateKeys.add(mealKey(y, m));
      (m == 'midi' ? lunches : dinners).add(s.startAt);
    }
  }
  final today = ymdOf(livedDate(now, dayStartMin));
  final curMoment = currentMealMoment(now);
  final cells = <String, MealCell>{};
  var balanced = 0, counted = 0, skipped = 0;
  for (final y in days) {
    for (final m in kMealMoments) {
      final k = mealKey(y, m);
      final slot = week.slots[k];
      final past = y.compareTo(today) < 0 || (y == today && (m == 'midi' && curMoment == 'soir'));
      final current = y == today && m == curMoment;
      MealCell c;
      if (okKeys.contains(k) || slot?.ate == 'ok') {
        c = MealCell.ok;
      } else if (slot?.ate == 'other' || (past && (ateKeys.contains(k) || slot?.out == true))) {
        c = MealCell.other;
      } else if (past) {
        c = MealCell.none;
      } else if (slot != null) {
        c = MealCell.planned;
      } else {
        c = MealCell.empty;
      }
      cells[k] = c;
      if (past || (current && c != MealCell.planned && c != MealCell.empty)) {
        counted++;
        if (c == MealCell.ok) balanced++;
        if (m == 'midi' && c == MealCell.none) skipped++;
      }
    }
  }
  return MealWeekView(cells, balanced, counted, skipped, cook, _avgClock(lunches), _avgClock(dinners));
}
