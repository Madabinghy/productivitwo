import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart'
    show effectiveDueDate, focusDateOf, isFolderProject, isUpcomingTask, workDate;
import 'package:productivitwo_v1/utils/project_health.dart' show ganttOrder;

/// File d'un bloc d'ACTIVITÉ (maquette « Blocs d'activité », 2026-10) : un
/// bloc = une activité + une durée ; au lancement, la page focus propose UNE
/// action par projet lié à l'activité (la prochaine, même règle que l'onglet
/// Actions), les en retard d'abord, puis les actions propres de l'activité.
/// Le bloc ne retient que le temps ; les actions se cochent dans leur projet.
class QueueItem {
  final TaskAction action;
  final Project? project; // null = action propre de l'activité
  final ProjectTask? task;
  /// Échéance effective (vraie date butoir) ; `overdue` la regarde seule.
  final DateTime? due;
  final bool overdue;
  /// Jour visé (intention) ; `focusedToday` = visée pour la journée du bloc.
  final DateTime? focus;
  final bool focusedToday;
  const QueueItem({
    required this.action,
    this.project,
    this.task,
    this.due,
    this.overdue = false,
    this.focus,
    this.focusedToday = false,
  });

  /// Date de travail : jour visé, sinon échéance.
  DateTime? get work => focus ?? due;

