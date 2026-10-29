import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show effectiveDueDate, actionDueLabel, shortDateFr, rootProjectOf, focusLabel, isStaleFocus;
import 'package:productivitwo_v1/widgets/focus_day_sheet.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show isPrepTask, isMilestoneTask, isClosureTask;
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart' show taskBricks;
import 'package:productivitwo_v1/utils/time_spent.dart' show spentByAction, spentLabel;
import 'package:productivitwo_v1/widgets/context_picker.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart' show showDocList;
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:productivitwo_v1/widgets/steps_section.dart';
import 'package:productivitwo_v1/widgets/task_schedule.dart';
import 'package:productivitwo_v1/widgets/confirm_done.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

/// Fiche de TÂCHE « une carte, une fiche » (2026-10, maquette « Fiche de
/// tâche ») : en-tête `FicheHeader` (émoji de rôle en petit, titre sur deux
/// lignes, chip d'état, ligne d'info), ACTIONS en lignes `StatusRow` (tap = la
/// fiche d'action : étapes, note, échéance, activité liée ; cocher = fait ;
/// appui long = organiser), FAITES repliées, DÉTAIL repliable (description,
/// dates et phase, activité liée, documents), gestes `FicheActions`. Remplace
/// l'ancienne `_TaskDetailSheet` (titre géant, onglets À faire / Fait, chevrons).
/// Même modèle de données : tout reste cochable sur le web et par le MCP.
Future<void> showTaskFiche(
  BuildContext context, {
  required Project project,
  required ProjectTask task,
  List<Activity> activities = const [],
  List<Project> allProjects = const [],
  FirestoreSync? sync,
  AppLogic? logic,
  void Function(Activity activity, Project project, ProjectTask task)? onStartTimer,
  String? expandActionId,
  VoidCallback? onChanged,
}) {
  return showFiche<void>(
    context,
    builder: (ctx, scroll) => _TaskFiche(
      project: project,
      task: task,
      activities: activities,
      allProjects: allProjects,
      sync: sync ?? FirestoreSync(),
      logic: logic,
      onStartTimer: onStartTimer,
      expandActionId: expandActionId,
      onChanged: onChanged,
      scroll: scroll,
    ),
  );
}

final RegExp _leadingEmoji = RegExp(r'^\s*((?:\p{Extended_Pictographic}|[\u2600-\u27BF])\uFE0F?)\s*', unicode: true);

/// Titre sans son émoji de tête (« ✍️ Corriger — 5e » → « Corriger — 5e »).
String stripLeadingEmoji(String title) => title.replaceFirst(_leadingEmoji, '');

class _TaskFiche extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final List<Activity> activities;
  final List<Project> allProjects;
  final FirestoreSync sync;
  final AppLogic? logic;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;
  final String? expandActionId;
  final VoidCallback? onChanged;
  final ScrollController scroll;
  const _TaskFiche({
    required this.project,
    required this.task,
    required this.activities,
    this.allProjects = const [],
    required this.sync,
    required this.logic,
    required this.onStartTimer,
    required this.expandActionId,
    required this.onChanged,
    required this.scroll,
  });

  @override
  State<_TaskFiche> createState() => _TaskFicheState();
}

class _TaskFicheState extends State<_TaskFiche> {
  bool _showDone = false;
  bool _detailOpen = false;
  int? _docCount;

  Project get p => widget.project;
  ProjectTask get t => widget.task;

