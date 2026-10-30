import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, isOverdueAction, isUpcomingTask, workDate;
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/project_health.dart' show ganttOrder, nextAction;
import 'package:productivitwo_v1/utils/project_moment.dart' show projectPlan;

/// Offensive (maquette validée 2026-10-30) : l'équivalent de la Guérilla quand
/// on est EN FORME. On choisit un FRONT (un projet, ou « tout mélanger » = la
/// prochaine action de chaque projet, la plus en retard d'abord) et la durée
/// d'un coup (10 ou 15 min) ; l'app enchaîne les actions, une étape en avant.
/// Un coup est GAGNÉ quand son minuteur arrive au bout, même sans finir
/// l'action. Point d'étape tous les [kOffensivePauseEvery] coups. Une
/// offensive est une [ChainRun] `kind:"offensive"` (doneCount = coups gagnés) ;
/// elle compte pour le badge Offensive dès [kOffensiveCountedMin] coups. Le
/// deep work 90 min reste à part (un seul gros bloc). Logique pure.
const kOffensiveKind = 'offensive';
const kOffensiveDurations = [10, 15];
const kOffensivePauseEvery = 3;
const kOffensiveCountedMin = 3;
const kOffensiveTiers = [1, 5, 15];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class OffensiveTarget {
  final Project project;
  final ProjectTask task;
  final TaskAction action;
  const OffensiveTarget(this.project, this.task, this.action);

  /// Activité du chrono : celle de l'action, sinon celle du projet.
  String? get chronoActivityId => action.linkedActivityId ?? project.linkedActivityId;
}

class OffensiveFront {
  final Project project;
  final int ready;
  final int overdue;
  final DateTime? sessionDate;
  const OffensiveFront({required this.project, required this.ready, required this.overdue, this.sessionDate});
}

bool _alive(Project p, List<Project> all) =>
    !p.paused && p.status != 'done' && p.status != 'archived' && !isFolderProject(p, all);

/// Actions ouvertes d'un projet qu'on peut attaquer aujourd'hui (hors tâches à
/// venir), par date de travail (visée, sinon échéance) puis ordre Gantt.
List<OffensiveTarget> openTargets(Project p, DateTime now) {
  final out = <(OffensiveTarget, DateTime?, int)>[];
  var rank = 0;
  for (final t in ganttOrder(p)) {
    if (t.status == 'done' || t.status == 'skipped' || isUpcomingTask(t, now)) continue;
    for (final a in t.actions) {
      if (a.done) continue;
      final w = workDate(a, t);
      out.add((OffensiveTarget(p, t, a), w == null ? null : _day(w), rank++));
    }
  }
  out.sort((x, y) {
    if (x.$2 != null && y.$2 != null && x.$2 != y.$2) return x.$2!.compareTo(y.$2!);
    if ((x.$2 == null) != (y.$2 == null)) return x.$2 == null ? 1 : -1;
    return x.$3.compareTo(y.$3);
  });
  return [for (final e in out) e.$1];
}

/// Les fronts possibles : projets vivants qui ont des actions prêtes, les plus
/// en retard d'abord, puis la séance la plus proche, puis le plus d'actions.
List<OffensiveFront> offensiveFronts(List<Project> projects, DateTime now) {
  final out = <OffensiveFront>[];
  for (final p in projects) {
    if (!_alive(p, projects)) continue;
    final targets = openTargets(p, now);
    if (targets.isEmpty) continue;
    final overdue = targets.where((x) => isOverdueAction(x.action, x.task, now)).length;
    final next = nextInterventionOf(p, now);
    out.add(OffensiveFront(project: p, ready: targets.length, overdue: overdue, sessionDate: next?.date));
  }
  out.sort((a, b) {
    if (a.overdue != b.overdue) return b.overdue.compareTo(a.overdue);
    final sa = a.sessionDate, sb = b.sessionDate;
    if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    if ((sa == null) != (sb == null)) return sa == null ? 1 : -1;
    return b.ready.compareTo(a.ready);
  });
  return out;
}

/// « 2 en retard · séance le 9 nov · 4 actions prêtes ».
String frontLine(OffensiveFront f) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return [
    if (f.overdue > 0) '${f.overdue} en retard',
    if (f.sessionDate case final d?) 'séance le ${d.day} ${months[d.month - 1]}',
    '${f.ready} action${f.ready > 1 ? 's' : ''} prête${f.ready > 1 ? 's' : ''}',
  ].join(' · ');
}

/// La file : toutes les actions prêtes du projet choisi ; sans projet (« tout
/// mélanger »), la prochaine action de chaque projet vivant, en retard d'abord.
List<OffensiveTarget> buildOffensiveQueue(List<Project> projects, DateTime now, {String? projectId}) {
  if (projectId != null) {
    final p = projects.where((x) => x.id == projectId).firstOrNull;
    return p == null ? const [] : openTargets(p, now);
  }
  final out = <(OffensiveTarget, bool, DateTime?)>[];
  for (final p in projects) {
    if (!_alive(p, projects)) continue;
    final n = nextAction(p);
    if (n == null || isUpcomingTask(n.task, now)) continue;
    final w = workDate(n.action, n.task);
    out.add((OffensiveTarget(p, n.task, n.action), isOverdueAction(n.action, n.task, now), w == null ? null : _day(w)));
  }
  out.sort((x, y) {
    if (x.$2 != y.$2) return x.$2 ? -1 : 1;
    if (x.$3 != null && y.$3 != null && x.$3 != y.$3) return x.$3!.compareTo(y.$3!);
    if ((x.$3 == null) != (y.$3 == null)) return x.$3 == null ? 1 : -1;
    return 0;
  });
  return [for (final e in out) e.$1];
}

/// Point d'étape dû après [won] coups gagnés.
bool offensivePauseDue(int won) => won > 0 && won % kOffensivePauseEvery == 0;

bool isOffensiveRun(ChainRun r) => r.kind == kOffensiveKind;

bool offensiveCounts(ChainRun r) => isOffensiveRun(r) && r.doneCount >= kOffensiveCountedMin;

/// Avancement d'un projet : tâches faites / total, et retard sur le plan.
({int done, int total, int behind}) planSnapshot(Project p, DateTime now) {
  final plan = projectPlan(p, now);
  final behind = plan.expected - plan.done;
  return (done: plan.done, total: plan.total, behind: behind < 0 ? 0 : behind);
}

/// « 1 h 32 » / « 47 min ».
String fmtOffensiveMin(int min) => min < 60 ? '$min min' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
