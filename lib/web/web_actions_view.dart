import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';

/// Onglet « Actions » de l'app web — le pendant de l'onglet mobile (pivot
/// GTD) : les actions en attente PAR PROJET, filtrées par les contextes
/// « je suis », process au clic (multi-contextes), ajout rapide. Le contenu
/// Gantt est INTÉGRÉ mais en second plan : un bouton par projet ouvre le
/// Gantt complet — la priorité reste au GTD.
class WebActionsView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<Activity> activities;
  final FirestoreSync sync;
  final VoidCallback onRefresh;

  const WebActionsView({
    super.key,
    required this.projects,
    required this.domains,
    required this.activities,
    required this.sync,
    required this.onRefresh,
  });

  @override
  State<WebActionsView> createState() => _WebActionsViewState();
}

class _WebActionsViewState extends State<WebActionsView> {
  // Contextes actifs — locaux à la session web (comme nowContexts mobile,
  // préférence par appareil, rien en base).
  final Set<String> _nowContexts = {};

  static const _flowTaskId = 'gtd-flow'; // même réceptacle que le mobile

  List<Activity> get _activeActivities =>
      widget.activities.where((a) => !a.deleted).toList();

  // ── Dérivation ─────────────────────────────────────────────────────────────

  List<({Project project, List<(ProjectTask, TaskAction)> entries})>
      _projectGroups() {
    final out =
        <({Project project, List<(ProjectTask, TaskAction)> entries})>[];
    for (final p in widget.projects) {
      if (p.status != 'active' || p.paused) continue;
      final entries = <(ProjectTask, TaskAction)>[];
      final tasks = p.tasks
          .where((t) =>
              !t.isMilestone && t.status != 'done' && t.status != 'skipped')
          .toList()
        ..sort((a, b) {
          final ae = a.endDate, be = b.endDate;
          if (ae == null && be == null) return 0;
          if (ae == null) return 1;
          if (be == null) return -1;
          return ae.compareTo(be);
        });
      for (final t in tasks) {
        for (final a in t.actions.where((a) => !a.done)) {
          entries.add((t, a));
        }
      }
      out.add((project: p, entries: entries));
    }
    return out;
  }

  List<({Activity activity, List<TaskAction> actions})> _activityGroups() {
    return [
      for (final act in _activeActivities)
        if (act.ownActions.any((a) => !a.done))
          (
            activity: act,
            actions: act.ownActions.where((a) => !a.done).toList()
          ),
    ];
  }

  bool _visible(TaskAction a) =>
      _nowContexts.isEmpty ||
      a.allContexts.any(_nowContexts.contains);

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> _toggleProjectAction(Project p, TaskAction a, bool done) async {
    a.done = done;
    a.doneAt = done ? DateTime.now() : null;
    unawaited(widget.sync.saveProjectTasks(p.id, p.tasks));
    setState(() {});
  }

  Future<void> _toggleOwnAction(Activity act, TaskAction a, bool done) async {
    a.done = done;
    a.doneAt = done ? DateTime.now() : null;
    unawaited(widget.sync.updateOwnActions(act.id, act.ownActions));
    setState(() {});
  }

  Future<void> _togglePause(Project p) async {
    p.paused = !p.paused;
    unawaited(widget.sync.saveProject(p));
    setState(() {});
  }

