import 'package:productivitwo_v1/utils/half_days.dart';
import 'package:productivitwo_v1/utils/acquired.dart' show Acquired, isAcquiredOn;
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/chain_session.dart' show PendingChain;
import 'package:productivitwo_v1/utils/elan_logic.dart' show disciplineStats;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayStart;
import 'package:productivitwo_v1/utils/objective_day.dart' show buildObjectiveDays;

/// Les faits du jour vécu (badges, enjeux), composés depuis les données brutes :
/// partagé par le mobile (`BadgeCenter.todayFacts`) et le web (Aujourd'hui).
TodayFacts composeTodayFacts({
  required String ymd,
  required DateTime now,
  required int dayStartMin,
  required List<Activity> activities,
  required List<HabitHit> hits,
  required List<Session> sessions,
  required List<MoodMark> moodMarks,
  required List<StrategicObjective> objectives,
  required List<Project> projects,
  DailySchedule? schedule,
  PendingChain? pendingChain,
  Map<String, Acquired> acquired = const {},
  Set<String> restingDomainIds = const {},
  /// Jours en veille d'une activité : ne réclament rien dans la fenêtre de Montre suisse.
  Set<String> Function(Activity a)? frozenOf,
}) {
  final dayStart = livedDayStart(now, dayStartMin);
  final active = activities.where((a) => !a.deleted).toList();
  final routines = <RoutineToday>[];
  for (final a in active) {
    if (!a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    if (a.createdAt.isAfter(now)) continue;
    if (isAcquiredOn(acquired, a.id, ymd)) continue; // acquise : plus réclamée
    final t = a.habitTarget ?? 1;
    final done = hits.where((h) => h.habitId == a.id && !h.ts.isBefore(dayStart)).length;
    routines.add(RoutineToday(a, done, t <= 0 ? 1 : t));
  }
  final elan = moodMarks.where((m) => m.isElan && m.ymd == ymd).toList();
  final blocks = schedule?.blocks ?? const <ScheduleBlock>[];
  final days = buildObjectiveDays(
    objectives: objectives,
    activities: active,
    sessions: sessions,
    blocks: blocks,
    projects: projects,
    now: now,
    dayStartMin: dayStartMin,
  );
  final disc = disciplineStats(marks: elan, schedules: schedule == null ? const [] : [schedule], hits: hits, activities: activities, dayStartMin: dayStartMin);
  return TodayFacts(
    ymd: ymd,
    now: now,
    routines: routines,
    blocks: blocks,
    elanMarks: elan,
    pendingChain: pendingChain,
    objectiveDays: days,
    objectives: objectives,
    disciplineWinsToday: disc.wins.length,
    pace: paceOn(now,
        activities: active.where((a) => !restingDomainIds.contains(a.domainId)).toList(),
        minutes: minutesByActivityDay(sessions, now),
        frozenOf: frozenOf),
    restingDomainIds: restingDomainIds,
  );
}
