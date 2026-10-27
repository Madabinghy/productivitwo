import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show effectiveDueDate, isFolderProject, rootProjectOf;
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

/// Onglet Projets « une carte, une fiche » (2026-10) : logique pure du
/// *projet du moment* et des lignes. Même lecture que les objectifs : fait /
/// attendu à ce jour, repère « attendu aujourd'hui », trois couleurs d'état.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Avancement du plan : tâches faites / total, et tâches ATTENDUES à ce jour
/// (échéance — sinon date de début — passée ou aujourd'hui). « Au fil de
/// l'eau » (`gtd-flow`) et les tâches sautées ne comptent pas.
class ProjectPlan {
  final int done;
  final int total;
  final int expected;
  const ProjectPlan({required this.done, required this.total, required this.expected});

  /// Part du plan tenue (1 = au rythme ; au-delà, de l'avance).
  double get ratio => expected <= 0 ? 1 : done / expected;
  int get pctInt => (ratio * 100).round();
  int get delta => done - expected;
}

ProjectPlan projectPlan(Project p, DateTime today) {
  final d = _day(today);
  var done = 0, total = 0, expected = 0;
  for (final t in p.tasks) {
    if (t.id == 'gtd-flow' || t.status == 'skipped') continue;
    total++;
    if (t.status == 'done') done++;
    final due = _day(t.endDate ?? t.startDate);
    if (!due.isAfter(d)) expected++;
  }
  return ProjectPlan(done: done, total: total, expected: expected);
}

/// Une action ouverte qui compte pour « cette semaine » : échéance effective
/// à 7 jours ou dépassée, ou action de la prépa de la prochaine séance.
typedef ProjectAction = ({ProjectTask task, TaskAction action, DateTime? due});

class ProjectMoment {
  final Project project;
  final ProjectPlan plan;
  final ProjectHealth health;
  final Intervention? session;
  final int? daysToSession;
  final List<ProjectAction> weekActions;
  final ({ProjectTask task, TaskAction action})? next;
  /// Toutes les tâches restantes démarrent plus tard : projet « à venir ».
  final bool upcoming;
  final String? rootTitle;
  const ProjectMoment({
    required this.project,
    required this.plan,
    required this.health,
    required this.session,
    required this.daysToSession,
    required this.weekActions,
    required this.next,
    required this.upcoming,
    required this.rootTitle,
  });

  bool get sessionSoon => daysToSession != null && daysToSession! >= 0 && daysToSession! <= 7;
  bool get behind => plan.delta < 0;

  /// Pourcentage qui colore la ligne et l'anneau (paliers objectifs).
  int get pctInt => upcoming ? 100 : plan.pctInt;

  String get stateLabel {
    if (upcoming) return 'à venir';
    if (health.kind == HealthKind.stalled) return 'au point mort';
    final p = plan.pctInt;
    return p >= 85 ? 'au rythme' : (p >= 60 ? 'à surveiller' : 'en retard');
  }

  /// Écart au plan en tâches : « +1 tâche », « −2 tâches », « à jour ».
  String get deltaLabel {
    final d = plan.delta;
    if (d == 0) return 'à jour';
    final n = d.abs();
    return '${d > 0 ? '+' : '−'}$n tâche${n > 1 ? 's' : ''}';
  }
}

List<ProjectAction> _weekActions(Project p, Intervention? session, DateTime today, {int horizonDays = 7}) {
  final d = _day(today);
  final limit = d.add(Duration(days: horizonDays));
  final out = <ProjectAction>[];
  final seen = <String>{};
  for (final t in ganttOrder(p)) {
    if (t.status == 'done' || t.status == 'skipped') continue;
    final isPrep = session?.prep?.id == t.id;
    for (final a in t.actions) {
      if (a.done) continue;
      final due = effectiveDueDate(a, t);
      final inWeek = due != null && !_day(due).isAfter(limit);
      if (!inWeek && !isPrep) continue;
      if (seen.add(a.id)) out.add((task: t, action: a, due: due == null ? null : _day(due)));
    }
  }
  out.sort((x, y) {
    if (x.due == null) return y.due == null ? 0 : 1;
    if (y.due == null) return -1;
    return x.due!.compareTo(y.due!);
  });
  return out;
}

bool _isUpcoming(Project p, DateTime today) {
  final d = _day(today);
  final open = p.tasks.where((t) => t.id != 'gtd-flow' && t.status != 'done' && t.status != 'skipped').toList();
  if (open.isEmpty) return false;
  return open.every((t) => _day(t.startDate).isAfter(d));
}

ProjectMoment projectMoment(Project p, List<Project> all, List<Session> sessions, DateTime now) {
  final session = nextInterventionOf(p, now);
  final days = session?.date.difference(_day(now)).inDays;
  final root = rootProjectOf(p, all);
  return ProjectMoment(
    project: p,
    plan: projectPlan(p, now),
    health: projectHealth(p, sessions, now),
    session: session,
    daysToSession: days,
    weekActions: _weekActions(p, session, now),
    next: nextAction(p),
    upcoming: _isUpcoming(p, now),
    rootTitle: root.id == p.id ? null : root.title,
  );
}

/// Classe les projets vivants (actifs, non en pause, hors dossiers) : le
/// premier est le *projet du moment*. D'abord une séance à 7 jours (la plus
/// proche), sinon le plus en retard sur son plan, puis ceux qui ont une
/// prochaine action, puis les projets à venir, puis le reste ; à égalité,
/// ordre alphabétique.
List<ProjectMoment> rankProjectMoments(List<Project> projects, List<Session> sessions, DateTime now) {
  final out = <({ProjectMoment m, int rank, double key})>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    if (isFolderProject(p, projects)) continue;
    final m = projectMoment(p, projects, sessions, now);
    final int rank;
    final double key;
    if (m.sessionSoon) {
      rank = 0;
      key = m.daysToSession!.toDouble();
    } else if (m.upcoming) {
      rank = 3;
      key = 0;
    } else if (m.behind) {
      rank = 1;
      key = m.plan.ratio;
    } else if (m.next != null) {
      rank = 2;
      key = -m.plan.ratio;
    } else {
      rank = 4;
      key = 0;
    }
    out.add((m: m, rank: rank, key: key));
  }
  out.sort((a, b) {
    final r = a.rank.compareTo(b.rank);
    if (r != 0) return r;
    final k = a.key.compareTo(b.key);
    if (k != 0) return k;
    return a.m.project.title.toLowerCase().compareTo(b.m.project.title.toLowerCase());
  });
  return [for (final e in out) e.m];
}

/// « séance jeu. 30 oct. », « séance demain », « séance aujourd'hui ».
String sessionLabel(Intervention s, DateTime today) {
  final d = s.date.difference(_day(today)).inDays;
  if (d == 0) return 'séance aujourd\'hui';
  if (d == 1) return 'séance demain';
  const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return 'séance ${days[s.date.weekday - 1]} ${s.date.day} ${months[s.date.month - 1]}';
}