  @override
  void initState() {
    super.initState();
    _detailOpen = (t.description ?? '').trim().isNotEmpty;
    widget.logic?.addListener(_onLogic);
    widget.sync.fetchDocuments(taskId: t.id).then((d) {
      if (mounted) setState(() => _docCount = d.length);
    }).catchError((_) {});
    final target = widget.expandActionId;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final a = t.actions.where((x) => x.id == target).firstOrNull;
        if (a != null && mounted) _openAction(a);
      });
    }
  }

  @override
  void dispose() {
    widget.logic?.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  // ── Persistance ─────────────────────────────────────────────────────────────

  void _changed() {
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _saveTasks() async {
    await widget.sync.saveProjectTasks(p.id, p.tasks);
    _changed();
  }

  Future<void> _patchAction(TaskAction a) async {
    await widget.sync.patchActionOf(p, a);
    _changed();
  }

  Future<void> _patchTask(List<String> keys) async {
    await widget.sync.patchTaskFields(p.id, t, keys);
    _changed();
  }

  // ── Lectures ────────────────────────────────────────────────────────────────

  Session? get _running {
    final l = widget.logic;
    if (l == null) return null;
    return l.state.sessions.where((s) => s.endAt == null && !s.deleted && s.taskId == t.id).firstOrNull;
  }

  Map<String, int> get _spent => widget.logic == null ? const {} : spentByAction(widget.logic!.state.sessions);

  Activity? _activityFor(TaskAction a) {
    final id = a.linkedActivityId ?? p.linkedActivityId;
    if (id == null) return null;
    return widget.activities.where((x) => x.id == id).firstOrNull;
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Émoji de tête du titre (rôle de séance 📝 / 🎯 / ✅, ou tout autre pictogramme
  /// posé par Claude) : il passe dans la pastille, le titre reste du texte.
  String get _roleEmoji {
    final m = _leadingEmoji.firstMatch(t.title);
    if (m != null) return m.group(1)!;
    return isPrepTask(t) ? '📝' : (isMilestoneTask(t) ? '🎯' : (isClosureTask(t) ? '✅' : ''));
  }

  String get _cleanTitle => stripLeadingEmoji(t.title);

  TaskAction? get _next => t.actions.where((a) => !a.done).firstOrNull;

  // ── Gestes ──────────────────────────────────────────────────────────────────

  void _start(TaskAction a) {
    final act = _activityFor(a);
    final cb = widget.onStartTimer;
    if (act == null || cb == null) {
      _openAction(a);
      return;
    }
    Navigator.pop(context);
    cb(act, p, t);
  }

  Future<void> _toggleActionDone(TaskAction a, bool v) async {
    if (v && !await confirmDone(context, title: a.title)) return;
    setActionDone(a, v);
    await _patchAction(a);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text(v ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Annuler', onPressed: () => _toggleActionDone(a, !v)),
      ));
  }

  Future<void> _toggleTaskDone() async {
    final done = t.status == 'done';
    t.status = done ? 'pending' : 'done';
    await _patchTask(['status']);
  }

  Future<void> _addAction() async {
    final ctrl = TextEditingController();
    var picked = <String>[];
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Nouvelle action'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Verbe + objet, ≤ 8 mots'),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
            },
          ),
          const SizedBox(height: 12),
          ContextPicker(values: picked, sync: widget.sync, onValuesChanged: (l) => picked = l),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Ajouter')),
        ],
      ),
    );
    ctrl.dispose();
    if (title == null) return;
    t.actions.add(TaskAction(
      title: title,
      context: picked.isEmpty ? null : picked.first,
      contexts: List.of(picked),
      estimatedMin: defaultEstimateFor(title, contexts: picked),
    ));
    await _saveTasks();
  }

  Future<void> _organize(TaskAction a) async {
    final open = t.actions.where((x) => !x.done).toList();
    final i = open.indexOf(a);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ),
          if (i > 0) ListTile(leading: const Icon(Icons.arrow_upward_rounded), title: const Text('Monter'), onTap: () => Navigator.pop(ctx, 'up')),
          if (i >= 0 && i < open.length - 1) ListTile(leading: const Icon(Icons.arrow_downward_rounded), title: const Text('Descendre'), onTap: () => Navigator.pop(ctx, 'down')),
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Déplacer vers une autre tâche'), onTap: () => Navigator.pop(ctx, 'move')),
          ListTile(leading: const Icon(Icons.account_tree_outlined), title: const Text('Promouvoir en sous-projet'), onTap: () => Navigator.pop(ctx, 'promote')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('Supprimer l\'action', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    switch (choice) {
      case 'up':
      case 'down':
        final all = t.actions;
        final from = all.indexOf(a);
        final other = open[choice == 'up' ? i - 1 : i + 1];
        final to = all.indexOf(other);
        all.removeAt(from);
        all.insert(to, a);
        await _saveTasks();
      case 'move':
        await _moveAction(a);
      case 'promote':
        await _promoteAction(a);
      case 'delete':
        await _deleteAction(a);
    }
  }

  Future<void> _deleteAction(TaskAction a) async {
    t.actions.remove(a);
    await _saveTasks();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text('Action supprimée : ${a.title}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
            label: 'Annuler',
            onPressed: () {
              t.actions.add(a);
              _saveTasks();
            }),
      ));
  }

  Future<Project?> _pickProject(String title, {String? excludeId}) async {
    final projects = await widget.sync.fetchProjects();
    if (!mounted) return null;
    final candidates = projects.where((x) => x.id != excludeId && x.status != 'archived').toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun autre projet disponible.')));
      return null;
    }
    return showModalBottomSheet<Project>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final x in candidates) ListTile(title: Text(x.title), onTap: () => Navigator.pop(ctx, x)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<ProjectTask?> _pickTask(Project project, {String? excludeTaskId}) async {
    final tasks = project.tasks.where((x) => x.id != excludeTaskId && x.id != 'gtd-flow').toList();
    if (!mounted) return null;
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('« ${project.title} » n\'a aucune autre tâche.')));
      return null;
    }
    return showModalBottomSheet<ProjectTask>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Tâche cible — ${project.title}', style: const TextStyle(fontWeight: FontWeight.bold))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final x in tasks) ListTile(title: Text(x.title), onTap: () => Navigator.pop(ctx, x)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _moveAction(TaskAction a) async {
    final target = await _pickProject('Déplacer l\'action vers…');
    if (target == null) return;
    final targetTask = await _pickTask(target, excludeTaskId: target.id == p.id ? t.id : null);
    if (targetTask == null) return;
    await widget.sync.moveActionToTask(fromProjectId: p.id, fromTaskId: t.id, toProjectId: target.id, toTaskId: targetTask.id, actionId: a.id);
    t.actions.removeWhere((x) => x.id == a.id);
    if (target.id == p.id) p.tasks.where((x) => x.id == targetTask.id).firstOrNull?.actions.add(a);
    _changed();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action déplacée vers « ${targetTask.title} ».')));
  }

  Future<void> _promoteAction(TaskAction a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promouvoir en sous-projet'),
        content: Text('Créer un sous-projet « ${a.title} » sous « ${p.title} » ? L\'action sera retirée de cette tâche.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true) return;
    final child = await widget.sync.promoteActionToSubproject(parentProjectId: p.id, taskId: t.id, actionId: a.id);
    t.actions.removeWhere((x) => x.id == a.id);
    _changed();
    if (!mounted || child == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sous-projet « ${child.title} » créé.')));
  }

  Future<void> _moveTask() async {
    final target = await _pickProject('Déplacer la tâche vers…', excludeId: p.id);
    if (target == null) return;
    await widget.sync.moveTaskToProject(p.id, target.id, t.id);
    p.tasks.removeWhere((x) => x.id == t.id);
    widget.onChanged?.call();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tâche déplacée vers « ${target.title} ».')));
  }

  Future<void> _deleteTask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la tâche ?'),
        content: Text('« ${_cleanTitle} » et ses ${t.actions.length} action${t.actions.length > 1 ? 's' : ''} seront supprimées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    p.tasks.removeWhere((x) => x.id == t.id);
    await widget.sync.saveProjectTasks(p.id, p.tasks);
    widget.onChanged?.call();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tâche supprimée')));
  }

  Future<void> _editTask() async {
    final titleCtrl = TextEditingController(text: _cleanTitle);
    final descCtrl = TextEditingController(text: t.description ?? '');
    var start = t.startDate;
    DateTime? end = t.endDate;
    var phaseId = t.phaseId;
    var milestone = t.isMilestone;
    final phases = p.phases;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Modifier la tâche', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: titleCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: descCtrl, minLines: 2, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_outlined, size: 20),
                title: const Text('Début'),
                trailing: Text(shortDateFr(start)),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setSB(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined, size: 20),
                title: const Text('Échéance'),
                trailing: Text(end == null ? 'Aucune' : shortDateFr(end!)),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: end ?? start, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setSB(() => end = d);
                },
              ),
              if (phases.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: DropdownButtonFormField<String?>(
                    value: phases.any((x) => x.id == phaseId) ? phaseId : null,
                    decoration: const InputDecoration(labelText: 'Phase', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Aucune phase')),
                      for (final x in phases) DropdownMenuItem(value: x.id, child: Text(x.label)),
                    ],
                    onChanged: (v) => setSB(() => phaseId = v),
                  ),
                ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Jalon'), value: milestone, onChanged: (v) => setSB(() => milestone = v)),
              Row(children: [
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (saved == true) {
      final newTitle = titleCtrl.text.trim();
      if (newTitle.isNotEmpty) t.title = _roleEmoji.isEmpty ? newTitle : '$_roleEmoji ${stripLeadingEmoji(newTitle)}';
      final d = descCtrl.text.trim();
      t.description = d.isEmpty ? null : d;
      t.startDate = start;
      t.endDate = end;
      t.phaseId = phaseId;
      t.groupLabel = phases.where((x) => x.id == phaseId).firstOrNull?.label;
      t.isMilestone = milestone;
      await _saveTasks();
    }
    titleCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> _openDocs() async {
    final taskDocs = await widget.sync.fetchDocuments(taskId: t.id);
    final projectDocs = await widget.sync.fetchDocuments(projectId: p.id);
    final seen = <String>{};
    final docs = [
      for (final d in [...taskDocs, ...projectDocs])
        if (seen.add(d['id'] as String? ?? '')) d,
    ];
    if (!mounted) return;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun document lié à cette tâche.')));
      return;
    }
    await showDocList(context, docs);
  }

  Future<void> _more() async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.today_outlined),
              title: Text(t.todayFlag ? 'Retirer du programme du jour' : 'Au programme aujourd\'hui'),
              subtitle: const Text('un bloc sur la prochaine action'),
              onTap: () => Navigator.pop(ctx, 'today')),
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Déplacer vers un autre projet'), subtitle: const Text('la tâche et ses actions'), onTap: () => Navigator.pop(ctx, 'move')),
          if (t.endDate != null) ListTile(leading: const Icon(Icons.event_repeat_outlined), title: const Text('Repousser l\'échéance'), onTap: () => Navigator.pop(ctx, 'push')),
          ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Documents'), onTap: () => Navigator.pop(ctx, 'docs')),
          ListTile(leading: Icon(Icons.delete_outline, color: cs.error), title: Text('Supprimer la tâche', style: TextStyle(color: cs.error)), subtitle: const Text('et ses actions · confirmation'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    switch (choice) {
      case 'today':
        await toggleTaskTodayAndSchedule(context, widget.sync, p, t);
        _changed();
      case 'move':
        await _moveTask();
      case 'push':
        await _pushDeadline();
      case 'docs':
        await _openDocs();
      case 'delete':
        await _deleteTask();
    }
  }

  Future<void> _pushDeadline() async {
    final cur = t.endDate;
    if (cur == null) return;
    final ref = DateTime(cur.year, cur.month, cur.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: ref.add(const Duration(days: 7)),
      firstDate: ref.add(const Duration(days: 1)),
      lastDate: DateTime(2100),
      helpText: 'Repousser l\'échéance au…',
    );
    if (picked == null || !mounted) return;
    t.endDate = DateTime(picked.year, picked.month, picked.day);
    await _patchTask(['endDate']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Échéance repoussée.')));
  }

  // ── Fiche d'action ──────────────────────────────────────────────────────────

  Future<void> _openAction(TaskAction a) async {
    await showActionFicheOfTask(
      context,
      project: p,
      task: t,
      action: a,
      activities: widget.activities,
      sync: widget.sync,
      logic: widget.logic,
      onStart: widget.onStartTimer == null ? null : () => _start(a),
      onOrganize: () => _organize(a),
      onChanged: _changed,
    );
    if (mounted) setState(() {});
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = _today;
    final running = _running;
    final open = t.actions.where((a) => !a.done).toList();
    final done = t.actions.where((a) => a.done).toList();
    final isDone = t.status == 'done';
    final late = !isDone && t.endDate != null && t.endDate!.isBefore(today);
    final lateDays = late ? today.difference(DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day)).inDays : 0;
    final spent = _spent;
    final spentMin = t.actions.fold<int>(0, (s, a) => s + (spent[a.id] ?? 0));
    final phase = p.phases.where((x) => x.id == t.phaseId).firstOrNull?.label ?? t.groupLabel;
    final (chip, chipColor) = isDone
        ? ('faite', kPalierGreen)
        : running != null
            ? ('chrono en cours', cs.primary)
            : late
                ? ('en retard · $lateDays j', kPalierCoral)
                : t.todayFlag
                    ? ('au programme', cs.primary)
                    : ('à faire', kPalierMuted);
    final root = widget.allProjects.isEmpty ? null : rootProjectOf(p, widget.allProjects);
    final session = t.interventionId == null ? null : p.interventions.where((i) => i.id == t.interventionId).firstOrNull;
    final kpi = <String>[
      p.title,
      if (root != null && root.id != p.id) 'Pour ${root.title}',
      if (session != null) 'séance du ${shortDateFr(session.date, today: today)}' else if (phase != null && phase.isNotEmpty) phase,
      '${shortDateFr(t.startDate)}${t.endDate != null ? ' → ${shortDateFr(t.endDate!)}' : ''}',
      if (t.actions.isNotEmpty) '${done.length} / ${t.actions.length} action${t.actions.length > 1 ? 's' : ''}',
      if (spentMin > 0) '⏱ ${fmtMin(spentMin)} passées',
    ].join(' · ');
    final next = _next;
    final nextActivity = next == null ? null : _activityFor(next);

    final String primaryLabel;
    final IconData primaryIcon;
    final VoidCallback? onPrimary;
    if (isDone) {
      primaryLabel = 'Rouvrir la tâche';
      primaryIcon = Icons.unarchive_outlined;
      onPrimary = _toggleTaskDone;
    } else if (running != null && widget.logic != null) {
      primaryLabel = 'Arrêter le chrono';
      primaryIcon = Icons.stop_rounded;
      onPrimary = () => widget.logic!.stopActive();
    } else if (next == null) {
      primaryLabel = 'Ajouter une action';
      primaryIcon = Icons.add;
      onPrimary = _addAction;
    } else if (nextActivity != null && widget.onStartTimer != null) {
      primaryLabel = 'Lancer · ${next.title}';
      primaryIcon = Icons.play_arrow_rounded;
      onPrimary = () => _start(next);
    } else {
      primaryLabel = 'Ouvrir · ${next.title}';
      primaryIcon = Icons.arrow_forward_rounded;
      onPrimary = () => _openAction(next);
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        FicheHeader(
          title: _cleanTitle,
          chip: chip,
          chipColor: chipColor,
          kpi: kpi,
          leading: _roleEmoji.isEmpty
              ? null
              : Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(10)),
                  child: Text(_roleEmoji, style: const TextStyle(fontSize: 17)),
                ),
        ),
        // Mur des projets (lot 3) : la rangée de briques de la tâche, une par
        // action, remplie par ses étapes ; trait = actions échues à ce jour.
        if (t.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ProgressBricks(
                row: taskBricks(t, today, runningActionIds: {if (running?.actionId != null) running!.actionId!}), height: 12),
          ),
        FicheTitle('ACTIONS',
            trailing: open.isEmpty
                ? (t.actions.isEmpty ? null : FicheDelta('toutes faites', color: kPalierGreen))
                : FicheDelta(
                    '${open.length} à faire${running != null ? ' · 1 en cours' : ''}',
                    color: open.any((a) => _isLate(a, today)) ? kPalierCoral : cs.onSurface.withValues(alpha: .6))),
        if (t.actions.isEmpty)
          const FicheNote('Aucune action : ajoute la première. Une action = verbe + objet, ses étapes se cochent dans sa fiche.')
        else
          for (final a in open) _actionRow(cs, a, today, running, spent),
        if (done.isNotEmpty) ...[
          ListSectionTitle('FAITES · ${done.length}', onAction: () => setState(() => _showDone = !_showDone), expanded: _showDone),
          if (_showDone)
            for (final a in done) _actionRow(cs, a, today, running, spent),
        ],
        ListSectionTitle('DÉTAIL', onAction: () => setState(() => _detailOpen = !_detailOpen), expanded: _detailOpen),
        if (_detailOpen) ..._detail(cs, phase, session),
        FicheActions(
          primaryLabel: primaryLabel,
          primaryIcon: primaryIcon,
          onPrimary: onPrimary,
          secondary: [
            if (!isDone) (label: 'Marquer faite', onTap: _toggleTaskDone),
            (label: '+ Action', onTap: _addAction),
            (label: 'Modifier', onTap: _editTask),
            (label: '⋯', onTap: _more),
          ],
        ),
        if (!isDone && next != null && nextActivity == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              widget.activities.isEmpty ? '' : 'Pas d\'activité liée : lie l\'action à une activité (dans sa fiche) pour lancer un chrono ciblé.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .5)),
            ),
          ),
      ],
    );
  }

  bool _isLate(TaskAction a, DateTime today) {
    final due = effectiveDueDate(a, t);
    return due != null && DateTime(due.year, due.month, due.day).isBefore(today);
  }

  Widget _actionRow(ColorScheme cs, TaskAction a, DateTime today, Session? running, Map<String, int> spent) {
    final isRunning = running != null && running.actionId == a.id;
    final late = !a.done && _isLate(a, today);
    final due = effectiveDueDate(a, t);
    final sp = spentLabel(spent[a.id] ?? 0, a.estimatedMin, fmtMin);
    final act = _activityFor(a);
    final sub = <String>[
      if (a.allContexts.isNotEmpty) (a.allContexts.toList()..sort()).join(' '),
      if (a.checklist.isNotEmpty) '${a.checklistDone} / ${a.checklistTotal} étapes',
      if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
      if (sp != null) sp.label,
      if (!a.done && due != null && a.dueDate != null) '⚑ ${actionDueLabel(due, today)}',
      if (a.done) 'faite${a.doneAt != null ? ' ${shortDateFr(a.doneAt!, today: today)}' : ''}${(spent[a.id] ?? 0) > 0 ? ' · ${fmtMin(spent[a.id]!)}' : ''}',
    ].join(' · ');
    final chipLabel = a.done ? null : (isRunning ? 'en cours' : (late ? 'en retard' : 'à faire'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _toggleActionDone(a, !a.done),
          child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked, size: 26, color: a.done ? kPalierGreen : cs.onSurface.withValues(alpha: .4)),
        ),
        title: a.title,
        sub: sub.isEmpty ? null : sub,
        bar: a.checklist.isEmpty ? null : (done: a.checklistDone, total: a.checklistTotal, expected: a.checklistTotal),
        pct: a.done ? 100 : (a.checklist.isEmpty ? (late ? 0 : 60) : (a.checklistDone * 100 ~/ a.checklistTotal)),
        chip: chipLabel,
        muted: a.done,
        trailing: a.done || act == null || widget.onStartTimer == null
            ? null
            : IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: isRunning ? 'Chrono en cours' : 'Lancer le chrono',
                onPressed: isRunning ? null : () => _start(a),
                icon: Icon(isRunning ? Icons.timer : Icons.play_circle_outline, color: cs.primary),
              ),
        onTap: () => _openAction(a),
        onLongPress: a.done ? null : () => _organize(a),
      ),
    );
  }

  List<Widget> _detail(ColorScheme cs, String? phase, ProjectIntervention? session) {
    final text3 = cs.onSurface.withValues(alpha: .55);
    final linked = widget.activities.where((x) => x.id == p.linkedActivityId).firstOrNull;
    Widget row(IconData icon, String title, String? sub, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: cs.onSurface.withValues(alpha: .7)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (sub != null && sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11.5, height: 1.3, color: text3)),
                ]),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withValues(alpha: .35)),
            ]),
          ),
        );
    final desc = (t.description ?? '').trim();
    return [
      row(Icons.notes_rounded, desc.isEmpty ? 'Pas de description' : 'Description', desc.isEmpty ? '+ ajouter' : desc, onTap: _editTask),
      row(Icons.calendar_month_outlined, '${shortDateFr(t.startDate)} → ${t.endDate == null ? '—' : shortDateFr(t.endDate!)}',
          [if (phase != null && phase.isNotEmpty) 'phase $phase', if (t.estimatedMin != null) 'estimation ${fmtMin(t.estimatedMin!)}', if (t.isMilestone) 'jalon'].join(' · '),
          onTap: _editTask),
      if (t.interventionRole != null) ...[
        row(Icons.event_rounded, isPrepTask(t) ? 'Préparation de la séance' : isMilestoneTask(t) ? 'La séance' : 'Clôture de la séance',
            session == null ? 'rôle ${t.interventionRole}' : 'séance du ${shortDateFr(session.date)}${session.place != null ? ' · ${session.place}' : ''}'),
        if (isClosureTask(t))
          row(Icons.rate_review_outlined, 'Bilan de la séance',
              (session?.debriefText ?? '').trim().isEmpty ? 'à remplir · nourrit la prépa de la séance suivante' : session!.debriefText!.trim()),
      ],
      row(Icons.timer_outlined, linked == null ? 'Aucune activité liée au projet' : linked.name, linked == null ? 'le chrono d\'une action passe par son activité liée' : 'activité liée du projet · le chrono de la tâche y compte'),
      row(Icons.description_outlined, _docCount == null ? 'Documents' : (_docCount == 0 ? 'Aucun document' : '$_docCount document${_docCount! > 1 ? 's' : ''}'), 'programmes, briefs, livrables', onTap: _openDocs),
    ];
  }
}

