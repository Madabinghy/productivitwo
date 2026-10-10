import 'package:collection/collection.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

/// Logique pure de l'onglet Actions (refonte web § 5) — testable sans widget.

/// « J'ai… » : 15 min · 1 h · plus. Une action sans estimation passe toujours.
enum TimeBucket { quarter, hour, more }

bool passesContexts(TaskAction a, Set<String> selected) {
  if (selected.isEmpty) return true;
  final ctx = a.allContexts;
  if (ctx.isEmpty) return true;
  return ctx.any(selected.contains);
}

bool passesTime(TaskAction a, TimeBucket? bucket) {
  final est = a.estimatedMin;
  if (bucket == null || est == null) return true;
  return switch (bucket) {
    TimeBucket.quarter => est <= 15,
    TimeBucket.hour => est <= 60,
    TimeBucket.more => est > 60,
  };
}

/// Contextes connus : défauts + tous ceux rencontrés sur les actions ouvertes.
List<String> knownContexts(List<Project> projects, List<Activity> activities) {
  final seen = <String>{...kDefaultGtdContexts};
  final extra = <String>[];
  void visit(TaskAction a) {
    for (final c in a.allContexts) {
      if (seen.add(c)) extra.add(c);
    }
  }
  for (final p in projects) {
    for (final t in p.tasks) {
      for (final a in t.actions) {
        if (!a.done) visit(a);
      }
    }
  }
  for (final act in activities) {
    for (final a in act.ownActions) {
      if (!a.done) visit(a);
    }
  }
  extra.sort();
  return [...kDefaultGtdContexts, ...extra];
}

/// `milestone` = par urgence du prochain jalon / séance du projet (brief 2.4 :
/// « j'ai 20 min » → d'abord ce qui sert la séance la plus proche).
enum ActionsSort { dueDate, domain, alpha, milestone }

class ProjectActions {
  final Project project;
  /// Actions ouvertes, prochaine action en tête, puis ordre Gantt.
  final List<({ProjectTask task, TaskAction action})> entries;
  const ProjectActions(this.project, this.entries);
}

/// Un groupe par projet actif non en pause, filtré et trié.
List<ProjectActions> projectActionGroups(
  List<Project> projects, {
  required bool Function(TaskAction) filter,
  /// Filtre sur la tâche porteuse (ex. « En retard » = échéance dépassée) ;
  /// null = toutes.
  bool Function(ProjectTask)? taskFilter,
  ActionsSort sort = ActionsSort.dueDate,
  List<String> domainOrder = const [],
  /// Date du prochain jalon / séance d'un projet (tri `milestone`) ; null = aucun.
  DateTime? Function(Project)? urgencyOf,
}) {
  final out = <ProjectActions>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    final entries = <({ProjectTask task, TaskAction action})>[];
    final next = nextAction(p);
    if (next != null && filter(next.action) && (taskFilter?.call(next.task) ?? true)) {
      entries.add(next);
    }
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      if (taskFilter != null && !taskFilter(t)) continue;
      for (final a in t.actions) {
        if (a.done || !filter(a)) continue;
        if (next != null && a.id == next.action.id) continue;
        entries.add((task: t, action: a));
      }
    }
    out.add(ProjectActions(p, entries));
  }
  int byDue(Project a, Project b) {
    if (a.endDate == null) return b.endDate == null ? 0 : 1;
    if (b.endDate == null) return -1;
    return a.endDate!.compareTo(b.endDate!);
  }
  out.sort((x, y) {
    final a = x.project, b = y.project;
    switch (sort) {
      case ActionsSort.dueDate:
        return byDue(a, b);
      case ActionsSort.milestone:
        final ua = urgencyOf?.call(a), ub = urgencyOf?.call(b);
        if (ua == null && ub == null) return byDue(a, b);
        if (ua == null) return 1;
        if (ub == null) return -1;
        final c = ua.compareTo(ub);
        return c != 0 ? c : byDue(a, b);
      case ActionsSort.alpha:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case ActionsSort.domain:
        final ia = domainOrder.indexOf(a.domainId ?? '');
        final ib = domainOrder.indexOf(b.domainId ?? '');
        final ra = ia < 0 ? domainOrder.length : ia;
        final rb = ib < 0 ? domainOrder.length : ib;
        return ra != rb ? ra.compareTo(rb) : byDue(a, b);
    }
  });
  return out;
}

