import 'package:productivitwo_v1/models.dart';

/// Ce qu'on a à faire pendant un bloc de tâche (écran « bloc », 2026-10) :
/// l'action visée par le bloc (sinon la première action ouverte de la tâche)
/// en avant avec ses étapes, les autres actions ouvertes repliées, les faites
/// à part.
class BlockWork {
  final TaskAction? focus;
  final List<TaskAction> open;
  final List<TaskAction> done;
  const BlockWork(this.focus, this.open, this.done);
}

BlockWork blockWork(ProjectTask task, String? actionId) {
  TaskAction? focus;
  if (actionId != null) {
    for (final a in task.actions) {
      if (a.id == actionId) focus = a;
    }
  }
  focus ??= task.actions.where((a) => !a.done).firstOrNull;
  return BlockWork(
    focus,
    [for (final a in task.actions) if (!a.done && a.id != focus?.id) a],
    [for (final a in task.actions) if (a.done && a.id != focus?.id) a],
  );
}

/// La cible DU MOMENT d'un bloc à plusieurs cibles (2026-11-16) : la première,
/// dans l'ordre du bloc, où il reste quelque chose à faire — une tâche ouverte
/// avec une action ouverte (ou sans action encore), un projet visé en entier
/// qui a une action ouverte. Tout est fait, ou une seule cible : la principale.
BlockTarget? activeTargetOf(ScheduleBlock b, List<Project> projects) {
  final all = b.targets;
  if (all.length < 2) return all.firstOrNull;
  for (final t in all) {
    final p = projects.where((x) => x.id == t.projectId).firstOrNull;
    if (p == null) continue;
    bool open(ProjectTask x) =>
        x.status != 'done' && x.status != 'skipped' && (x.actions.isEmpty || x.actions.any((a) => !a.done));
    if (t.taskId == null) {
      if (p.tasks.any((x) => x.actions.any((a) => !a.done) && open(x))) return t;
      continue;
    }
    final task = p.tasks.where((x) => x.id == t.taskId).firstOrNull;
    if (task != null && open(task)) return t;
  }
  return all.first;
}