  /// Édition COMPLÈTE d'une action (CRUD web) : titre + multi-contextes +
  /// suppression — actions Gantt et actions simples, même dialog.
  Future<void> _editAction(TaskAction a,
      {Project? project, ProjectTask? task, Activity? activity}) async {
    final available = await widget.sync.fetchAvailableContexts();
    if (!mounted) return;
    final selected = Set<String>.of(a.allContexts);
    final all = [
      ...available,
      ...selected.where((c) => !available.contains(c)),
    ];
    final titleCtrl = TextEditingController(text: a.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Action'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Titre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Text('Où / avec quoi cette action est-elle réalisable ?',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(.55))),
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            icon: Icon(Icons.delete_outline,
                size: 16, color: Theme.of(ctx).colorScheme.error),
            label: Text('Supprimer',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    final newTitle = titleCtrl.text.trim();
    titleCtrl.dispose();
    if (result == null) return;
    if (result == 'delete') {
      if (task != null) {
        task.actions.remove(a);
      } else if (activity != null) {
        activity.ownActions.remove(a);
      }
    } else {
      if (newTitle.isNotEmpty) a.title = newTitle;
      a.setContexts(selected.toList());
    }
    if (project != null) {
      unawaited(widget.sync.saveProjectTasks(project.id, project.tasks));
    } else if (activity != null) {
      unawaited(widget.sync.updateOwnActions(activity.id, activity.ownActions));
    }
    setState(() {});
  }

  /// Crée une action SIMPLE (ownAction) sur une activité — CRUD web complet.
  Future<void> _addOwnAction() async {
    final timeActivities =
        _activeActivities.where((a) => a.type == 'time').toList();
    if (timeActivities.isEmpty) return;
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
                ContextPicker(
                  values: picked,
                  sync: widget.sync,
                  onValuesChanged: (list) => picked = list,
                ),
                const SizedBox(height: 12),
                Text('SUR L\'ACTIVITÉ',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in timeActivities)
                      ChoiceChip(
                        selected: activityId == a.id,
                        onSelected: (_) =>
                            setLocal(() => activityId = a.id),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
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
    if (saved != true || title.isEmpty) return;
    unawaited(widget.sync
        .addOwnActionToActivity(activityId, title, contexts: picked));
    final act =
        widget.activities.firstWhereOrNull((a) => a.id == activityId);
    act?.ownActions.add(TaskAction(
      title: title,
      linkedActivityId: activityId,
      context: picked.isEmpty ? null : picked.first,
      contexts: List.of(picked),
    ));
    setState(() {});
  }

  /// Ajout rapide d'une action au projet — même réceptacle « Au fil de
  /// l'eau » (gtd-flow) que le mobile.
  Future<void> _quickAddAction(Project p) async {
    final ctrl = TextEditingController();
    var picked = <String>[];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Prochaine action'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withOpacity(.55))),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'La prochaine action concrète…'),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) Navigator.pop(ctx, true);
                },
              ),
              const SizedBox(height: 12),
              ContextPicker(
                values: picked,
                sync: widget.sync,
                onValuesChanged: (list) => picked = list,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, true);
              },
              child: const Text('Ajouter')),
        ],
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (saved != true || title.isEmpty) return;
    var flow = p.tasks.firstWhereOrNull((t) => t.id == _flowTaskId);
    if (flow == null) {
      flow = ProjectTask(
          id: _flowTaskId, title: 'Au fil de l\'eau', startDate: DateTime.now());
      p.tasks.add(flow);
    } else if (flow.status != 'pending') {
      flow.status = 'pending';
    }
    flow.actions.add(TaskAction(
      title: title,
      context: picked.isEmpty ? null : picked.first,
      contexts: List.of(picked),
    ));
    unawaited(widget.sync.saveProjectTasks(p.id, p.tasks));
    setState(() {});
  }

  void _openGantt(Project p, {String? targetTaskId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GanttScreen(
            project: p, targetTaskId: targetTaskId, domains: widget.domains),
      ),
    ).then((_) => widget.onRefresh());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _projectGroups();
    final aGroups = _activityGroups();
    final contexts = <String>{
      for (final g in groups)
        for (final e in g.entries) ...e.$2.allContexts,
      for (final g in aGroups)
        for (final a in g.actions) ...a.allContexts,
    }.toList()
      ..sort();
    _nowContexts.removeWhere((c) => !contexts.contains(c));

    final paused = widget.projects
        .where((p) => p.status == 'active' && p.paused)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── « Je suis… » : les contextes actifs filtrent tout ─────
                if (contexts.isNotEmpty) ...[
                  Row(children: [
                    Icon(Icons.place_outlined,
                        size: 14, color: cs.onSurface.withOpacity(.45)),
                    const SizedBox(width: 6),
                    Text('JE SUIS…',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: cs.onSurface.withOpacity(.45))),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in contexts)
                        ChoiceChip(
                          selected: _nowContexts.contains(c),
                          onSelected: (_) => setState(() {
                            _nowContexts.contains(c)
                                ? _nowContexts.remove(c)
                                : _nowContexts.add(c);
                          }),
                          showCheckmark: false,
                          label: Text(c),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                if (groups.every((g) => g.entries.isEmpty) &&
                    aGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Center(
                      child: Text('Aucune action en attente.',
                          style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurface.withOpacity(.45))),
                    ),
                  ),

                // ── Par projet — GTD d'abord, Gantt à un clic ─────────────
                for (final g in groups)
                  _projectGroup(cs, g.project,
                      g.entries.where((e) => _visible(e.$2)).toList(),
                      hadAny: g.entries.isNotEmpty),

                // ── Projets en pause ──────────────────────────────────────
                if (paused.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('EN PAUSE (${paused.length})',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                          color: cs.onSurface.withOpacity(.4))),
                  const SizedBox(height: 6),
                  for (final p in paused)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceVariant.withOpacity(.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Icon(Icons.pause,
                            size: 14, color: cs.onSurface.withOpacity(.35)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(.5))),
                        ),
                        IconButton(
                          tooltip: 'Reprendre',
                          icon: Icon(Icons.play_circle_outline,
                              size: 20, color: cs.primary),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _togglePause(p),
                        ),
                      ]),
                    ),
                ],

                // ── Actions simples (activités) ───────────────────────────
                ...(() {
                  final visibleA = [
                    for (final g in aGroups)
                      (
                        activity: g.activity,
                        actions: g.actions.where(_visible).toList()
                      ),
                  ].where((g) => g.actions.isNotEmpty).toList();
                  // Section toujours visible s'il existe une activité-temps :
                  // le + de création reste accessible même sans action.
                  if (visibleA.isEmpty &&
                      !_activeActivities.any((a) => a.type == 'time')) {
                    return const <Widget>[];
                  }
                  return <Widget>[
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('ACTIONS SIMPLES',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                              color: cs.onSurface.withOpacity(.4))),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Créer une action simple',
                        icon: Icon(Icons.add,
                            size: 18, color: cs.primary.withOpacity(.75)),
                        visualDensity: VisualDensity.compact,
                        onPressed: _addOwnAction,
                      ),
                    ]),
                    const SizedBox(height: 6),
                    for (final g in visibleA) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(g.activity.name.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                                color: cs.onSurface.withOpacity(.4))),
                      ),
                      for (final a in g.actions)
                        _actionTile(cs, a,
                            onToggle: (v) =>
                                _toggleOwnAction(g.activity, a, v),
                            onTap: () =>
                                _editAction(a, activity: g.activity)),
                    ],
                  ];
                })(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _projectGroup(ColorScheme cs, Project p,
      List<(ProjectTask, TaskAction)> entries,
      {required bool hadAny}) {
    // Vidé par le filtre de contexte → masqué ; vraiment vide → invitation.
    if (entries.isEmpty && hadAny) return const SizedBox.shrink();
    final color =
        domainColor(p.domainId, widget.domains) ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(.8))),
            ),
            IconButton(
              tooltip: 'Ajouter une action',
              icon: Icon(Icons.add,
                  size: 18, color: cs.primary.withOpacity(.75)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _quickAddAction(p),
            ),
            IconButton(
              tooltip: 'Mettre en pause',
              icon: Icon(Icons.pause_circle_outline,
                  size: 18, color: cs.onSurface.withOpacity(.4)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _togglePause(p),
            ),
            // Le Gantt du projet — intégré, mais en SECOND plan.
            IconButton(
              tooltip: 'Ouvrir le Gantt',
              icon: Icon(Icons.stacked_bar_chart,
                  size: 18, color: cs.onSurface.withOpacity(.45)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _openGantt(p),
            ),
          ]),
          if (entries.isEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _quickAddAction(p),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary.withOpacity(.25)),
                ),
                child: Text('Définir la prochaine action',
                    style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.75))),
              ),
            )
          else
            for (final e in entries)
              _actionTile(cs, e.$2,
                  onToggle: (v) => _toggleProjectAction(p, e.$2, v),
                  onTap: () => _editAction(e.$2, project: p, task: e.$1),
                  onOpenTask: () => _openGantt(p, targetTaskId: e.$1.id)),
        ],
      ),
    );
  }

  Widget _actionTile(ColorScheme cs, TaskAction a,
      {required ValueChanged<bool> onToggle,
      required VoidCallback onTap,
      VoidCallback? onOpenTask}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Checkbox(
          value: false,
          shape: const CircleBorder(),
          onChanged: (v) => onToggle(v ?? false),
        ),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Text(a.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                if (a.allContexts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                        (a.allContexts.toList()..sort()).join(' '),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.primary.withOpacity(.75))),
                  ),
              ]),
            ),
          ),
        ),
        if (onOpenTask != null)
          IconButton(
            tooltip: 'Voir dans le Gantt',
            icon: Icon(Icons.open_in_new,
                size: 15, color: cs.onSurface.withOpacity(.35)),
            visualDensity: VisualDensity.compact,
            onPressed: onOpenTask,
          ),
        const SizedBox(width: 4),
      ]),
    );
  }
}