// ── Fiche d'action d'une tâche ────────────────────────────────────────────────

/// Fiche d'une ACTION de tâche, ouverte depuis la fiche de tâche : en-tête,
/// ÉTAPES (`StepsSection`), DÉTAIL (note), ÉCHÉANCE propre, ACTIVITÉ LIÉE,
/// gestes (lancer / faite / organiser). Même modèle que la fiche d'action de
/// l'onglet Actions, sans dépendre de son état.
Future<void> showActionFicheOfTask(
  BuildContext context, {
  required Project project,
  required ProjectTask task,
  required TaskAction action,
  required List<Activity> activities,
  required FirestoreSync sync,
  AppLogic? logic,
  VoidCallback? onStart,
  VoidCallback? onOrganize,
  VoidCallback? onChanged,
}) {
  return showFiche<void>(
    context,
    builder: (ctx, scroll) => _ActionFiche(
      project: project,
      task: task,
      action: action,
      activities: activities,
      sync: sync,
      logic: logic,
      onStart: onStart,
      onOrganize: onOrganize,
      onChanged: onChanged,
      scroll: scroll,
    ),
  );
}

class _ActionFiche extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final TaskAction action;
  final List<Activity> activities;
  final FirestoreSync sync;
  final AppLogic? logic;
  final VoidCallback? onStart;
  final VoidCallback? onOrganize;
  final VoidCallback? onChanged;
  final ScrollController scroll;
  const _ActionFiche({
    required this.project,
    required this.task,
    required this.action,
    required this.activities,
    required this.sync,
    required this.logic,
    required this.onStart,
    required this.onOrganize,
    required this.onChanged,
    required this.scroll,
  });

  @override
  State<_ActionFiche> createState() => _ActionFicheState();
}

