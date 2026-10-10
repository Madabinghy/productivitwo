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
