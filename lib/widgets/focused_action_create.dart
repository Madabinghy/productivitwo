import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show flowTaskOf, isFolderProject, isUpcomingTask, kFlowTaskId;
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/widgets/activity_picker.dart';
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

/// « Ajouter une action visée » (feuille Visées aujourd'hui, puis le bouton
/// « + » d'Aujourd'hui, 2026-10-30) : un titre, et « Pour » déjà rempli — le
/// chrono qui tourne, sinon la dernière activité chronométrée — avec en raccourci
/// les projets du moment ; « Autre activité » / « Autre projet » pour le reste.
/// L'action est créée avec `focusDate` = aujourd'hui. `onOther` = lien discret
/// vers la création d'un projet / d'une action sans jour. Renvoie true si créée.
Future<bool> showNewFocusedAction(BuildContext context, {required AppLogic logic, required FirestoreSync sync, VoidCallback? onOther}) async {
  final ctrl = TextEditingController();
  final timeActs = logic.state.activeActivities.where((a) => !a.isHabit).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final all = logic.currentProjects;
  final projects = all.where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, all)).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final now0 = DateTime.now();
  final quickProjects = [for (final m in rankProjectMoments(projects, logic.state.sessions, now0).take(3)) m.project];
  _Owner? owner = _defaultOwner(logic, timeActs);
  final quickActivity = owner?.activity;
  var other = false;

  Future<_Owner?> pickActivity(BuildContext c) async {
    final id = await showActivityPicker(c, activities: timeActs, domains: logic.state.activeDomains, title: 'Action libre · sur quelle activité ?');
    final a = timeActs.where((x) => x.id == id).firstOrNull;
    return a == null ? null : _Owner.activity(a);
  }

  Future<_Owner?> pickTask(BuildContext c, Project p) async {
    final today = DateTime.now();
    final hasTasks = p.tasks.any((t) => t.status == 'pending' && t.id != kFlowTaskId && !isUpcomingTask(t, DateTime(today.year, today.month, today.day)));
    if (!hasTasks) return _Owner.project(p, null);
    final id = await showTaskPicker(c, project: p, includeUpcoming: false);
    if (id == null) return null;
    return _Owner.project(p, id == kPickFlowTask ? null : p.tasks.where((t) => t.id == id).firstOrNull);
  }

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
              leading: const Icon(Icons.view_timeline_outlined),
              title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(s, p),
            ),
        ],
      ),
    );
    if (p == null || !c.mounted) return null;
    return pickTask(c, p);
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (d) => StatefulBuilder(builder: (d, setD) {
      final cs = Theme.of(d).colorScheme;
      final canSave = ctrl.text.trim().isNotEmpty && owner != null;
      void save() {
        if (ctrl.text.trim().isEmpty || owner == null) return;
        Navigator.pop(d, true);
      }

      Widget chip(String label, IconData icon, bool selected, VoidCallback onTap) => ChoiceChip(
            avatar: Icon(icon, size: 16, color: selected ? cs.primary : null),
            label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(label, overflow: TextOverflow.ellipsis)),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
          );
      final o = owner;
      final isQuick = o != null &&
          ((o.activity != null && o.activity!.id == quickActivity?.id) || (o.project != null && quickProjects.any((p) => p.id == o.project!.id)));
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(d).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('☀ À faire aujourd\'hui', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('L\'action est visée aujourd\'hui : elle t\'attend dans ta journée.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setD(() {}),
                onSubmitted: (_) => save(),
                decoration: const InputDecoration(hintText: 'Verbe + objet, ≤ 8 mots', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              Text('POUR', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: cs.onSurface.withValues(alpha: .55))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (quickActivity != null)
                  chip(quickActivity.name, Icons.timer_outlined, o?.activity?.id == quickActivity.id, () => setD(() => owner = _Owner.activity(quickActivity))),
                for (final p in quickProjects)
                  chip(p.title, Icons.view_timeline_outlined, o?.project?.id == p.id, () async {
                    final picked = await pickTask(d, p);
                    if (picked != null) setD(() => owner = picked);
                  }),
              ]),
              if (o != null && (!isQuick || o.task != null))
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(o.activity != null ? Icons.timer_outlined : Icons.view_timeline_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                ),
              if (!other && (quickActivity != null || quickProjects.isNotEmpty))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setD(() => other = true), child: const Text('Ailleurs…')),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    if (timeActs.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final x = await pickActivity(d);
                            if (x != null) setD(() => owner = x);
                          },
                          icon: const Icon(Icons.timer_outlined, size: 18),
                          label: const Text('Une activité'),
                        ),
                      ),
                    if (timeActs.isNotEmpty && projects.isNotEmpty) const SizedBox(width: 8),
                    if (projects.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final x = await pickProject(d);
                            if (x != null) setD(() => owner = x);
                          },
                          icon: const Icon(Icons.view_timeline_outlined, size: 18),
                          label: const Text('Un projet'),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canSave ? save : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('Viser aujourd\'hui'),
              ),
              if (onOther != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(d, false);
                    onOther();
                  },
                  child: const Text('Plutôt un projet ou une action sans jour'),
                ),
            ]),
          ),
        ),
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

/// « Pour » par défaut : l'activité du chrono qui tourne, sinon celle de la
/// dernière session chronométrée.
_Owner? _defaultOwner(AppLogic logic, List<Activity> timeActs) {
  final ids = {for (final a in timeActs) a.id};
  final running = logic.runningActivity();
  if (running != null && ids.contains(running.id)) return _Owner.activity(running);
  final sessions = [...logic.state.sessions]..sort((a, b) => b.startAt.compareTo(a.startAt));
  for (final s in sessions) {
    if (ids.contains(s.activityId)) return _Owner.activity(timeActs.firstWhere((a) => a.id == s.activityId));
  }
  return null;
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