class _ActionFicheState extends State<_ActionFiche> {
  TaskAction get a => widget.action;

  Future<void> _persist() async {
    await widget.sync.patchActionOf(widget.project, a);
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  void _toggleStep(ChecklistItem c, bool v) {
    final changed = setChecklistItem(a, c.id, v);
    setState(() {});
    _persist();
    if (changed && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}')));
    }
  }

  Future<void> _edit() async {
    final titleCtrl = TextEditingController(text: a.title);
    final noteCtrl = TextEditingController(text: a.note ?? '');
    final estCtrl = TextEditingController(text: a.estimatedMin?.toString() ?? '');
    var picked = a.allContexts.toList();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Modifier l\'action'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: titleCtrl, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Titre')),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, minLines: 2, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Note (le détail, les consignes)')),
          const SizedBox(height: 10),
          TextField(controller: estCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Estimation (min)')),
          const SizedBox(height: 12),
          ContextPicker(values: picked, sync: widget.sync, onValuesChanged: (l) => picked = l),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (saved == true) {
      final title = titleCtrl.text.trim();
      if (title.isNotEmpty) a.title = title;
      final note = noteCtrl.text.trim();
      a.note = note.isEmpty ? null : note;
      a.estimatedMin = int.tryParse(estCtrl.text.trim());
      a.contexts = List.of(picked);
      a.context = picked.isEmpty ? null : picked.first;
      await _persist();
    }
    titleCtrl.dispose();
    noteCtrl.dispose();
    estCtrl.dispose();
  }

  Future<void> _pickFocus() async {
    final now = DateTime.now();
    final pick = await pickFocusDay(context, current: a.focusDate, today: DateTime(now.year, now.month, now.day));
    if (pick == null) return;
    a.focusDate = switch (pick) { FocusDay(:final day) => day, FocusClear() => null };
    await _persist();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.wb_sunny_outlined), title: const Text('Demain'), onTap: () => Navigator.pop(ctx, 'tomorrow')),
          ListTile(leading: const Icon(Icons.weekend_outlined), title: const Text('Fin de semaine'), onTap: () => Navigator.pop(ctx, 'week')),
          ListTile(leading: const Icon(Icons.event_outlined), title: const Text('Choisir une date…'), onTap: () => Navigator.pop(ctx, 'date')),
          if (a.dueDate != null) ListTile(leading: const Icon(Icons.close), title: const Text('Retirer l\'échéance propre'), onTap: () => Navigator.pop(ctx, 'clear')),
        ]),
      ),
    );
    if (choice == null) return;
    DateTime? d;
    switch (choice) {
      case 'tomorrow':
        d = today.add(const Duration(days: 1));
      case 'week':
        d = today.add(Duration(days: 7 - today.weekday));
      case 'date':
        if (!mounted) return;
        d = await showDatePicker(context: context, initialDate: a.dueDate ?? today, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (d == null) return;
      case 'clear':
        d = null;
    }
    a.dueDate = d == null ? null : DateTime(d.year, d.month, d.day);
    await _persist();
  }

  Future<void> _linkActivity() async {
    final list = widget.activities.where((x) => !x.isHabit && !x.deleted).toList();
    if (list.isEmpty) return;
    final picked = await showActivityPicker(context,
        activities: list,
        domains: widget.logic?.state.activeDomains ?? const [],
        title: 'Activité liée',
        selectedId: a.linkedActivityId,
        preferDomainId: widget.project.domainId,
        trailingExtras: [if (a.linkedActivityId != null) const ActivityPickerExtra('', 'Délier', icon: Icons.link_off)]);
    if (picked == null) return;
    a.linkedActivityId = picked.isEmpty ? null : picked;
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = effectiveDueDate(a, widget.task);
    final late = !a.done && due != null && DateTime(due.year, due.month, due.day).isBefore(today);
    final running = widget.logic?.state.sessions.where((s) => s.endAt == null && !s.deleted && s.actionId == a.id).firstOrNull;
    final spent = widget.logic == null ? 0 : (spentByAction(widget.logic!.state.sessions)[a.id] ?? 0);
    final sp = spentLabel(spent, a.estimatedMin, fmtMin);
    final linked = widget.activities.where((x) => x.id == (a.linkedActivityId ?? widget.project.linkedActivityId)).firstOrNull;
    final kpi = <String>[
      '${widget.project.title} › ${stripLeadingEmoji(widget.task.title)}',
      if (a.allContexts.isNotEmpty) (a.allContexts.toList()..sort()).join(' '),
      if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
      if (sp != null) sp.label,
    ].join(' · ');
    final (chip, chipColor) = a.done
        ? ('faite', kPalierGreen)
        : running != null
            ? ('chrono en cours', cs.primary)
            : late
                ? ('en retard', kPalierCoral)
                : due != null
                    ? (actionDueLabel(due, today), palierColor(due.difference(today).inDays <= 2 ? 70 : 100))
                    : ('à faire', kPalierMuted);
    final text3 = cs.onSurface.withValues(alpha: .55);
    return ListView(
      controller: widget.scroll,
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      children: [
        FicheHeader(
          title: a.title,
          chip: chip,
          chipColor: chipColor,
          kpi: kpi,
          leading: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              if (!a.done && !await confirmDone(context, title: a.title)) return;
              setActionDone(a, !a.done);
              _persist();
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked, size: 26, color: a.done ? kPalierGreen : cs.onSurface.withValues(alpha: .4)),
            ),
          ),
        ),
        FicheTitle('ÉTAPES', trailing: a.checklist.isEmpty ? null : FicheDelta('${a.checklistDone} / ${a.checklistTotal}', color: kPalierGreen)),
        StepsSection(
          key: ValueKey('task_fiche_steps_${a.id}'),
          action: a,
          leftInset: 0,
          onToggle: _toggleStep,
          onAdd: (title) {
            if (addChecklistItem(a, title) == null) return;
            _persist();
          },
          onRemove: (c) {
            removeChecklistItem(a, c.id);
            _persist();
          },
          onRename: (c, title) {
            if (!renameChecklistItem(a, c.id, title)) return;
            _persist();
          },
        ),
        const FicheTitle('DÉTAIL'),
        if ((a.note ?? '').trim().isEmpty)
          FicheStep(title: 'Pas de note', detail: 'le détail, les consignes, les codes', onTap: _edit)
        else
          FicheStep(title: a.note!.trim(), onTap: _edit),
        FicheTitle('JOUR VISÉ', trailing: a.focusDate != null ? FicheDelta(isStaleFocus(a, today) ? 'à re-viser' : 'intention', color: isStaleFocus(a, today) ? kPalierAmber : kPalierMuted) : null),
        FicheStep(
          title: a.focusDate == null ? 'Pas de jour visé' : focusLabel(a.focusDate!, today),
          detail: a.focusDate == null ? 'le jour où tu veux l\'avoir sous la main · ni créneau, ni retard' : 'une intention, pas un créneau',
          onTap: _pickFocus,
          trailing: Icon(Icons.wb_sunny_outlined, size: 18, color: text3),
        ),
        FicheTitle('ÉCHÉANCE', trailing: a.dueDate != null ? const FicheDelta('⚑ propre', color: kPalierMuted) : null),
        FicheStep(
          title: due == null ? 'Aucune échéance' : actionDueLabel(due, today),
          detail: a.dueDate != null ? 'échéance propre à l\'action' : (widget.task.endDate != null ? 'celle de la tâche · ${shortDateFr(widget.task.endDate!, today: today)}' : 'ni sur l\'action ni sur la tâche'),
          current: late,
          onTap: _pickDue,
          trailing: Icon(Icons.edit_calendar_outlined, size: 18, color: text3),
        ),
        const FicheTitle('ACTIVITÉ LIÉE'),
        FicheStep(
          title: linked == null ? 'Aucune' : linked.name,
          detail: linked == null
              ? 'lie une activité-temps : le chrono y sera ciblé'
              : (a.linkedActivityId != null ? 'lien propre à l\'action' : 'héritée du projet'),
          onTap: _linkActivity,
          trailing: Icon(Icons.link, size: 18, color: text3),
        ),
        FicheActions(
          primaryLabel: a.done
              ? 'Rouvrir'
              : (widget.onStart != null && linked != null ? 'Lancer le chrono' : 'Marquer faite'),
          primaryIcon: a.done ? Icons.undo_rounded : (widget.onStart != null && linked != null ? Icons.play_arrow_rounded : Icons.check_rounded),
          onPrimary: () async {
            if (a.done) {
              setActionDone(a, false);
              _persist();
            } else if (widget.onStart != null && linked != null) {
              Navigator.pop(context);
              widget.onStart!();
            } else {
              if (!await confirmDone(context, title: a.title)) return;
              setActionDone(a, true);
              _persist();
              if (mounted) Navigator.pop(context);
            }
          },
          secondary: [
            if (!a.done && widget.onStart != null && linked != null) (label: 'Marquer faite', onTap: () async {
              if (!await confirmDone(context, title: a.title)) return;
              setActionDone(a, true);
              _persist();
              if (mounted) Navigator.pop(context);
            }),
            (label: 'Modifier', onTap: _edit),
            if (widget.onOrganize != null)
              (label: 'Organiser', onTap: () {
                Navigator.pop(context);
                widget.onOrganize!();
              }),
          ],
        ),
      ],
    );
  }
}