/// Projet racine (client) d'un projet : on remonte `parentProjectId` jusqu'à
/// un projet sans parent connu. Un parent introuvable = le projet est racine.
Project rootProjectOf(Project p, List<Project> all) {
  var cur = p;
  final seen = <String>{p.id};
  while (cur.parentProjectId != null) {
    final parent = all.where((x) => x.id == cur.parentProjectId).firstOrNull;
    if (parent == null || !seen.add(parent.id)) break;
    cur = parent;
  }
  return cur;
}

bool _liveProject(Project p) => p.status == 'active' && !p.paused;

/// « Pour… » : les racines (clients, dossiers) qui ont au moins un projet
/// vivant sous elles (elles comprises), triées par titre.
List<Project> clientRoots(List<Project> all) {
  final roots = <String, Project>{};
  for (final p in all) {
    // Un dossier ne compte que par ses enfants vivants.
    if (!_liveProject(p) || isFolderProject(p, all)) continue;
    final r = rootProjectOf(p, all);
    roots[r.id] = r;
  }
  return roots.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

/// Entrée « Perso » du filtre « Pour… » : les actions SANS projet (actions
/// propres d'activité). Un client choisi ne montre que ses projets ; sans
/// cette entrée, les actions simples n'auraient plus d'endroit où apparaître
/// filtrées.
const String kPersoClientId = '__perso__';
const String kPersoClientLabel = 'Perso';

/// Filtre « Pour… » : null = tout ; [kPersoClientId] = actions sans projet ;
/// sinon le projet racine (client / dossier) de [p] doit être [clientId].
/// Une action simple n'est « pour » aucun client.
bool inClient(String? clientId, Project? p, List<Project> all) {
  if (clientId == null) return true;
  if (clientId == kPersoClientId) return p == null;
  return p != null && rootProjectOf(p, all).id == clientId;
}

/// Dossier : un projet racine sans tâche dont d'autres projets dépendent —
/// il sert de client, pas de liste d'actions (jamais « Définir la prochaine »).
bool isFolderProject(Project p, List<Project> all) =>
    p.tasks.isEmpty && all.any((x) => x.parentProjectId == p.id);

/// Tâche EN RETARD : ouverte (ni faite ni annulée) et échéance strictement
/// avant le jour de [today]. Règle unique du filtre « En retard » (web), du
/// groupe « En retard » et de la pastille.
bool isOverdueTask(ProjectTask t, DateTime today) {
  if (t.status == 'done' || t.status == 'skipped' || t.endDate == null) return false;
  final d = DateTime(today.year, today.month, today.day);
  final due = DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day);
  return due.isBefore(d);
}

/// Actions EN RETARD : ouvertes, dans une tâche ouverte (ni faite ni annulée)
/// d'un projet vivant, dont l'échéance de la tâche est avant [today]. Même
/// règle que le groupe « En retard » d'Actions (mobile et web) — alimente la
/// pastille de l'onglet Actions.
int overdueActionCount(List<Project> projects, DateTime today) {
  var n = 0;
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      if (!isOverdueTask(t, today)) continue;
      n += t.actions.where((a) => !a.done).length;
    }
  }
  return n;
}

/// Groupe de projets sous un dossier (racine sans tâche) : [folder] null =
/// projet hors dossier, seul dans son groupe.
class FolderGroup {
  final Project? folder;
  final List<Project> projects;
  const FolderGroup(this.folder, this.projects);
}

