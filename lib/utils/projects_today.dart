import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn, isOverdueAction, isFolderProject, isUpcomingTask;
import 'package:productivitwo_v1/utils/project_health.dart' show nextAction;

/// Onglet Projets à 3 onglets (maquette validée 2026-11-01 « Projets et
/// actions ») : en tête, « Pour aujourd'hui » — la parole du jour, ce qui est
/// au programme, les visées aujourd'hui, puis un retard par projet.

enum TodayReason { parole, program, focus, late }

class TodayAction {
  final TaskAction action;
  final Project? project;
  final ProjectTask? task;
  final Activity? owner; // action propre d'une activité
  final TodayReason reason;
  const TodayAction(this.action, this.reason, {this.project, this.task, this.owner});
}

bool _liveProject(Project p) => p.status == 'active' && !p.paused;

List<TodayAction> todayActions({
  required List<Project> projects,
  required List<Activity> activities,
  required DateTime today,
  Set<String> paroleIds = const {},
  Set<String> programActionIds = const {},
}) {
  final out = <TodayAction>[];
  final seen = <String>{};
  final candidates = <TodayAction Function(TodayReason)>[];
  final all = <(TaskAction, Project?, ProjectTask?, Activity?)>[
    for (final p in projects.where(_liveProject))
      for (final t in p.tasks)
        if (t.status != 'done' && t.status != 'skipped')
          for (final a in t.actions)
            if (!a.done) (a, p, t, null),
    for (final act in activities.where((x) => !x.deleted))
      for (final a in act.ownActions)
        if (!a.done) (a, null, null, act),
  ];
  candidates.clear();
  void add(TodayReason r, bool Function((TaskAction, Project?, ProjectTask?, Activity?) x) test) {
    for (final x in all) {
      if (seen.contains(x.$1.id) || !test(x)) continue;
      seen.add(x.$1.id);
      out.add(TodayAction(x.$1, r, project: x.$2, task: x.$3, owner: x.$4));
    }
  }

  add(TodayReason.parole, (x) => paroleIds.contains(x.$1.id));
  add(TodayReason.program, (x) => programActionIds.contains(x.$1.id));
  add(TodayReason.focus, (x) => isFocusedOn(x.$1, today));
  // Un retard par projet : sa prochaine action, si elle est en retard.
  for (final p in projects.where(_liveProject)) {
    if (isFolderProject(p, projects)) continue;
    final n = nextAction(p);
    if (n == null || seen.contains(n.action.id) || isUpcomingTask(n.task, today)) continue;
    if (!isOverdueAction(n.action, n.task, today)) continue;
    seen.add(n.action.id);
    out.add(TodayAction(n.action, TodayReason.late, project: p, task: n.task));
  }
  return out;
}

/// Actions propres ouvertes des activités (« Sans projet »).
List<(Activity, TaskAction)> looseActions(List<Activity> activities) => [
      for (final act in activities.where((x) => !x.deleted))
        for (final a in act.ownActions)
          if (!a.done) (act, a),
    ];
