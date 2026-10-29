import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show flowTaskOf, isFolderProject, isUpcomingTask, kFlowTaskId;
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/widgets/task_fiche_sheet.dart' show stripLeadingEmoji;
import 'package:productivitwo_v1/widgets/task_picker_sheet.dart';

/// Porteur choisi pour une nouvelle action visée : une activité-temps (action
/// libre) ou un projet (tâche ou « Au fil de l'eau »).
class _Owner {
  final Activity? activity;
  final Project? project;
  final ProjectTask? task;
  const _Owner.activity(this.activity)
      : project = null,
        task = null;
  const _Owner.project(this.project, this.task) : activity = null;

  String get label {
    if (activity != null) return activity!.name;
    final t = task;
    return t == null || t.id == kFlowTaskId ? '${project!.title} › Au fil de l\'eau' : '${project!.title} › ${stripLeadingEmoji(t.title)}';
  }
}

/// « Ajouter une action visée » (feuille Visées aujourd'hui, 2026-10-30) :
/// titre, puis action libre (sur une activité-temps) ou projet › tâche ;
/// l'action est créée avec `focusDate` = aujourd'hui. Renvoie true si créée.
Future<bool> showNewFocusedAction(BuildContext context, {required AppLogic logic, required FirestoreSync sync}) async {
  final ctrl = TextEditingController();
  final timeActs = logic.state.activeActivities.where((a) => !a.isHabit).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final all = logic.currentProjects;
  final projects = all.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all)).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  _Owner? owner;

  Future<_Owner?> pickActivity(BuildContext c) => showModalBottomSheet<_Owner>(
        context: c,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (s) => _PickList(
          title: 'Action libre · sur quelle activité ?',
          children: [
            for (final a in timeActs)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(a.name),
                onTap: () => Navigator.pop(s, _Owner.activity(a)),
              ),
          ],
        ),
      );

  Future<_Owner?> pickProject(BuildContext c) async {
    final p = await showModalBottomSheet<Project>(
      context: c,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (s) => _PickList(
        title: 'Dans quel projet ?',
        children: [
          for (final p in projects)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(s, p),
            ),
        ],
      ),
    );
    if (p == null || !c.mounted) return null;
    final today = DateTime.now();
    final hasTasks = p.tasks.any((t) => t.status == 'pending' && t.id != kFlowTaskId && !isUpcomingTask(t, DateTime(today.year, today.month, today.day)));
    if (!hasTasks) return _Owner.project(p, null);
    final id = await showTaskPicker(c, project: p, includeUpcoming: false);
    if (id == null) return null;
    return _Owner.project(p, id == kPickFlowTask ? null : p.tasks.where((t) => t.id == id).firstOrNull);
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (d, setD) {
      final cs = Theme.of(d).colorScheme;
      Widget choice(IconData icon, String label, Future<_Owner?> Function(BuildContext) pick) => Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final o = await pick(d);
                if (o != null) setD(() => owner = o);
              },
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
          );
      return AlertDialog(
        scrollable: true,
        title: const Text('Action visée aujourd\'hui'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Verbe + objet, ≤ 8 mots'),
          ),
          const SizedBox(height: 14),
          const Text('Pour', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (owner != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(owner!.activity != null ? Icons.timer_outlined : Icons.folder_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(owner!.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ),
          Row(children: [
            if (timeActs.isNotEmpty) choice(Icons.bolt_outlined, 'Libre', pickActivity),
            if (timeActs.isNotEmpty && projects.isNotEmpty) const SizedBox(width: 8),
            if (projects.isNotEmpty) choice(Icons.folder_outlined, 'Projet', pickProject),
          ]),
          const SizedBox(height: 6),
          Text('Libre = une action sans projet, rangée sous une activité (son chrono).',
              style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .55))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty || owner == null) return;
              Navigator.pop(d, true);
            },
            child: const Text('Viser aujourd\'hui'),
          ),
        ],
      );
    }),
  );
  final title = ctrl.text.trim();
  ctrl.dispose();
  final o = owner;
  if (ok != true || title.isEmpty || o == null) return false;
  final now = DateTime.now();
  final action = TaskAction(
    title: title,
    estimatedMin: defaultEstimateFor(title),
    focusDate: DateTime(now.year, now.month, now.day),
  );
  if (o.activity != null) {
    final a = o.activity!;
    action.linkedActivityId = a.id;
    a.ownActions.add(action);
    await sync.updateOwnActions(a.id, a.ownActions);
  } else {
    final p = o.project!;
    (o.task ?? flowTaskOf(p)).actions.add(action);
    await sync.saveProjectTasks(p.id, p.tasks);
  }
  logic.onChange();
  return true;
}

class _PickList extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _PickList({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          ),
          Flexible(child: ListView(shrinkWrap: true, children: children)),
        ]),
      ),
    );
  }
}
