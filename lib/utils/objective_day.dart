import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show isReadingDue;

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

// ── Objectif du moment (2026-10) ──────────────────────────────────────────────
// Carte en tête du segment Objectifs, sur le modèle de MAINTENANT et de « Routine
// du moment » : UN objectif à la fois et UN geste. L'objectif du moment est celui
// que la journée désigne (bloc en cours ou chrono qui tourne pour lui), sinon le
// plus en retard sur son rythme hebdo parmi ceux qui ont encore quelque chose à
// faire aujourd'hui, puis ceux dont un relevé est dû, puis les autres.

enum ObjectiveMoveKind { running, block, time, routine, reading, nextAction, none }

/// Le geste proposé par la carte : lancer le bloc en cours / à venir, lancer le
/// chrono de l'engagement de temps le plus en retard, +1 sur une routine non
/// atteinte, noter un relevé, ouvrir la prochaine action — ou rien à faire.
class ObjectiveMove {
  final ObjectiveMoveKind kind;
  final ScheduleBlock? block;
  final ObjectiveTimeToday? time;
  final Activity? routine;
  final ({Project project, ProjectTask task, TaskAction action})? next;
  const ObjectiveMove(this.kind, {this.block, this.time, this.routine, this.next});
  static const none = ObjectiveMove(ObjectiveMoveKind.none);
}

class ObjectiveMoment {
  final ObjectiveDay day;
  final ObjectiveMove move;
  final double? weekPercent; // 0..1+ — rythme hebdo (null = aucun engagement)
  final bool readingDue;
  /// Ce qui reste à faire aujourd'hui, en morceaux de phrase (« 25 min d'Écriture »,
  /// « 1 routine », « bloc à 14:00 »).
  final List<String> remaining;
  const ObjectiveMoment({
    required this.day,
    required this.move,
    required this.weekPercent,
    required this.readingDue,
    required this.remaining,
  });
  StrategicObjective get objective => day.objective;
  bool get allDone => move.kind == ObjectiveMoveKind.none && remaining.isEmpty && !readingDue;
}

int _hm(String s) {
  final p = s.split(':');
  if (p.length < 2) return 0;
  return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
}

String _minLabel(int m) => m >= 60 ? '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${(m % 60).toString().padLeft(2, '0')}'}' : '$m min';

/// Classe les objectifs du jour : le premier est l'objectif du moment, les
/// suivants sont servis par « Suivant ». `routineCount` = occurrences du jour
/// vécu, `weekPercent` = part du rythme hebdo attendu à ce jour (jauge Objectifs),
/// `runningActivityId` = chrono en cours.
List<ObjectiveMoment> rankObjectiveMoments(
  List<ObjectiveDay> days, {
  required int nowMin,
  required DateTime now,
  required int Function(Activity routine) routineCount,
  required double? Function(StrategicObjective o) weekPercent,
  String? runningActivityId,
}) {
  final out = <({ObjectiveMoment m, int rank, double pct})>[];
  for (final d in days) {
    final o = d.objective;
    final remaining = <String>[];
    final due = isReadingDue(o, now);
    final pct = weekPercent(o);

    ObjectiveTimeToday? behind;
    for (final t in d.times) {
      final left = t.expectedTodayMin - t.doneTodayMin;
      if (left <= 0) continue;
      remaining.add('${_minLabel(left)} de ${t.name}');
      if (behind == null || left > behind.expectedTodayMin - behind.doneTodayMin) behind = t;
    }
    Activity? openRoutine;
    var routinesLeft = 0;
    for (final a in d.routines) {
      final target = a.habitFreq == HabitFreq.daily ? ((a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1)) : 1;
      if (routineCount(a) >= target) continue;
      routinesLeft++;
      openRoutine ??= a;
    }
    if (routinesLeft > 0) remaining.add(routinesLeft == 1 ? '1 routine' : '$routinesLeft routines');
    ScheduleBlock? current, upcoming;
    var blocksLeft = 0;
    for (final b in d.blocks) {
      if (b.status != 'pending') continue;
      final s = _hm(b.startTime);
      if (s + b.durationMin <= nowMin) continue; // passé non fait : a sauté
      blocksLeft++;
      if (s <= nowMin) {
        current ??= b;
      } else {
        upcoming ??= b;
      }
    }
    if (blocksLeft > 0) remaining.add(blocksLeft == 1 ? 'bloc à ${(current ?? upcoming)!.startTime}' : '$blocksLeft blocs');

    final running = runningActivityId != null && d.times.any((t) => t.activityId == runningActivityId);
    final ObjectiveMove move;
    if (running) {
      move = ObjectiveMove(ObjectiveMoveKind.running, time: d.times.firstWhere((t) => t.activityId == runningActivityId));
    } else if (current != null) {
      move = ObjectiveMove(ObjectiveMoveKind.block, block: current);
    } else if (behind != null) {
      move = ObjectiveMove(ObjectiveMoveKind.time, time: behind);
    } else if (openRoutine != null) {
      move = ObjectiveMove(ObjectiveMoveKind.routine, routine: openRoutine);
    } else if (upcoming != null) {
      move = ObjectiveMove(ObjectiveMoveKind.block, block: upcoming);
    } else if (due) {
      move = const ObjectiveMove(ObjectiveMoveKind.reading);
    } else if (d.nextActions.isNotEmpty) {
      move = ObjectiveMove(ObjectiveMoveKind.nextAction, next: d.nextActions.first);
    } else {
      move = ObjectiveMove.none;
    }

    final hasWork = remaining.isNotEmpty;
    final rank = running || current != null
        ? 0
        : hasWork
            ? 1
            : due
                ? 2
                : d.nextActions.isNotEmpty
                    ? 3
                    : 4;
    out.add((
      m: ObjectiveMoment(day: d, move: move, weekPercent: pct, readingDue: due, remaining: remaining),
      rank: rank,
      pct: pct ?? 2,
    ));
  }
  out.sort((a, b) {
    final r = a.rank.compareTo(b.rank);
    if (r != 0) return r;
    final p = a.pct.compareTo(b.pct);
    if (p != 0) return p;
    return a.m.objective.title.toLowerCase().compareTo(b.m.objective.title.toLowerCase());
  });
  return [for (final e in out) e.m];
}
