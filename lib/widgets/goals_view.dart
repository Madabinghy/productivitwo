import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';

class GoalsView extends StatefulWidget {
  final List<Domain> domains;

  const GoalsView({super.key, required this.domains});

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  List<Project> _projects = [];
  final _sync = FirestoreSync();
  StreamSubscription<List<Project>>? _projectsSub;

  List<Domain> get domains => widget.domains;

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

    final activeProjects = _projects
        .where((p) => p.status != 'archived')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projets'),
        centerTitle: false,
      ),
      body: activeProjects.isEmpty
          ? _buildEmptyState(context, cs)
          : CustomScrollView(
              slivers: [
                ..._buildProjectSections(context, activeProjects, todayD, horizon),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showWebHint(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau projet'),
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
              'Crée tes projets depuis l\'app web\npuis ils apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withOpacity(.35)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showWebHint(context),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('Ouvrir l\'app web'),
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
    DateTime horizon,
  ) {
    // Grouper les tâches actives par domaine
    final byDomain = <String?, List<({Project project, ProjectTask task})>>{};
    for (final p in projects) {
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (t.startDate.isAfter(horizon)) continue;
        byDomain.putIfAbsent(p.domainId, () => []).add((project: p, task: t));
      }
    }

    // Projets sans tâches actives proches (affiche quand même le projet)
    final projectsWithNoNearTasks = projects
        .where((p) => !byDomain.values.any(
            (pairs) => pairs.any((pair) => pair.project.id == p.id)))
        .toList();

    final widgets = <Widget>[];

    if (byDomain.isEmpty && projectsWithNoNearTasks.isNotEmpty) {
      // Tous les projets existent mais aucune tâche dans les 30j
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'PROJETS ACTIFS — aucune tâche urgente (30j)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.4),
            ),
          ),
        ),
      ));
      for (final p in projectsWithNoNearTasks) {
        widgets.add(SliverToBoxAdapter(
          child: _buildProjectSummaryTile(context, p),
        ));
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
      final color = domainColor(domainId, domains) ??
          Theme.of(context).colorScheme.primary;

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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: color,
                ),
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
        widgets.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _GanttTaskCard(
              project: project,
              task: tasks[i],
              domains: domains,
              today: todayD,
              color: color,
              projectTitle: project.title,
              onTaskActionToggled: (taskId, actionIdx, value) async {
                project.tasks
                    .firstWhere((t) => t.id == taskId)
                    .actions[actionIdx]
                    .done = value;
                await _sync.saveProjectTasks(project.id, project.tasks);
                setState(() {});
              },
              onTap: () => showProjectSheet(
                context,
                project: project,
                domains: domains,
                targetTaskId: tasks[i].id,
              ),
            ),
            childCount: tasks.length,
          ),
        ));
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
  final VoidCallback onTap;

  const _GanttTaskCard({
    required this.project,
    required this.task,
    required this.domains,
    required this.today,
    required this.color,
    required this.projectTitle,
    required this.onTaskActionToggled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOverdue = task.endDate != null &&
        task.endDate!.isBefore(today) &&
        task.status != 'done';
    final hasActions = task.actions.isNotEmpty;
    final doneActions = task.actions.where((a) => a.done).length;
    final totalActions = task.actions.length;
    final progress = totalActions > 0 ? doneActions / totalActions : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.55),
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(
                color: isOverdue ? cs.error : color,
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
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
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
                for (int i = 0; i < task.actions.length; i++)
                  GestureDetector(
                    onTap: () =>
                        onTaskActionToggled(task.id, i, !task.actions[i].done),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            task.actions[i].done
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: task.actions[i].done
                                ? Colors.green.shade500
                                : cs.onSurface.withOpacity(.4),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.actions[i].title,
                              style: TextStyle(
                                fontSize: 13,
                                color: task.actions[i].done
                                    ? cs.onSurface.withOpacity(.35)
                                    : cs.onSurface.withOpacity(.8),
                                decoration: task.actions[i].done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
