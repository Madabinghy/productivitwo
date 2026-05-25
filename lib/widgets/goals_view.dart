import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';

class GoalsView extends StatefulWidget {
  final List<Domain> domains;
  final List<Activity> activities;
  final void Function(Activity activity, Project project, ProjectTask task)?
      onStartTimer;
  /// Appelé après chaque validation d'action ou de tâche, avec le total de points.
  final void Function(int doneCount)? onBadgeCheck;
  /// Widget optionnel affiché en tête de la liste (ex. Priorités du jour).
  final Widget? header;

  const GoalsView({
    super.key,
    required this.domains,
    this.activities = const [],
    this.onStartTimer,
    this.onBadgeCheck,
    this.header,
  });

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  List<Project> _projects = [];
  final _sync = FirestoreSync();
  StreamSubscription<List<Project>>? _projectsSub;
  bool _showRealized = false;
  bool _showOutOfScope = false;
  bool _showArchived = false;

  List<Domain> get domains => widget.domains;

  /// Total tâches done + sous-actions cochées — miroir de _ganttActionCount dans main.dart.
  int _totalDoneCount() {
    int total = 0;
    for (final p in _projects) {
      for (final t in p.tasks) {
        if (t.status == 'done') total++;
        total += t.stepsDone;
      }
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _projectsSub = _sync.streamProjects().listen((projects) {
      if (mounted) setState(() => _projects = projects);
    });
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);
    final horizon = todayD.add(const Duration(days: 30));

    final activeProjects = _projects.where((p) => p.status != 'archived').toList();
    final archivedProjects = _projects.where((p) => p.status == 'archived').toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    // Projets où TOUTES les tâches démarrées (non-skippées) sont done → RÉALISÉ
    final doneInScopeProjects = activeProjects.where((p) {
      final inScope = p.tasks
          .where((t) => t.status != 'skipped' && !t.startDate.isAfter(todayD))
          .toList();
      return inScope.isNotEmpty && inScope.every((t) => t.status == 'done');
    }).toList()..sort((a, b) => a.title.compareTo(b.title));
    final doneIds = doneInScopeProjects.map((p) => p.id).toSet();

    // Projets affichés dans la liste principale (excluant ceux entièrement réalisés)
    final mainProjects = activeProjects.where((p) => !doneIds.contains(p.id)).toList();

    // Projets avec au moins une tâche active (non-done) démarrée → affichés dans les sections du haut
    final projectsWithTodayTasks = <String>{};
    for (final p in mainProjects) {
      for (final t in p.tasks) {
        if (t.status == 'skipped') continue;
        if (t.status == 'done') continue;
        if (!t.startDate.isAfter(todayD)) {
          projectsWithTodayTasks.add(p.id);
          break;
        }
      }
    }
    final outOfScope = mainProjects
        .where((p) => !projectsWithTodayTasks.contains(p.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projets'),
        centerTitle: false,
      ),
      body: CustomScrollView(
              slivers: [
                if (widget.header != null)
                  SliverToBoxAdapter(child: widget.header!),
                if (activeProjects.isEmpty && archivedProjects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(context, cs),
                  )
                else ...[
                ..._buildProjectSections(context, mainProjects, todayD),
                // Réalisé
                if (doneInScopeProjects.isNotEmpty)
                  ..._buildCollapsibleSection(
                    context, cs,
                    label: 'À JOUR (${doneInScopeProjects.length})',
                    expanded: _showRealized,
                    onToggle: () => setState(() => _showRealized = !_showRealized),
                    projects: doneInScopeProjects,
                    checkmark: true,
                  ),
                // Hors scope
                if (outOfScope.isNotEmpty)
                  ..._buildCollapsibleSection(
                    context, cs,
                    label: 'HORS SCOPE (${outOfScope.length})',
                    expanded: _showOutOfScope,
                    onToggle: () => setState(() => _showOutOfScope = !_showOutOfScope),
                    projects: outOfScope,
                    showArchiveButton: true,
                  ),
                // En veille
                if (archivedProjects.isNotEmpty)
                  ..._buildCollapsibleSection(
                    context, cs,
                    label: 'EN VEILLE (${archivedProjects.length})',
                    expanded: _showArchived,
                    onToggle: () => setState(() => _showArchived = !_showArchived),
                    projects: archivedProjects,
                    showRestoreButton: true,
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewProjectSheet(
          context,
          domains: domains,
          onCreated: () {},
        ),
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Nouveau projet'),
        backgroundColor: Colors.deepPurple.shade500,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 48, color: cs.onSurface.withOpacity(.2)),
            const SizedBox(height: 16),
            Text(
              'Aucun projet actif',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface.withOpacity(.5)),
            ),
            const SizedBox(height: 8),
            Text(
              'Décris tes idées et ORION structure le projet pour toi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withOpacity(.35)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showNewProjectSheet(
                context,
                domains: domains,
                onCreated: () {},
              ),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Nouveau projet'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProjectSections(
    BuildContext context,
    List<Project> projects,
    DateTime todayD,
  ) {
    final cs = Theme.of(context).colorScheme;

    // Tâches actives démarrées aujourd'hui (done exclues → section RÉALISÉ projet)
    final byDomain = <String?, List<({Project project, ProjectTask task})>>{};
    for (final p in projects) {
      for (final t in p.tasks) {
        if (t.status == 'skipped') continue;
        if (t.status == 'done') continue;
        if (t.startDate.isAfter(todayD)) continue;
        byDomain.putIfAbsent(p.domainId, () => []).add((project: p, task: t));
      }
    }

    final widgets = <Widget>[];

    // Aucune tâche active aujourd'hui → résumé des projets
    if (byDomain.isEmpty) {
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'AUCUNE TÂCHE DÉMARRÉE AUJOURD\'HUI',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4),
            ),
          ),
        ),
      ));
      for (final p in projects) {
        widgets.add(SliverToBoxAdapter(
            child: _buildProjectSummaryTile(context, p)));
      }
      return widgets;
    }

    // Domaines dans l'ordre défini
    final knownIds = domains.map((d) => d.id).toSet();
    final orderedDomainIds = [
      ...domains.map((d) => d.id).where(byDomain.containsKey),
      ...byDomain.keys.where((k) => k != null && !knownIds.contains(k)),
      if (byDomain.containsKey(null)) null,
    ];

    for (final domainId in orderedDomainIds) {
      final pairs = byDomain[domainId]!;
      final domain = domainId != null
          ? domains.where((d) => d.id == domainId).firstOrNull
          : null;
      final color = domainColor(domainId, domains) ?? cs.primary;

      // Header domaine
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                domain?.name.toUpperCase() ?? 'SANS DOMAINE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                    letterSpacing: 1, color: color),
              ),
            ],
          ),
        ),
      ));

      // Grouper par projet dans ce domaine
      final byProject = <String, List<ProjectTask>>{};
      final projectMap = <String, Project>{};
      for (final pair in pairs) {
        byProject.putIfAbsent(pair.project.id, () => []).add(pair.task);
        projectMap[pair.project.id] = pair.project;
      }

      for (final projectId in byProject.keys) {
        final project = projectMap[projectId]!;
        final tasks = byProject[projectId]!;

        // Header projet (si plusieurs projets dans le même domaine)
        if (byProject.length > 1) {
          widgets.add(SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                project.title,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: cs.onSurface.withOpacity(.55)),
              ),
            ),
          ));
        }

        // Grouper par phase dans ce projet
        final phaseMap = {for (final ph in project.phases) ph.id: ph};
        final byPhase = <String?, List<ProjectTask>>{};
        for (final t in tasks) {
          byPhase.putIfAbsent(t.phaseId, () => []).add(t);
        }

        // Afficher dans l'ordre des phases, puis phaseId orphelin (phase supprimée), puis sans phase
        final orderedPhaseIds = [
          ...project.phases.map((ph) => ph.id).where(byPhase.containsKey),
          // Tâches avec un phaseId qui n'existe plus dans les phases → affichées sans en-tête
          ...byPhase.keys.where((k) => k != null && !phaseMap.containsKey(k)),
          if (byPhase.containsKey(null)) null,
        ];

        for (final phaseId in orderedPhaseIds) {
          final phaseTasks = byPhase[phaseId]!;
          final phase = phaseId != null ? phaseMap[phaseId] : null;

          // Header phase
          if (phase != null) {
            Color phaseColor = color;
            if (phase.color != null) {
              try {
                final hex = phase.color!.replaceAll('#', '');
                phaseColor = Color(int.parse('FF$hex', radix: 16));
              } catch (_) {}
            }
            widgets.add(SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: phaseColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      phase.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: cs.onSurface.withOpacity(.45)),
                    ),
                  ],
                ),
              ),
            ));
          }

          widgets.add(SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final task = phaseTasks[i];
                return _GanttTaskCard(
                  project: project,
                  task: task,
                  domains: domains,
                  today: todayD,
                  color: color,
                  projectTitle: byProject.length == 1 ? project.title : '',
                  onTaskActionToggled: (taskId, actionIdx, value) async {
                    final action = project.tasks
                        .firstWhere((t) => t.id == taskId)
                        .actions[actionIdx];
                    action.done = value;
                    action.doneAt = value ? DateTime.now() : null;
                    await _sync.saveProjectTasks(project.id, project.tasks);
                    setState(() {});
                    if (value) widget.onBadgeCheck?.call(_totalDoneCount());
                  },
                  onTap: () => showProjectSheet(
                    context,
                    project: project,
                    domains: domains,
                    targetTaskId: task.id,
                  ),
                  onReorderActions: (oldIdx, newIdx) async {
                    final action = task.actions.removeAt(oldIdx);
                    task.actions.insert(newIdx, action);
                    await _sync.saveProjectTasks(project.id, project.tasks);
                    setState(() {});
                  },
                  onPlay: widget.onStartTimer == null
                      ? null
                      : () => _onPlay(context, project, task, color),
                  onComplete: () async {
                    task.status = task.status == 'done' ? 'pending' : 'done';
                    await _sync.saveProjectTasks(project.id, project.tasks);
                    setState(() {});
                    if (task.status == 'done') widget.onBadgeCheck?.call(_totalDoneCount());
                  },
                  onAddAction: (title) async {
                    task.actions.add(TaskAction(title: title));
                    await _sync.saveProjectTasks(project.id, project.tasks);
                    setState(() {});
                  },
                  onToggleTodayFlag: () async {
                    await _sync.toggleTaskTodayFlag(
                        project.id, task.id, !task.todayFlag);
                  },
                );
              },
              childCount: phaseTasks.length,
            ),
          ));
        }
      }
    }

    return widgets;
  }

  Widget _buildProjectSummaryTile(BuildContext context, Project project) {
    final cs = Theme.of(context).colorScheme;
    final totalTasks = project.tasks.length;
    final doneTasks = project.tasks.where((t) => t.status == 'done').length;
    final progress = totalTasks > 0 ? doneTasks / totalTasks : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showProjectSheet(context,
            project: project, domains: domains),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      '$doneTasks/$totalTasks tâches',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(.4)),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: cs.onSurface.withOpacity(.1),
                      color: cs.primary,
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: cs.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCollapsibleSection(
    BuildContext context,
    ColorScheme cs, {
    required String label,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Project> projects,
    bool showArchiveButton = false,
    bool showRestoreButton = false,
    bool checkmark = false,
  }) {
    return [
      SliverToBoxAdapter(
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: cs.onSurface.withOpacity(.4))),
                const Spacer(),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: cs.onSurface.withOpacity(.3)),
              ],
            ),
          ),
        ),
      ),
      if (expanded)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final p = projects[i];
              final totalTasks = p.tasks.length;
              final doneTasks = p.tasks.where((t) => t.status == 'done').length;
              final progress = totalTasks > 0 ? doneTasks / totalTasks : 0.0;
              final dColor = domainColor(p.domainId, domains) ?? cs.primary;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showProjectSheet(context, project: p, domains: domains),
                child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: checkmark
                        ? Colors.green.withOpacity(.06)
                        : cs.surfaceContainerHighest.withOpacity(.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: checkmark
                          ? Colors.green.withOpacity(.25)
                          : cs.outlineVariant.withOpacity(.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (checkmark)
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(Icons.check_circle_outline,
                              size: 16, color: Colors.green),
                        )
                      else ...[
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                              color: dColor.withOpacity(.5), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: checkmark
                                        ? Colors.green.withOpacity(.8)
                                        : cs.onSurface.withOpacity(.6))),
                            if (totalTasks > 0)
                              Text('$doneTasks/$totalTasks tâches',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: checkmark
                                          ? Colors.green.withOpacity(.5)
                                          : cs.onSurface.withOpacity(.35))),
                          ],
                        ),
                      ),
                      if (totalTasks > 0 && !checkmark)
                        SizedBox(
                          width: 30, height: 30,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            backgroundColor: cs.onSurface.withOpacity(.08),
                            color: dColor.withOpacity(.5),
                          ),
                        ),
                      if (showArchiveButton) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            p.status = 'archived';
                            await _sync.saveProject(p);
                            setState(() {});
                          },
                          child: Icon(Icons.archive_outlined,
                              size: 18, color: cs.onSurface.withOpacity(.3)),
                        ),
                      ],
                      if (showRestoreButton) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            p.status = 'active';
                            await _sync.saveProject(p);
                            setState(() {});
                          },
                          child: Icon(Icons.unarchive_outlined,
                              size: 18, color: cs.onSurface.withOpacity(.3)),
                        ),
                      ],
                    ],
                  ),
                ),
              ));
            },
            childCount: projects.length,
          ),
        ),
    ];
  }

  Future<void> _onPlay(BuildContext context, Project project,
      ProjectTask task, Color color) async {
    // Activités du domaine du projet
    final domainActivities = widget.activities
        .where((a) => a.domainId == project.domainId && !a.isHabit)
        .toList();

    if (domainActivities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune activité dans ce domaine.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Activity? activity;
    if (domainActivities.length == 1) {
      activity = domainActivities.first;
    } else {
      activity = await showModalBottomSheet<Activity>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text('Sur quelle activité ?',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                for (final a in domainActivities)
                  ListTile(
                    leading: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    title: Text(a.name),
                    onTap: () => Navigator.pop(ctx, a),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    }

    if (activity != null) widget.onStartTimer?.call(activity, project, task);
  }

  void _showWebHint(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Créer un projet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Les projets Gantt se créent depuis l\'app web. '
              'Ouvre productivitwo-app.web.app et utilise le tab Projets.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu peux aussi demander à Claude de créer un projet via MCP.',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gantt task card ───────────────────────────────────────────────────────────

class _GanttTaskCard extends StatelessWidget {
  final Project project;
  final ProjectTask task;
  final List<Domain> domains;
  final DateTime today;
  final Color color;
  final String projectTitle;
  final void Function(String taskId, int actionIdx, bool value) onTaskActionToggled;
  final Future<void> Function(int oldIndex, int newIndex)? onReorderActions;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onComplete;
  final Future<void> Function(String title)? onAddAction;
  final VoidCallback? onToggleTodayFlag;

  const _GanttTaskCard({
    required this.project,
    required this.task,
    required this.domains,
    required this.today,
    required this.color,
    required this.projectTitle,
    required this.onTaskActionToggled,
    required this.onTap,
    this.onReorderActions,
    this.onPlay,
    this.onComplete,
    this.onAddAction,
    this.onToggleTodayFlag,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDone = task.status == 'done';
    final isOverdue = task.endDate != null &&
        task.endDate!.isBefore(today) &&
        !isDone;
    final hasActions = task.actions.isNotEmpty;
    final doneActions = task.actions.where((a) => a.done).length;
    final totalActions = task.actions.length;
    final progress = totalActions > 0 ? doneActions / totalActions : null;
    // Seules les sous-actions non cochées sont affichées dans la carte
    final undoneSubActions = task.actions.where((a) => !a.done).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Opacity(
        opacity: isDone ? 0.55 : 1.0,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(isDone ? .3 : .55),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: isDone ? Colors.green.withOpacity(.5) : isOverdue ? cs.error : color,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.isMilestone)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Transform.rotate(
                        angle: 0.785,
                        child: Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: isDone ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  if (progress != null) ...[
                    Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Étoile priorité du jour
                  GestureDetector(
                    onTap: onToggleTodayFlag,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        task.todayFlag ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 18,
                        color: task.todayFlag
                            ? Colors.amber.shade600
                            : cs.onSurface.withOpacity(.25),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (onPlay != null)
                    GestureDetector(
                      onTap: onPlay,
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            size: 18, color: color),
                      ),
                    )
                  else
                    Icon(Icons.chevron_right,
                        size: 16, color: cs.onSurface.withOpacity(.25)),
                ],
              ),
              Text(
                projectTitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(.45),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(3),
                  backgroundColor: cs.onSurface.withOpacity(.08),
                  color: isOverdue ? cs.error : color,
                ),
              ],
              if (task.endDate != null) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 11,
                      color: isOverdue
                          ? cs.error
                          : cs.onSurface.withOpacity(.35),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _fmtDate(task.endDate!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue
                            ? cs.error
                            : cs.onSurface.withOpacity(.4),
                        fontWeight: isOverdue
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (isOverdue) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '−${today.difference(task.endDate!).inDays}j',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cs.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (hasActions) ...[
                const SizedBox(height: 8),
                // Seules les sous-actions non cochées sont affichées
                if (undoneSubActions.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: undoneSubActions.length,
                    onReorder: (oldIdx, newIdx) {
                      // Convertir les indices display (undone) → indices originaux
                      final origOld =
                          task.actions.indexOf(undoneSubActions[oldIdx]);
                      final origNewPre = newIdx < undoneSubActions.length
                          ? task.actions.indexOf(undoneSubActions[newIdx])
                          : task.actions.length;
                      // Ajustement post-suppression dans l'espace original
                      final origNew =
                          origNewPre > origOld ? origNewPre - 1 : origNewPre;
                      onReorderActions?.call(origOld, origNew);
                    },
                    itemBuilder: (ctx, i) {
                      final action = undoneSubActions[i];
                      final origIdx = task.actions.indexOf(action);
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey('${task.id}_undone_action_$i'),
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              // Checkbox
                              GestureDetector(
                                onTap: () => onTaskActionToggled(
                                    task.id, origIdx, true),
                                child: Icon(
                                  Icons.check_box_outline_blank,
                                  size: 16,
                                  color: cs.onSurface.withOpacity(.4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Titre — tap pour éditer
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    final ctrl = TextEditingController(
                                        text: action.title);
                                    final result = await showDialog<String>(
                                      context: ctx,
                                      builder: (c) => AlertDialog(
                                        title:
                                            const Text('Modifier l\'action'),
                                        content: TextField(
                                          controller: ctrl,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder()),
                                          onSubmitted: (v) {
                                            if (v.trim().isNotEmpty)
                                              Navigator.pop(c, v.trim());
                                          },
                                        ),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c),
                                              child: const Text('Annuler')),
                                          FilledButton(
                                            onPressed: () {
                                              final v = ctrl.text.trim();
                                              if (v.isNotEmpty)
                                                Navigator.pop(c, v);
                                            },
                                            child:
                                                const Text('Enregistrer'),
                                          ),
                                        ],
                                      ),
                                    );
                                    ctrl.dispose();
                                    if (result != null) {
                                      action.title = result;
                                      onTaskActionToggled(
                                          task.id, origIdx, action.done);
                                    }
                                  },
                                  child: Text(
                                    action.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withOpacity(.8),
                                    ),
                                  ),
                                ),
                              ),
                              Icon(Icons.drag_handle,
                                  size: 14,
                                  color: cs.onSurface.withOpacity(.2)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                // Indicateur sous-actions cochées
                if (doneActions > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 12,
                            color: Colors.green.withOpacity(.65)),
                        const SizedBox(width: 4),
                        Text(
                          '$doneActions réalisée${doneActions > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.35),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              // Valider (100% ou pas de sous-actions) + bouton +
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onAddAction != null)
                    GestureDetector(
                      onTap: () => _showAddActionDialog(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 14, color: cs.onSurface.withOpacity(.35)),
                          const SizedBox(width: 3),
                          Text('Ajouter',
                              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.35))),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (onComplete != null)
                    GestureDetector(
                      onTap: onComplete,
                      child: task.status == 'done'
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.withOpacity(.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.undo_rounded, size: 14, color: Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Text('Annuler',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade700)),
                                ],
                              ),
                            )
                          : (!hasActions || (progress != null && progress >= 1.0))
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_rounded, size: 14, color: Colors.green.shade600),
                                      const SizedBox(width: 4),
                                      Text('Valider',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green.shade600)),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _showAddActionDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle action'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Description…'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (result != null) await onAddAction?.call(result);
  }

  String _fmtDate(DateTime d) {
    const m = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