/// Regroupe [projects] par FAMILLE (projet racine), que la racine soit un
/// dossier ou un projet qui a ses propres tâches (Chérubins, SOF Conseil) :
/// une famille de plusieurs projets donne un groupe dont `folder` est la
/// racine et dont la racine, si elle est listée, vient en tête. Un projet
/// seul dans sa famille reste seul (`folder` null). Ordre d'apparition gardé ;
/// un dossier n'est jamais listé comme projet.
List<FolderGroup> groupByRoot(List<Project> projects, List<Project> all) {
  final order = <String>[];
  final roots = <String, Project>{};
  final members = <String, List<Project>>{};
  for (final p in projects) {
    if (isFolderProject(p, all)) continue;
    final r = rootProjectOf(p, all);
    if (!members.containsKey(r.id)) {
      order.add(r.id);
      roots[r.id] = r;
      members[r.id] = [];
    }
    members[r.id]!.add(p);
  }
  return [
    for (final id in order)
      if (members[id]!.length == 1 && members[id]!.single.id == id)
        FolderGroup(null, members[id]!)
      else
        FolderGroup(roots[id], [
          ...members[id]!.where((p) => p.id == id),
          ...members[id]!.where((p) => p.id != id),
        ]),
  ];
}

/// Regroupe [projects] par dossier en gardant l'ordre d'apparition : le
/// premier projet d'un dossier ouvre son groupe, les suivants s'y rangent.
/// Les dossiers eux-mêmes présents dans [projects] ne sont pas listés (ils
/// sont l'en-tête du groupe) ; un dossier sans enfant listé n'apparaît pas.
List<FolderGroup> groupByFolder(List<Project> projects, List<Project> all) {
  final out = <FolderGroup>[];
  final byFolder = <String, FolderGroup>{};
  for (final p in projects) {
    if (isFolderProject(p, all)) continue;
    final root = rootProjectOf(p, all);
    if (root.id == p.id || !isFolderProject(root, all)) {
      out.add(FolderGroup(null, [p]));
      continue;
    }
    final g = byFolder[root.id];
    if (g != null) {
      g.projects.add(p);
    } else {
      final ng = FolderGroup(root, [p]);
      byFolder[root.id] = ng;
      out.add(ng);
    }
  }
  return out;
}

/// Filtre actif (contexte ou temps) : on ne montre que les projets qui ont au
/// moins une action qui passe — « que puis-je faire @maison ? » va droit à
/// l'essentiel. Les autres sont comptés (lien « Afficher ») au lieu d'être
/// listés vides. Sans filtre, tout reste visible (« Définir la prochaine »).
({List<ProjectActions> shown, int hidden}) visibleProjectGroups(
    List<ProjectActions> groups, {required bool filtering}) {
  if (!filtering) return (shown: groups, hidden: 0);
  final shown = groups.where((g) => g.entries.isNotEmpty).toList();
  return (shown: shown, hidden: groups.length - shown.length);
}

/// « Possible maintenant » : actions ouvertes dont l'activité-temps liée est
/// celle du chrono en cours — lien propre (`TaskAction.linkedActivityId`),
/// lien du projet, ou action simple de cette activité.
List<({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>
    possibleNow(
  List<Project> projects,
  List<Activity> activities,
  String activityId, {
  required bool Function(TaskAction) filter,
}) {
  final out = <({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      for (final a in t.actions) {
        if (a.done || !filter(a)) continue;
        final linked = a.linkedActivityId ?? p.linkedActivityId;
        if (linked == activityId) {
          out.add((action: a, project: p, task: t, activity: null));
        }
      }
    }
  }
  for (final act in activities) {
    if (act.deleted || act.id != activityId) continue;
    for (final a in act.ownActions) {
      if (!a.done && filter(a)) {
        out.add((action: a, project: null, task: null, activity: act));
      }
    }
  }
  return out;
}

/// Actions simples ouvertes (`Activity.ownActions`), par activité.
List<({Activity activity, List<TaskAction> actions})> ownActionGroups(
  List<Activity> activities, {
  required bool Function(TaskAction) filter,
}) =>
    [
      for (final act in activities)
        if (!act.deleted)
          if (act.ownActions.any((a) => !a.done && filter(a)))
            (
              activity: act,
              actions: act.ownActions.where((a) => !a.done && filter(a)).toList(),
            ),
    ];
