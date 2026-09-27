import 'package:productivitwo_v1/models.dart';

/// Logique pure de l'onglet Projets (refonte web § 4) — testable sans widget.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Tâches dans l'ordre du Gantt : par date de début, ordre de saisie à égalité.
List<ProjectTask> ganttOrder(Project p) {
  final list = List.of(p.tasks);
  final index = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final c = a.startDate.compareTo(b.startDate);
    return c != 0 ? c : index[a.id]!.compareTo(index[b.id]!);
  });
  return list;
}

/// Avancement : tâches faites / tâches comptées (hors `skipped`).
({int done, int total}) taskProgress(Project p) {
  var done = 0, total = 0;
  for (final t in p.tasks) {
    if (t.status == 'skipped') continue;
    total++;
    if (t.status == 'done') done++;
  }
  return (done: done, total: total);
}

/// Phase contenant [today], sinon null (« sans phase »).
ProjectPhase? currentPhase(Project p, DateTime today) {
  final d = _day(today);
  for (final ph in p.phases) {
    if (!_day(ph.startDate).isAfter(d) && !_day(ph.endDate).isBefore(d)) return ph;
  }
  return null;
}

/// Tâches ouvertes dont l'échéance est passée.
List<ProjectTask> overdueTasks(Project p, DateTime today) {
  final d = _day(today);
  return [
    for (final t in p.tasks)
      if (t.status != 'done' &&
          t.status != 'skipped' &&
          t.endDate != null &&
          _day(t.endDate!).isBefore(d))
        t,
  ];
}

/// Prochaine action : première `TaskAction` non faite de la première tâche
/// non faite (ordre Gantt). Null si aucune action ouverte.
({ProjectTask task, TaskAction action})? nextAction(Project p) {
  for (final t in ganttOrder(p)) {
    if (t.status == 'done' || t.status == 'skipped') continue;
    for (final a in t.actions) {
      if (!a.done) return (task: t, action: a);
    }
  }
  return null;
}

bool _sessionOfProject(Session s, Project p, Set<String> taskIds) =>
    (s.taskId != null && taskIds.contains(s.taskId)) ||
    (p.linkedActivityId != null && s.activityId == p.linkedActivityId);

/// Sessions liées au projet (par tâche, ou par activité-temps liée) qui
/// touchent les 7 derniers jours.
List<Session> sessionsLast7Days(Project p, List<Session> sessions, DateTime now) {
  final since = now.subtract(const Duration(days: 7));
  final ids = {for (final t in p.tasks) t.id};
  return [
    for (final s in sessions)
      if (_sessionOfProject(s, p, ids) && !(s.endAt ?? now).isBefore(since)) s,
  ];
}

/// Minutes des sessions terminées ou en cours des 7 derniers jours liées au
/// projet, tronquées à la fenêtre.
int minutesLast7Days(Project p, List<Session> sessions, DateTime now) {
  final since = now.subtract(const Duration(days: 7));
  var total = 0;
  for (final s in sessionsLast7Days(p, sessions, now)) {
    final end = s.endAt ?? now;
    final start = s.startAt.isBefore(since) ? since : s.startAt;
    total += end.difference(start).inMinutes;
  }
  return total;
}

/// Prochain jalon non fait (date ≥ aujourd'hui), le plus proche d'abord.
ProjectTask? nextMilestone(Project p, DateTime today) {
  final d = _day(today);
  ProjectTask? best;
  for (final t in p.tasks) {
    if (!t.isMilestone || t.status == 'done' || t.status == 'skipped') continue;
    final when = _day(t.endDate ?? t.startDate);
    if (when.isBefore(d)) continue;
    if (best == null || when.isBefore(_day(best.endDate ?? best.startDate))) best = t;
  }
  return best;
}

/// Dernier signe de vie : fin de session liée ou action cochée. Null si aucun.
DateTime? lastActivityAt(Project p, List<Session> sessions) {
  DateTime? last;
  void keep(DateTime? d) {
    if (d != null && (last == null || d.isAfter(last!))) last = d;
  }
  final ids = {for (final t in p.tasks) t.id};
  for (final s in sessions) {
    if (_sessionOfProject(s, p, ids)) keep(s.endAt ?? s.startAt);
  }
  for (final t in p.tasks) {
    for (final a in t.actions) {
      if (a.done) keep(a.doneAt);
    }
  }
  return last;
}

enum HealthKind { stalled, atRisk, noDeadline, onTrack }

class ProjectHealth {
  final HealthKind kind;
  final int count; // jours d'inactivité (stalled) ou retards (atRisk)
  const ProjectHealth(this.kind, [this.count = 0]);

  String get label => switch (kind) {
        HealthKind.stalled => 'Au point mort · $count j',
        HealthKind.atRisk => count > 0
            ? 'À risque · $count retard${count > 1 ? 's' : ''}'
            : 'À risque · échéance proche',
        HealthKind.noDeadline => 'Sans échéance',
        HealthKind.onTrack => 'Dans les temps',
      };
}

/// État calculé (§ 4.4), dans l'ordre de priorité :
/// - au point mort : aucune session ni action faite depuis ≥ 7 jours
///   (un projet sans aucun signe de vie compte depuis sa création) ;
/// - à risque : ≥ 1 tâche en retard, ou échéance ≤ 7 j avec < 70 % fait ;
/// - sans échéance ; - dans les temps.
ProjectHealth projectHealth(Project p, List<Session> sessions, DateTime now) {
  final last = lastActivityAt(p, sessions) ?? p.createdAt;
  final idle = _day(now).difference(_day(last)).inDays;
  if (idle >= 7) return ProjectHealth(HealthKind.stalled, idle);

  final overdue = overdueTasks(p, now).length;
  if (overdue > 0) return ProjectHealth(HealthKind.atRisk, overdue);
  if (p.endDate != null) {
    final left = _day(p.endDate!).difference(_day(now)).inDays;
    final prog = taskProgress(p);
    final pct = prog.total == 0 ? 0.0 : prog.done / prog.total;
    if (left <= 7 && pct < .7) return const ProjectHealth(HealthKind.atRisk);
  }
  if (p.endDate == null) return const ProjectHealth(HealthKind.noDeadline);
  return const ProjectHealth(HealthKind.onTrack);
}

/// « J-n » (n ≥ 0), « J+n » si dépassée, « — » sans échéance.
String daysLeftLabel(DateTime? endDate, DateTime today) {
  if (endDate == null) return '—';
  final n = _day(endDate).difference(_day(today)).inDays;
  return n >= 0 ? 'J-$n' : 'J+${-n}';
}

/// Recherche : titre du projet OU titre d'une tâche, insensible à la casse et
/// aux accents. Requête vide = tout passe.
bool projectMatches(Project p, String query) {
  final q = _fold(query);
  if (q.isEmpty) return true;
  if (_fold(p.title).contains(q)) return true;
  return p.tasks.any((t) => _fold(t.title).contains(q));
}

String _fold(String s) {
  const from = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ';
  const to = 'aaaeeeeiioouuucAAAEEEEIIOOUUUC';
  final sb = StringBuffer();
  for (final r in s.trim().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb.toString().toLowerCase();
}
