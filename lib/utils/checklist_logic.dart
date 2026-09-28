import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

/// Logique pure des checklists d'actions (3ᵉ niveau) — testable sans widget.
/// Règle d'achèvement (CLAUDE.md) : tous les items cochés → l'action passe
/// faite ; décocher un item d'une action faite la rouvre.

/// Coche/décoche [itemId] et applique la règle. Retourne true si l'état
/// `done` de l'action a changé (pour le retour utilisateur).
bool setChecklistItem(TaskAction a, String itemId, bool done, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final item = a.checklist.where((c) => c.id == itemId).firstOrNull;
  if (item == null) return false;
  item.done = done;
  item.doneAt = done ? at : null;
  final allDone = a.checklist.isNotEmpty && a.checklist.every((c) => c.done);
  if (allDone && !a.done) {
    a.done = true;
    a.doneAt = at;
    return true;
  }
  if (!done && a.done) {
    a.done = false;
    a.doneAt = null;
    return true;
  }
  return false;
}

/// Ajoute un item (titre non vide) en fin de checklist ; une action faite qui
/// reçoit un nouvel item est rouverte. Null si le titre est vide.
ChecklistItem? addChecklistItem(TaskAction a, String title) {
  final t = title.trim();
  if (t.isEmpty) return null;
  final item = ChecklistItem(title: t);
  a.checklist.add(item);
  if (a.done) {
    a.done = false;
    a.doneAt = null;
  }
  return item;
}

void removeChecklistItem(TaskAction a, String itemId) =>
    a.checklist.removeWhere((c) => c.id == itemId);

/// Première action ouverte d'une tâche (ordre du tableau = ordre d'affichage).
TaskAction? nextOpenAction(ProjectTask t) => t.actions.where((a) => !a.done).firstOrNull;

/// Action visée par un bloc du programme : `actionId` explicite, sinon la
/// prochaine action ouverte de sa tâche. Null si le bloc ne vise rien.
({ProjectTask task, TaskAction action})? resolveBlockAction(Project? p, ScheduleBlock b) {
  if (p == null || b.taskId == null) return null;
  final task = p.tasks.where((t) => t.id == b.taskId).firstOrNull;
  if (task == null) return null;
  if (b.actionId != null) {
    final a = task.actions.where((x) => x.id == b.actionId).firstOrNull;
    if (a != null) return (task: task, action: a);
  }
  final next = nextOpenAction(task) ?? nextAction(p)?.action;
  return next == null ? null : (task: task, action: next);
}
