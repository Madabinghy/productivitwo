import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

/// Bande Focus (web, Aujourd'hui) : quand un chrono tourne sur une action,
/// on remonte l'action, ses étapes et son contexte là où est l'utilisateur,
/// au lieu de les chercher dans la fiche projet. Logique pure, testable.

/// Ligne de la mini-spec « 4 lignes » d'une tâche de dev (CLAUDE.md) : les
/// actions dont le titre commence par « Objectif : », « Fichiers : »,
/// « Critères : », « Contraintes : ».
const kSpecLabels = ['Objectif', 'Fichiers', 'Critères', 'Contraintes'];

({String label, String text})? specLineOf(String title) {
  final i = title.indexOf(':');
  if (i <= 0) return null;
  final label = title.substring(0, i).trim();
  if (!kSpecLabels.contains(label)) return null;
  final text = title.substring(i + 1).trim();
  return text.isEmpty ? null : (label: label, text: text);
}

bool isSpecAction(TaskAction a) => specLineOf(a.title) != null;

/// Consignes de la tâche : la spec 4 lignes si elle existe, sinon rien (la
/// description est affichée à part).
List<({String label, String text})> taskSpecLines(ProjectTask t) =>
    [for (final a in t.actions) if (specLineOf(a.title) case final l?) l];

/// Actions « étapes » d'une tâche (hors lignes de spec).
List<TaskAction> taskSteps(ProjectTask t) =>
    t.actions.where((a) => !isSpecAction(a)).toList();

class FocusTarget {
  final Project project;
  final ProjectTask task;
  final TaskAction action;
  /// Bloc du programme à l'origine du chrono (null = chrono lancé hors bloc).
  final ScheduleBlock? block;
  const FocusTarget(
      {required this.project, required this.task, required this.action, this.block});

  ProjectPhase? get phase =>
      project.phases.where((ph) => ph.id == task.phaseId).firstOrNull;

  /// Étapes affichées : la checklist de l'action ; si elle est vide et que la
  /// tâche a plusieurs actions-étapes, ce sont ces actions qui servent
  /// d'étapes (le bloc visait la tâche, pas une action précise).
  bool get stepsAreTaskActions =>
      action.checklist.isEmpty && taskSteps(task).length > 1;
}

/// Cible de la bande : le bloc courant si le chrono lui correspond, sinon la
/// tâche/action portées par la session (chrono lancé depuis Actions ou la
/// fiche projet). Null = pas de bande (chrono libre, routine, pas de projet).
FocusTarget? resolveFocusTarget({
  required Session? open,
  required ScheduleBlock? currentBlock,
  required List<Project> projects,
}) {
  if (open == null) return null;
  Project? projectOf(String? id) =>
      id == null ? null : projects.where((p) => p.id == id).firstOrNull;
  final b = currentBlock;
  if (b != null && b.taskId != null) {
    final p = projectOf(b.projectId);
    if (p != null &&
        sessionMatchesBlock(open, b, projectLinkedActivityId: p.linkedActivityId)) {
      final r = resolveBlockAction(p, b);
      if (r != null) return FocusTarget(project: p, task: r.task, action: r.action, block: b);
    }
  }
  if (open.taskId == null) return null;
  for (final p in projects) {
    final t = p.tasks.where((x) => x.id == open.taskId).firstOrNull;
    if (t == null) continue;
    final a = (open.actionId != null
            ? t.actions.where((x) => x.id == open.actionId).firstOrNull
            : null) ??
        nextOpenAction(t) ??
        t.actions.firstOrNull;
    if (a == null) return null;
    return FocusTarget(project: p, task: t, action: a);
  }
  return null;
}

/// Documents liés : ceux de la tâche d'abord, sinon ceux du projet (4 max).
List<Map<String, dynamic>> focusDocuments(
    List<Map<String, dynamic>> projectDocs, String taskId,
    {int max = 4}) {
  final ofTask = projectDocs.where((d) => d['taskId'] == taskId).toList();
  final list = ofTask.isNotEmpty ? ofTask : projectDocs;
  return list.take(max).toList();
}

/// Prochaine action ouverte de la tâche après [current] (null si aucune).
TaskAction? nextStepAfter(ProjectTask t, TaskAction current) {
  var seen = false;
  for (final a in taskSteps(t)) {
    if (a.id == current.id) {
      seen = true;
      continue;
    }
    if (seen && !a.done) return a;
  }
  return taskSteps(t).where((a) => !a.done && a.id != current.id).firstOrNull;
}