  String get id => action.id;
  String? get context => project == null ? null : '${project!.title}${task != null ? ' › ${task!.title}' : ''}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Un projet est lié à l'activité par son `linkedActivityId`, ou par une
/// action ouverte dont le `linkedActivityId` est l'activité.
bool projectServesActivity(Project p, String activityId) {
  if (p.linkedActivityId == activityId) return true;
  for (final t in p.tasks) {
    if (t.status == 'done' || t.status == 'skipped') continue;
    for (final a in t.actions) {
      if (!a.done && a.linkedActivityId == activityId) return true;
    }
  }
  return false;
}

QueueItem _item(TaskAction a, Project? p, ProjectTask? t, DateTime today) {
  final due = effectiveDueDate(a, t);
  final focus = focusDateOf(a);
  return QueueItem(
    action: a,
    project: p,
    task: t,
    due: due,
    overdue: due != null && due.isBefore(today),
    focus: focus,
    focusedToday: focus != null && !focus.isAfter(today),
  );
}

/// Prochaine action d'un projet pour l'activité : parmi les actions ouvertes
/// des tâches ouvertes non à venir qui servent l'activité (toutes si le projet
/// est lié), la date de travail la plus proche (jour visé, sinon échéance),
/// sinon l'ordre Gantt.
QueueItem? _nextFor(Project p, String activityId, DateTime today) {
  final wholeProject = p.linkedActivityId == activityId;
  QueueItem? best;
  for (final t in ganttOrder(p)) {
    if (t.status == 'done' || t.status == 'skipped' || isUpcomingTask(t, today)) continue;
    for (final a in t.actions) {
      if (a.done || !(wholeProject || a.linkedActivityId == activityId)) continue;
      final w = workDate(a, t);
      final better = best == null || (w != null && (best.work == null || w.isBefore(best.work!)));
      if (better) best = _item(a, p, t, today);
    }
  }
  return best;
}

/// La file du bloc : une action par projet vivant (actif, pas en pause, pas un
/// dossier) lié à l'activité, puis les actions propres ouvertes de l'activité.
/// Tri : VISÉES pour aujourd'hui (ou avant) d'abord — l'intention du jour
/// commande —, puis en retard (échéance la plus ancienne), puis datées par date
/// de travail, puis sans date dans l'ordre d'arrivée. Vide = rien à proposer
/// (le ▶ garde son comportement : chrono seul).
List<QueueItem> blockQueue({
  required Activity activity,
  required List<Project> projects,
  required DateTime today,
}) {
  final d = _day(today);
  final items = <QueueItem>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused || isFolderProject(p, projects)) continue;
    if (!projectServesActivity(p, activity.id)) continue;
    final n = _nextFor(p, activity.id, d);
    if (n != null) items.add(n);
  }
  for (final a in activity.ownActions) {
    if (a.done) continue;
    items.add(_item(a, null, null, d));
  }
  int rank(QueueItem q) => q.focusedToday ? 0 : (q.overdue ? 1 : (q.work != null ? 2 : 3));
  final indexed = items.indexed.toList()
    ..sort((x, y) {
      final r = rank(x.$2).compareTo(rank(y.$2));
      if (r != 0) return r;
      if (x.$2.work != null && y.$2.work != null) {
        final c = x.$2.work!.compareTo(y.$2.work!);
        if (c != 0) return c;
      }
      return x.$1.compareTo(y.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Minutes estimées de la file (45 min par défaut, comme les filtres).
int queueEstimateMin(Iterable<QueueItem> q) => q.fold(0, (s, e) => s + (e.action.estimatedMin ?? 45));

/// Minutes restantes du bloc à [nowMin] (minute du jour) ; 0 si fini.
int blockRemainingMin(ScheduleBlock b, int nowMin) {
  final p = b.startTime.split(':');
  final s = (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  final end = s + b.durationMin;
  if (nowMin < s) return b.durationMin;
  return end > nowMin ? end - nowMin : 0;
}

/// Bilan d'un bloc d'activité (écran de fin, lot 2) : temps tenu = sessions
/// de l'activité du bloc qui recoupent son créneau (tronquées), actions de la
/// file faites pendant le créneau, étapes cochées pendant le créneau, et ce
/// qui reste dans la file.
class BlockOutcome {
  final int heldMin;
  final List<QueueItem> doneItems;
  final Map<String, int> minutesByAction;
  final int stepsDone;
  final List<QueueItem> remaining;
  const BlockOutcome({
    required this.heldMin,
    required this.doneItems,
    required this.minutesByAction,
    required this.stepsDone,
    required this.remaining,
  });
}

({DateTime start, DateTime end}) blockWindow(ScheduleBlock b, DateTime date) {
  final p = b.startTime.split(':');
  final s = DateTime(date.year, date.month, date.day, int.tryParse(p[0]) ?? 0, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  return (start: s, end: s.add(Duration(minutes: b.durationMin)));
}

BlockOutcome blockOutcome({
  required ScheduleBlock block,
  required DateTime date,
  required String activityId,
  required List<QueueItem> queue,
  required List<Session> sessions,
  required DateTime now,
}) {
  final w = blockWindow(block, date);
  final end = now.isBefore(w.end) ? now : w.end;
  var held = 0;
  final byAction = <String, int>{};
  for (final s in sessions) {
    if (s.deleted || s.activityId != activityId) continue;
    final a = s.startAt.isAfter(w.start) ? s.startAt : w.start;
    final b = (s.endAt ?? now).isBefore(end) ? (s.endAt ?? now) : end;
    final m = b.difference(a).inMinutes;
    if (m <= 0) continue;
    held += m;
    if (s.actionId != null) byAction[s.actionId!] = (byAction[s.actionId!] ?? 0) + m;
  }
  bool inWindow(DateTime? d) => d != null && !d.isBefore(w.start) && !d.isAfter(end.add(const Duration(minutes: 1)));
  final done = <QueueItem>[], rest = <QueueItem>[];
  var steps = 0;
  for (final q in queue) {
    if (q.action.done) {
      if (inWindow(q.action.doneAt)) done.add(q);
    } else {
      rest.add(q);
    }
    steps += q.action.checklist.where((c) => c.done && inWindow(c.doneAt)).length;
  }
  return BlockOutcome(heldMin: held, doneItems: done, minutesByAction: byAction, stepsDone: steps, remaining: rest);
}

/// « Caser un bloc demain » : un NOUVEAU bloc, même activité, même heure,
/// même durée, sans action visée — la file se recalculera au lancement.
ScheduleBlock carriedActivityBlock(ScheduleBlock b, String fromYmd) => ScheduleBlock(
      startTime: b.startTime,
      durationMin: b.durationMin,
      title: b.title,
      category: b.category,
      activityId: b.activityId,
      domainId: b.domainId,
      carriedFromDate: fromYmd,
    );
