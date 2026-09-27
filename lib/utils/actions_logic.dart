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

enum ActionsSort { dueDate, domain, alpha }

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
  ActionsSort sort = ActionsSort.dueDate,
  List<String> domainOrder = const [],
}) {
  final out = <ProjectActions>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    final entries = <({ProjectTask task, TaskAction action})>[];
    final next = nextAction(p);
    if (next != null && filter(next.action)) entries.add(next);
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped') continue;
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
