import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';

// Dialogs CRUD des actions (ex-WebActionsView), partagés par l'onglet Actions.

/// Édition complète d'une action (titre + contextes + suppression ; monter /
/// descendre / déplacer pour une action de projet). Persiste et retourne true
/// si quelque chose a changé.
Future<bool> showEditActionDialog(
  BuildContext context, {
  required FirestoreSync sync,
  required TaskAction action,
  required List<Project> projects,
  Project? project,
  ProjectTask? task,
  Activity? activity,
}) async {
  final available = await sync.fetchAvailableContexts();
  if (!context.mounted) return false;
  final selected = Set<String>.of(action.allContexts);
  final all = [...available, ...selected.where((c) => !available.contains(c))];
  final titleCtrl = TextEditingController(text: action.title);
  final estCtrl = TextEditingController(text: action.estimatedMin?.toString() ?? '');
  // Brouillon de checklist : la règle d'achèvement s'applique à l'enregistrement.
  final draft = TaskAction(
    id: action.id,
    title: action.title,
    done: action.done,
    doneAt: action.doneAt,
    checklist: [
      for (final c in action.checklist)
        ChecklistItem(id: c.id, title: c.title, done: c.done, doneAt: c.doneAt),
    ],
  );
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Action'),
      content: StatefulBuilder(
        builder: (ctx, setLocal) => SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Titre', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: estCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Durée estimée (min, optionnel)',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
              const SizedBox(height: 12),
              Text('Où / avec quoi cette action est-elle réalisable ?',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.55))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in all)
                    FilterChip(
                      selected: selected.contains(c),
                      onSelected: (v) => setLocal(() {
                        v ? selected.add(c) : selected.remove(c);
                      }),
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Checklist (micro-actions)',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.55))),
              const SizedBox(height: 4),
              ChecklistEditor(
                items: draft.checklist,
                onToggle: (c, v) => setLocal(() => setChecklistItem(draft, c.id, v)),
                onAdd: (t) => setLocal(() => addChecklistItem(draft, t)),
                onDelete: (c) => setLocal(() => removeChecklistItem(draft, c.id)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(ctx, 'delete'),
          icon: Icon(Icons.delete_outline, size: 16, color: Theme.of(ctx).colorScheme.error),
          label: Text('Supprimer', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
        if (task != null) ...[
          IconButton(
              tooltip: 'Monter',
              icon: const Icon(Icons.arrow_upward, size: 16),
              onPressed: () => Navigator.pop(ctx, 'up')),
          IconButton(
              tooltip: 'Descendre',
              icon: const Icon(Icons.arrow_downward, size: 16),
              onPressed: () => Navigator.pop(ctx, 'down')),
          IconButton(
              tooltip: 'Déplacer vers une autre tâche',
              icon: const Icon(Icons.drive_file_move_outlined, size: 16),
              onPressed: () => Navigator.pop(ctx, 'move')),
        ],
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Enregistrer')),
      ],
    ),
  );
  final newTitle = titleCtrl.text.trim();
  final estRaw = estCtrl.text.trim();
  titleCtrl.dispose();
  estCtrl.dispose();
  if (result == null) return false;
  if (result == 'up' || result == 'down') {
    if (project != null && task != null) {
      return _nudgeAction(sync, project, task, action, up: result == 'up');
    }
    return false;
  }
  if (result == 'move') {
    if (project != null && task != null && context.mounted) {
      return moveActionToAnotherTask(context,
          sync: sync, projects: projects, from: project, fromTask: task, action: action);
    }
    return false;
  }
  if (result == 'delete') {
    task?.actions.remove(action);
    activity?.ownActions.remove(action);
  } else {
    if (newTitle.isNotEmpty) action.title = newTitle;
    action.setContexts(selected.toList());
    final est = int.tryParse(estRaw);
    action.estimatedMin = est != null && est > 0 ? est : null;
    action.checklist
      ..clear()
      ..addAll(draft.checklist);
    action.done = draft.done;
    action.doneAt = draft.doneAt;
  }
  if (project != null) {
    await sync.saveProjectTasks(project.id, project.tasks);
  } else if (activity != null) {
    await sync.updateOwnActions(activity.id, activity.ownActions);
  }
  return true;
}

