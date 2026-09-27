import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';

/// Logique pure de la vue « Cette semaine » (refonte web § 3) — testable sans
/// widget. Une semaine = lundi → dimanche. Les minutes sont comptées depuis
/// minuit ; les blocs `deleted` doivent avoir été filtrés en amont.

/// Lundi 00:00 de la semaine contenant [d].
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

List<DateTime> weekDates(DateTime monday) =>
    [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Une tâche de la semaine : la paire tâche/projet + ses attributs dérivés.
class WeekTask {
  final ProjectTask task;
  final Project project;
  final bool overdue; // échéance dépassée, non faite
  final int plannedBlocks; // blocs de la semaine liés à la tâche
  const WeekTask({
    required this.task,
    required this.project,
    required this.overdue,
    required this.plannedBlocks,
  });

  bool get done => task.status == 'done';
  bool get planned => plannedBlocks > 0;
  /// À caser = ouverte et sans bloc cette semaine.
  bool get toPlace => !done && !planned;
}

/// Tâches qui chevauchent la semaine [monday]..[monday+6], ou en retard
/// (échéance < aujourd'hui, non faite), des projets actifs non en pause.
/// [scheduled] = blocs (non supprimés) de tous les jours de la semaine.
List<WeekTask> weekTasks({
  required List<Project> projects,
  required DateTime monday,
  required List<ScheduleBlock> scheduled,
  required DateTime today,
}) {
  final sunday = monday.add(const Duration(days: 6));
  final blocksByTask = <String, int>{};
  for (final b in scheduled) {
    if (b.taskId != null) {
      blocksByTask[b.taskId!] = (blocksByTask[b.taskId!] ?? 0) + 1;
    }
  }
  final out = <WeekTask>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      if (t.status == 'skipped') continue;
      final end = dateOnly(t.endDate ?? t.startDate);
      final start = dateOnly(t.startDate);
      final overdue = t.status != 'done' && end.isBefore(dateOnly(today));
      final overlaps = !start.isAfter(sunday) && !end.isBefore(monday);
      if (!overlaps && !overdue) continue;
      out.add(WeekTask(
        task: t,
        project: p,
        overdue: overdue,
        plannedBlocks: blocksByTask[t.id] ?? 0,
      ));
    }
  }
  return out;
}

/// « À caser » : ouvertes sans bloc, retards d'abord, puis par échéance.
List<WeekTask> tasksToPlace(List<WeekTask> tasks) {
  final list = tasks.where((t) => t.toPlace).toList()
    ..sort((a, b) {
      if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
      final ea = a.task.endDate ?? a.task.startDate;
      final eb = b.task.endDate ?? b.task.startDate;
      return ea.compareTo(eb);
    });
  return list;
}

/// Minutes planifiées d'un jour (blocs non supprimés, faits ou non).
int plannedMin(List<ScheduleBlock> blocks) =>
    blocks.fold(0, (s, b) => s + b.durationMin);

/// Journée bloquée : un bloc d'au moins 6 h la couvre (déplacement, formation…).
bool isBlockedDay(List<ScheduleBlock> blocks) =>
    blocks.any((b) => b.durationMin >= 6 * 60);

/// Premier créneau libre d'au moins [durationMin] à partir de [fromMin]
/// (défaut 8 h) et finissant avant [untilMin] (défaut 22 h), hors blocs
/// existants. Null si aucun.
int? firstFreeSlot(
  List<ScheduleBlock> blocks,
  int durationMin, {
  int fromMin = 8 * 60,
  int untilMin = 22 * 60,
}) {
  final busy = blocks.map((b) => (start: blockStartMin(b), end: blockEndMin(b))).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  var cursor = fromMin;
  for (final s in busy) {
    if (s.end <= cursor) continue;
    if (s.start - cursor >= durationMin) break;
    cursor = s.end > cursor ? s.end : cursor;
  }
  return cursor + durationMin <= untilMin ? cursor : null;
}

String minToClock(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

/// Placement automatique : chaque tâche à caser, dans l'ordre de
/// [tasksToPlace], sur le premier jour ≥ [today] de la semaine dont la charge
/// (existant + déjà placé) + estimation tient dans la capacité ET qui offre un
/// créneau libre. Retourne les blocs à créer, par jour (YYYY-MM-DD).
/// Une tâche qui ne tient nulle part est ignorée (la liste `left` la garde).
({Map<String, List<ScheduleBlock>> blocks, List<WeekTask> left}) autoPlace({
  required List<WeekTask> toPlace,
  required List<DateTime> days,
  required Map<String, List<ScheduleBlock>> scheduledByDay,
  required Map<String, int> capacity,
  required DateTime today,
}) {
  final created = <String, List<ScheduleBlock>>{};
  final left = <WeekTask>[];
  final t0 = dateOnly(today);
  for (final wt in toPlace) {
    final dur = wt.task.plannedMin;
    var placed = false;
    for (final day in days) {
      if (day.isBefore(t0)) continue;
      final key = ymdOf(day);
      final existing = <ScheduleBlock>[
        ...?scheduledByDay[key],
        ...?created[key],
      ];
      final cap = capacityMinFor(capacity, day);
      if (cap == 0 || isBlockedDay(existing)) continue;
      if (plannedMin(existing) + dur > cap) continue;
      final start = firstFreeSlot(existing, dur);
      if (start == null) continue;
      created.putIfAbsent(key, () => []).add(taskBlock(wt, start));
      placed = true;
      break;
    }
    if (!placed) left.add(wt);
  }
  return (blocks: created, left: left);
}

/// Bloc de programme pour une tâche de projet à [startMin].
ScheduleBlock taskBlock(WeekTask wt, int startMin) => ScheduleBlock(
      startTime: minToClock(startMin),
      durationMin: wt.task.plannedMin,
      title: wt.task.title,
      category: 'project',
      projectId: wt.project.id,
      taskId: wt.task.id,
    );
