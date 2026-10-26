import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

/// Segment « Objectifs » d'Aujourd'hui (2026-10) : ce qui, dans la journée,
/// sert un objectif en cours — ses engagements de temps au rythme du jour, ses
/// routines, ses blocs du programme, la prochaine action de ses projets.
/// Logique pure ; l'UI vit dans `widgets/objectives_day_view.dart`.

class ObjectiveTimeToday {
  final Activity? activity;
  final String activityId;
  final int weeklyMin;
  final int doneTodayMin;
  final int doneWeekMin;
  const ObjectiveTimeToday({
    required this.activity,
    required this.activityId,
    required this.weeklyMin,
    required this.doneTodayMin,
    required this.doneWeekMin,
  });

  /// Attendu aujourd'hui = cible hebdo lissée sur 7 jours (au moins 1 min).
  int get expectedTodayMin => (weeklyMin / 7).round().clamp(1, 1 << 20);
  String get name => activity?.name ?? activityId;
}

class ObjectiveDay {
  final StrategicObjective objective;
  final List<ObjectiveTimeToday> times;
  final List<Activity> routines;
  final List<ScheduleBlock> blocks;
  final List<({Project project, ProjectTask task, TaskAction action})> nextActions;
  const ObjectiveDay({
    required this.objective,
    required this.times,
    required this.routines,
    required this.blocks,
    required this.nextActions,
  });

  bool get isEmpty => times.isEmpty && routines.isEmpty && blocks.isEmpty && nextActions.isEmpty;
}

/// Un bloc sert l'objectif s'il vise une de ses activités engagées (temps ou
/// routine), un de ses projets, ou l'activité liée d'un de ses projets.
bool blockServesObjective(ScheduleBlock b, StrategicObjective o, Map<String, Project> projectsById) {
  if (b.status == 'deleted') return false;
  final acts = {
    ...o.timeCommitments.map((c) => c.activityId),
    ...o.routineCommitments.map((c) => c.activityId),
  };
  if (b.activityId != null && acts.contains(b.activityId)) return true;
  if (b.projectId != null && o.projectIds.contains(b.projectId)) return true;
  for (final pid in o.projectIds) {
    final linked = projectsById[pid]?.linkedActivityId;
    if (linked != null && b.activityId == linked) return true;
  }
  return false;
}

/// Minutes de chrono d'une activité sur un jour vécu (sessions fermées et
/// session ouverte jusqu'à `now`).
int minutesOn(String activityId, List<Session> sessions, DateTime from, DateTime to) {
  var total = 0;
  for (final s in sessions) {
    if (s.deleted || s.activityId != activityId) continue;
    final end = s.endAt ?? to;
    final a = s.startAt.isBefore(from) ? from : s.startAt;
    final z = end.isAfter(to) ? to : end;
    final m = z.difference(a).inMinutes;
    if (m > 0) total += m;
  }
  return total;
}

List<ObjectiveDay> buildObjectiveDays({
  required List<StrategicObjective> objectives,
  required List<Activity> activities,
  required List<Session> sessions,
  required List<ScheduleBlock> blocks,
  required List<Project> projects,
  required DateTime now,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final actById = {for (final a in activities) a.id: a};
  final projById = {for (final p in projects) p.id: p};
  final dayStart = livedDayStart(now, dayStartMin);
  final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  final active = objectives.where((o) => o.status == 'active').toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return [
    for (final o in active)
      ObjectiveDay(
        objective: o,
        times: [
          for (final c in o.timeCommitments)
            ObjectiveTimeToday(
              activity: actById[c.activityId],
              activityId: c.activityId,
              weeklyMin: c.weeklyMin,
              doneTodayMin: minutesOn(c.activityId, sessions, dayStart, now),
              doneWeekMin: minutesOn(c.activityId, sessions, monday, now),
            ),
        ],
        routines: [
          for (final c in o.routineCommitments)
            if (actById[c.activityId] case final a? when !a.deleted) a,
        ],
        blocks: blocks.where((b) => blockServesObjective(b, o, projById)).toList()..sort((a, b) => a.startTime.compareTo(b.startTime)),
        nextActions: [
          for (final pid in o.projectIds)
            if (projById[pid] case final p? when p.status != 'archived' && p.status != 'done')
              if (nextAction(p) case final n?) (project: p, task: n.task, action: n.action),
        ],
      ),
  ];
}