/// Monte/descend une action parmi les actions NON FAITES de sa tâche —
/// l'ordre du tableau task.actions est l'ordre d'affichage partout.
Future<bool> _nudgeAction(FirestoreSync sync, Project p, ProjectTask task, TaskAction a,
    {required bool up}) async {
  final idx = task.actions.indexOf(a);
  if (idx == -1) return false;
  int? swapWith;
  if (up) {
    for (var i = idx - 1; i >= 0; i--) {
      if (!task.actions[i].done) {
        swapWith = i;
        break;
      }
    }
  } else {
    for (var i = idx + 1; i < task.actions.length; i++) {
      if (!task.actions[i].done) {
        swapWith = i;
        break;
      }
    }
  }
  if (swapWith == null) return false;
  final tmp = task.actions[swapWith];
  task.actions[swapWith] = a;
  task.actions[idx] = tmp;
  await sync.saveProjectTasks(p.id, p.tasks);
  return true;
}

/// « Déplacer vers une autre tâche » : sélecteur des tâches ouvertes de tous
/// les projets actifs, puis FirestoreSync.moveActionToTask (même helper que la
/// fiche tâche du Gantt et le mobile). Retourne true si déplacée.
Future<bool> moveActionToAnotherTask(
  BuildContext context, {
  required FirestoreSync sync,
  required List<Project> projects,
  required Project from,
  required ProjectTask fromTask,
  required TaskAction action,
}) async {
  final cs = Theme.of(context).colorScheme;
  final candidates = <(Project, ProjectTask)>[
    for (final p in projects)
      if (p.status == 'active' && !p.paused)
        for (final t in p.tasks)
          if (!t.isMilestone && t.status != 'done' && t.status != 'skipped' && t.id != fromTask.id)
            (p, t),
  ];
  if (candidates.isEmpty) return false;
  final picked = await showDialog<(Project, ProjectTask)>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Déplacer vers…'),
      children: [
        for (final (p, t) in candidates)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, (p, t)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45))),
              ],
            ),
          ),
      ],
    ),
  );
  if (picked == null) return false;
  await sync.moveActionToTask(
    fromProjectId: from.id,
    fromTaskId: fromTask.id,
    toProjectId: picked.$1.id,
    toTaskId: picked.$2.id,
    actionId: action.id,
  );
  fromTask.actions.removeWhere((x) => x.id == action.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Action déplacée vers « ${picked.$2.title} ».'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }
  return true;
}

/// Crée une action SIMPLE (`Activity.ownActions`) sur une activité-temps.
/// Retourne true si créée (l'activité locale est mise à jour).
Future<bool> showAddOwnActionDialog(
  BuildContext context, {
  required FirestoreSync sync,
  required List<Activity> activities,
}) async {
  final timeActivities =
      activities.where((a) => !a.deleted && a.type == 'time').toList();
  if (timeActivities.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Crée d\'abord une activité-temps pour y rattacher des actions simples.'),
      behavior: SnackBarBehavior.floating,
    ));
    return false;
  }
  final ctrl = TextEditingController();
  var picked = <String>[];
  var activityId = timeActivities.first.id;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Action simple'),
      content: StatefulBuilder(
        builder: (ctx, setLocal) => SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Ex : Réserver le contrôle technique',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              ContextPicker(values: picked, sync: sync, onValuesChanged: (list) => picked = list),
              const SizedBox(height: 12),
              Text('SUR L\'ACTIVITÉ',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.45))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in timeActivities)
                    ChoiceChip(
                      selected: activityId == a.id,
                      onSelected: (_) => setLocal(() => activityId = a.id),
                      showCheckmark: false,
                      label: Text(a.name),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Créer')),
      ],
    ),
  );
  final title = ctrl.text.trim();
  ctrl.dispose();
  if (saved != true || title.isEmpty) return false;
  await sync.addOwnActionToActivity(activityId, title, contexts: picked);
  final act = activities.where((a) => a.id == activityId).firstOrNull;
  act?.ownActions.add(TaskAction(
    title: title,
    linkedActivityId: activityId,
    context: picked.isEmpty ? null : picked.first,
    contexts: List.of(picked),
    estimatedMin: defaultEstimateFor(title, contexts: picked),
  ));
  return true;
}
