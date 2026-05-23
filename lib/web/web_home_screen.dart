import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/help_sheet.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:productivitwo_v1/web/assistant_history_sheet.dart';

Color? _parseTaskColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final clean = hex.replaceAll('#', '').replaceAll(RegExp(r'^0[xX]'), '');
    if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
    if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  } catch (_) {}
  return null;
}

class WebHomeScreen extends StatefulWidget {
  const WebHomeScreen({super.key});

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen>
    with SingleTickerProviderStateMixin {
  final _sync = FirestoreSync();
  List<Project> _projects = [];
  List<StrategicObjective> _objectives = [];
  List<Domain> _domains = [];
  List<RecurringAction> _routines = [];
  Map<String, List<Map<String, dynamic>>> _documentsByProject = {};
  String? _selectedDomainId;
  bool _loading = true;
  late TabController _mainTabs;
  List<AssistantMessageData> _assistantMessages = [];

  @override
  void initState() {
    super.initState();
    _mainTabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _mainTabs.dispose();
    super.dispose();
  }

  bool _hasIosData = false;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _sync.fetchProjects(),
        _sync.fetchStrategicObjectives(),
        _sync.fetchApiTokens(),
        _sync.fetchDomains(),
        _sync.fetchRoutines(),
        _sync.fetchDocuments(),
      ]);
      if (!mounted) return;
      final tokens = results[2] as List;
      final allDocs = results[5] as List<Map<String, dynamic>>;
      // Group documents by projectId
      final byProject = <String, List<Map<String, dynamic>>>{};
      for (final doc in allDocs) {
        final pid = doc['projectId'] as String?;
        if (pid != null && pid.isNotEmpty) {
          byProject.putIfAbsent(pid, () => []).add(doc);
        }
      }
      final loadedProjects = results[0] as List<Project>;
      final loadedDomains  = results[3] as List<Domain>;

      setState(() {
        _projects = loadedProjects;
        _objectives = results[1] as List<StrategicObjective>;
        _domains = loadedDomains;
        _routines = results[4] as List<RecurringAction>;
        _documentsByProject = byProject;
        _hasIosData = tokens.isNotEmpty;
        _loading = false;
      });

      // Évaluation de l'assistant après chargement
      final messages = await AssistantEngine.evaluate(
        projects: loadedProjects,
        domains: loadedDomains,
      );
      if (mounted && messages.isNotEmpty) {
        setState(() => _assistantMessages = messages);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _showLinkIosDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LinkIosDialog(onLinked: _load),
    );
  }

  void _showTokensPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TokensPanel(sync: _sync),
    );
  }

  StrategicObjective? _objectiveFor(Project p) => p.strategicObjectiveId == null
      ? null
      : _objectives.where((o) => o.id == p.strategicObjectiveId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(Icons.account_tree_outlined,
                  color: cs.primary, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Productivitwo — Projects',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  user.displayName ?? user.email ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ),
            const HelpButton(),
            IconButton(
              icon: Badge(
                isLabelVisible: _assistantMessages.isNotEmpty,
                smallSize: 7,
                backgroundColor: const Color(0xFFe8c94a),
                child: const Icon(Icons.smart_toy_outlined, size: 18),
              ),
              tooltip: 'Messages ORION',
              onPressed: () => AssistantHistorySheet.show(context),
            ),
            TextButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Connecter Claude'),
              onPressed: () => _showTokensPanel(context),
            ),
            IconButton(
              icon: const Icon(Icons.logout_outlined, size: 18),
              tooltip: 'Déconnexion',
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
            const SizedBox(width: 8),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _mainTabs,
                tabs: const [
                  Tab(text: 'Projets'),
                  Tab(text: 'Focus'),
                  Tab(text: 'Archives'),
                  Tab(text: 'ORION'),
                ],
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                TabBarView(
                  controller: _mainTabs,
                  children: [
                    _SimpleProjectsView(
                      projects: _projects,
                      domains: _domains,
                      sync: _sync,
                      onRefresh: _load,
                    ),
                    _FocusView(
                      projects: _projects
                          .where((p) => p.status != 'archived')
                          .toList(),
                      domains: _domains,
                      routines: _routines,
                      sync: _sync,
                      onRefresh: _load,
                      onTaskColorChange: (project, task, color) async {
                        task.color = color;
                        await _sync.saveProjectTasks(project.id, project.tasks);
                        _load();
                      },
                    ),
                    _ArchivesView(sync: _sync),
                    _OrionView(sync: _sync),
                  ],
                ),
                if (_assistantMessages.isNotEmpty)
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: AssistantOverlay(
                      key: ValueKey(_assistantMessages.first.id),
                      messages: _assistantMessages,
                      onAction: _handleAssistantAction,
                    ),
                  ),
              ],
            ),
    );
  }

  static Color _domainColor(Domain? domain, ColorScheme cs, [List<Domain>? allDomains]) {
    if (domain == null) return cs.primary;
    if (domain.colorValue != null) return Color(domain.colorValue!);
    if (allDomains != null) {
      final idx = allDomains.indexWhere((d) => d.id == domain.id);
      if (idx >= 0) return kDomainPalette[idx % kDomainPalette.length];
    }
    return cs.primary;
  }


  Future<void> _archiveProject(Project p, bool archive) async {
    await _sync.saveProject(p..status = archive ? 'archived' : 'active');
    _load();
  }

  Future<void> _deleteProject(Project p) async {
    await _sync.deleteProject(p.id);
    _load();
  }

  void _handleAssistantAction(AssistantActionData action) {
    switch (action.type) {
      case 'open_day_plan':
      case 'open_goals':
        _mainTabs.animateTo(1);
      case 'open_project':
        final projectId = action.payload?['projectId'] as String?;
        if (projectId == null) return;
        final p = _projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => GanttScreen(project: p, domains: _domains)));
      case 'open_gantt_task':
        final projectId = action.payload?['projectId'] as String?;
        final taskId   = action.payload?['taskId']   as String?;
        if (projectId == null) return;
        final p = _projects.where((p) => p.id == projectId).firstOrNull;
        if (p == null) return;
        Navigator.push(context,
            MaterialPageRoute(
              builder: (_) => GanttScreen(project: p, targetTaskId: taskId, domains: _domains),
            ));
      case 'open_activity':
        _mainTabs.animateTo(1);
    }
  }
}

// ── Vue Focus — Semaine en cours ─────────────────────────────────────────────

class _FocusView extends StatelessWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<RecurringAction> routines;
  final FirestoreSync sync;
  final VoidCallback? onRefresh;
  final Future<void> Function(Project, ProjectTask, String?) onTaskColorChange;
  const _FocusView({
    required this.projects,
    required this.domains,
    required this.routines,
    required this.sync,
    required this.onTaskColorChange,
    this.onRefresh,
  });

  // ── Helpers ──────────────────────────────────────────────────────────────

  static const _dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  static Color _domainColor(Domain? domain, ColorScheme cs, List<Domain> allDomains) {
    if (domain == null) return cs.onSurface.withOpacity(0.4);
    if (domain.colorValue != null) return Color(domain.colorValue!);
    final idx = allDomains.indexWhere((d) => d.id == domain.id);
    if (idx >= 0) return kDomainPalette[idx % kDomainPalette.length];
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Week boundaries (Monday–Sunday)
    final weekday = today.weekday; // 1=Mon..7=Sun
    final weekStart = today.subtract(Duration(days: weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    // ── Build (task, project) pairs that overlap the week ────────────────
    final allPairs = <({ProjectTask task, Project project})>[];
    for (final p in projects) {
      for (final t in p.tasks) {
        final effectiveEnd = t.endDate ?? t.startDate;
        final overlaps = !t.startDate.isAfter(weekEnd) &&
            !effectiveEnd.isBefore(weekStart);
        if (overlaps) allPairs.add((task: t, project: p));
      }
    }

    // ── Overdue (all tasks, not just this week) ───────────────────────────
    final overduePairs = <({ProjectTask task, Project project})>[];
    for (final p in projects) {
      for (final t in p.tasks) {
        if (t.endDate != null &&
            t.endDate!.isBefore(today) &&
            t.status != 'done' &&
            t.status != 'skipped') {
          overduePairs.add((task: t, project: p));
        }
      }
    }
    overduePairs.sort((a, b) => a.task.endDate!.compareTo(b.task.endDate!));

    // ── Group tasks by domain ─────────────────────────────────────────────
    // Map domainId -> list of pairs
    final byDomain = <String?, List<({ProjectTask task, Project project})>>{};
    for (final pair in allPairs) {
      final did = pair.project.domainId;
      byDomain.putIfAbsent(did, () => []).add(pair);
    }

    // Build ordered domain groups: known domains first (sorted), then null
    // Inclut les domaines qui ont des routines même sans tâches Gantt cette semaine
    final domainGroups = <({Domain? domain, List<({ProjectTask task, Project project})> pairs})>[];
    final seenDomainIds = <String?>{};
    for (final domain in domains) {
      if (domain.deleted) continue;
      final pairs = byDomain[domain.id] ?? [];
      final hasRoutines = routines.any((r) => r.domainId == domain.id && !r.deleted && r.active);
      if (pairs.isNotEmpty || hasRoutines) {
        domainGroups.add((domain: domain, pairs: pairs));
        seenDomainIds.add(domain.id);
      }
    }
    // Tâches/routines sans domaine ou domaine inconnu
    final noDomainPairs = byDomain[null] ?? [];
    final nodomainRoutines = routines.where((r) =>
        !r.deleted && r.active &&
        (r.domainId == null || !seenDomainIds.contains(r.domainId))).toList();
    if (noDomainPairs.isNotEmpty || nodomainRoutines.isNotEmpty) {
      domainGroups.add((domain: null, pairs: noDomainPairs));
    }

    // ── Week stats ────────────────────────────────────────────────────────
    final weekActive = allPairs.where((e) =>
        e.task.status != 'skipped' && !e.task.isMilestone).length;
    final weekDone = allPairs.where((e) => e.task.status == 'done').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final isWide   = constraints.maxWidth >= 850;
        if (isNarrow) {
          return _buildSidebar(
              context, cs, today, weekStart, weekEnd, overduePairs, allPairs, projects);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gantt ──────────────────────────────────────────────────────
            Expanded(
              flex: isWide ? 5 : 7,
              child: _buildGantt(
                context,
                cs,
                today,
                weekStart,
                weekDone,
                weekActive,
                domainGroups,
              ),
            ),
            SizedBox(
              width: 1,
              child: VerticalDivider(
                  color: cs.outlineVariant.withOpacity(0.4), width: 1),
            ),
            // ── Panneau tâches actives (visible ≥ 1100px) ─────────────────
            if (isWide) ...[
              Expanded(
                flex: 4,
                child: _buildProjectsPanel(context, cs, today, allPairs),
              ),
              SizedBox(
                width: 1,
                child: VerticalDivider(
                    color: cs.outlineVariant.withOpacity(0.4), width: 1),
              ),
            ],
            // ── Sidebar ────────────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: _buildSidebar(
                  context, cs, today, weekStart, weekEnd, overduePairs, allPairs, projects),
            ),
          ],
        );
      },
    );
  }

  // ── Panneau tâches actives de la semaine ──────────────────────────────────

  Widget _buildProjectsPanel(
    BuildContext context,
    ColorScheme cs,
    DateTime today,
    List<({ProjectTask task, Project project})> weekPairs,
  ) {
    // Grouper les tâches non-terminées par projet
    final byProject = <String, List<ProjectTask>>{};
    final projectMap = <String, Project>{};
    for (final pair in weekPairs) {
      if (pair.task.status == 'done' || pair.task.status == 'skipped') continue;
      if (pair.task.isMilestone) continue;
      byProject.putIfAbsent(pair.project.id, () => []).add(pair.task);
      projectMap[pair.project.id] = pair.project;
    }

    if (byProject.isEmpty) {
      return Center(
        child: Text(
          'Aucune tâche active cette semaine',
          style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.35),
              fontStyle: FontStyle.italic),
        ),
      );
    }

    // Trier par ordre d'apparition dans la liste originale des projets
    final orderedProjectIds = weekPairs
        .map((e) => e.project.id)
        .where(byProject.containsKey)
        .toSet()
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_tree_outlined,
                size: 13, color: cs.onSurface.withOpacity(.45)),
            const SizedBox(width: 6),
            Text(
              'TÂCHES EN COURS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: cs.onSurface.withOpacity(.45),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          for (final projectId in orderedProjectIds) ...[
            _buildPanelProjectGroup(
              context,
              cs,
              projectMap[projectId]!,
              byProject[projectId]!,
              today,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildPanelProjectGroup(
    BuildContext context,
    ColorScheme cs,
    Project project,
    List<ProjectTask> tasks,
    DateTime today,
  ) {
    // Couleur domaine
    final domainIdx = domains.indexWhere((d) => d.id == project.domainId);
    final domain = domainIdx >= 0 ? domains[domainIdx] : null;
    final color = domain?.colorValue != null
        ? Color(domain!.colorValue!)
        : domainIdx >= 0
            ? kDomainPalette[domainIdx % kDomainPalette.length]
            : cs.primary;

    // Grouper par phase
    final phaseMap = {for (final ph in project.phases) ph.id: ph};
    final byPhase = <String?, List<ProjectTask>>{};
    for (final t in tasks) byPhase.putIfAbsent(t.phaseId, () => []).add(t);

    final orderedPhaseIds = [
      ...project.phases.map((ph) => ph.id).where(byPhase.containsKey),
      if (byPhase.containsKey(null)) null,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titre projet
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              project.title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: 6),

        // Tâches par phase
        for (final phaseId in orderedPhaseIds) ...[
          if (phaseId != null && phaseMap[phaseId] != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 15, bottom: 3, top: 4),
              child: Text(
                phaseMap[phaseId]!.label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: cs.onSurface.withOpacity(.35)),
              ),
            ),
          ],
          for (final task in byPhase[phaseId]!) ...[
            _buildPanelTaskRow(context, cs, project, task, color, today),
            const SizedBox(height: 4),
          ],
        ],

        // Bouton discret + Ajouter une tâche
        const SizedBox(height: 2),
        InkWell(
          onTap: () => _addTaskToProject(context, project, color),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 12, color: color.withOpacity(.45)),
                const SizedBox(width: 4),
                Text('Ajouter une tâche',
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withOpacity(.45))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addTaskToProject(
      BuildContext context, Project project, Color color) async {
    final titleCtrl = TextEditingController();
    final today = DateTime.now();

    // Choisir la phase par défaut = la première phase active du projet
    String? defaultPhaseId = project.phases.isNotEmpty
        ? project.phases.first.id
        : null;

    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        title: Row(children: [
          Container(
            width: 3, height: 18,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(project.title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Titre de la tâche',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
              },
            ),
            if (project.phases.isNotEmpty) ...[
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx2, setSt) => DropdownButtonFormField<String?>(
                  value: defaultPhaseId,
                  decoration: const InputDecoration(
                    labelText: 'Phase (optionnel)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sans phase')),
                    for (final ph in project.phases)
                      DropdownMenuItem(value: ph.id, child: Text(ph.label)),
                  ],
                  onChanged: (v) {
                    setSt(() => defaultPhaseId = v);
                  },
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final t = titleCtrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    titleCtrl.dispose();
    if (result == null) return;

    final newTask = ProjectTask(
      title: result,
      phaseId: defaultPhaseId,
      startDate: today,
      status: 'pending',
    );
    project.tasks.add(newTask);
    await sync.saveProjectTasks(project.id, project.tasks);
    onRefresh?.call();
  }

  Widget _buildPanelTaskRow(
    BuildContext context,
    ColorScheme cs,
    Project project,
    ProjectTask task,
    Color color,
    DateTime today,
  ) {
    final isLate = task.endDate != null &&
        task.endDate!.isBefore(today);
    final daysLate = isLate
        ? today.difference(task.endDate!).inDays
        : 0;
    final doneActions = task.actions.where((a) => a.done).length;
    final totalActions = task.actions.length;

    return Builder(
      builder: (freshCtx) => InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await showGanttTaskDetailDialog(
          freshCtx,
          project: project,
          task: task,
          sync: sync,
          onProjectUpdated: (_) => onRefresh?.call(),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.25),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isLate ? cs.error.withOpacity(.7) : color.withOpacity(.5),
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withOpacity(.85)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isLate || totalActions > 0) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      if (isLate)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '−$daysLate j',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: cs.onErrorContainer),
                          ),
                        )
                      else if (task.endDate != null) ...[
                        Text(
                          _fmtDate(task.endDate!),
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(.35)),
                        ),
                      ],
                      if (totalActions > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.checklist_outlined,
                            size: 10,
                            color: cs.onSurface.withOpacity(.35)),
                        const SizedBox(width: 2),
                        Text(
                          '$doneActions/$totalActions',
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(.35)),
                        ),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 14, color: cs.onSurface.withOpacity(.2)),
          ],
        ),
      ),
      ), // InkWell
    ); // Builder
  }

  static String _fmtDate(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }

  // ── GANTT ─────────────────────────────────────────────────────────────────

  Widget _buildGantt(
    BuildContext context,
    ColorScheme cs,
    DateTime today,
    DateTime weekStart,
    int weekDone,
    int weekActive,
    List<({Domain? domain, List<({ProjectTask task, Project project})> pairs})> domainGroups,
  ) {
    const rowH = 30.0;
    const dayW = 40.0;
    const headerH = 36.0;
    const domainHeaderH = 26.0;
    const padding = 20.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // labelW remplit tout l'espace disponible moins les 7 colonnes jours et le padding
        final labelW = (constraints.maxWidth - padding * 2 - 7 * dayW)
            .clamp(180.0, 480.0);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stat globale ─────────────────────────────────────────────
            Text(
              '$weekDone / $weekActive tâches actives faites cette semaine',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 12),

            // ── Tracker ──────────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    SizedBox(width: labelW),
                    for (int d = 0; d < 7; d++) ...[
                      _buildDayHeader(
                        cs,
                        _dayLabels[d],
                        weekStart.add(Duration(days: d)).day,
                        weekStart.add(Duration(days: d)) == today,
                        dayW,
                        headerH,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Domain groups
                if (domainGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Aucune tâche cette semaine',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.35),
                        ),
                      ),
                    ),
                  )
                else
                  for (final group in domainGroups) ...[
                    _buildDomainGroupRows(
                      context,
                      cs,
                      group.domain,
                      group.pairs,
                      today,
                      weekStart,
                      labelW,
                      dayW,
                      rowH,
                      domainHeaderH,
                      routines,
                    ),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
      }, // end LayoutBuilder.builder
    ); // end LayoutBuilder
  }

  Widget _buildDayHeader(
    ColorScheme cs,
    String dayName,
    int dayNum,
    bool isToday,
    double width,
    double height,
  ) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: isToday
              ? BoxDecoration(
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Text(
            '$dayName\n$dayNum',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday
                  ? Colors.teal.shade700
                  : cs.onSurface.withOpacity(0.5),
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDomainGroupRows(
    BuildContext context,
    ColorScheme cs,
    Domain? domain,
    List<({ProjectTask task, Project project})> pairs,
    DateTime today,
    DateTime weekStart,
    double labelW,
    double dayW,
    double rowH,
    double domainHeaderH,
    List<RecurringAction> allRoutines,
  ) {
    final color = _domainColor(domain, cs, domains);
    final domainName = domain?.name ?? 'Sans domaine';
    // Total width = labelW + 7 * dayW
    final totalW = labelW + 7 * dayW;

    // Routines actives pour ce domaine
    final domainRoutines = allRoutines
        .where((r) =>
            r.domainId == domain?.id &&
            !r.deleted &&
            r.active)
        .toList();

    final hasRoutines = domainRoutines.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Domain header (spans full width)
        SizedBox(
          width: totalW,
          child: Container(
            height: domainHeaderH,
            margin: const EdgeInsets.only(bottom: 2, top: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  domainName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Routine rows (first)
        for (final routine in domainRoutines) ...[
          _buildRoutineRow(
            cs,
            routine,
            today,
            weekStart,
            labelW,
            dayW,
            rowH,
            color,
          ),
        ],
        // Separator between routines and tasks
        if (hasRoutines && pairs.isNotEmpty)
          SizedBox(
            width: totalW,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: labelW),
                  Expanded(
                    child: CustomPaint(
                      painter: _DashedLinePainter(
                          color: cs.outlineVariant.withOpacity(0.5)),
                      child: const SizedBox(height: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Task rows (Gantt bars)
        for (final pair in pairs) ...[
          _buildTaskBarRow(
            context,
            cs,
            pair.task,
            pair.project,
            today,
            weekStart,
            labelW,
            dayW,
            rowH,
            color,
          ),
        ],
      ],
    );
  }

  void _showColorPicker(
    BuildContext context,
    ProjectTask task,
    Project project,
    Offset globalPosition,
    Color currentColor,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String?>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String?>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Couleur de la barre',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Option "par défaut du domaine"
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onTaskColorChange(project, task, null);
                    },
                    child: Tooltip(
                      message: 'Couleur du domaine',
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                            colors: [Colors.grey, Colors.white],
                          ),
                        ),
                        child: const Icon(Icons.restart_alt, size: 14, color: Colors.grey),
                      ),
                    ),
                  ),
                  for (final c in kColorPickerOptions)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        final hex = '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
                        onTaskColorChange(project, task, hex);
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(6),
                          border: c.value == currentColor.value
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                          boxShadow: c.value == currentColor.value
                              ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 4)]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Ligne routine : cases à cocher par jour (cercle radio selon planification)
  Widget _buildRoutineRow(
    ColorScheme cs,
    RecurringAction routine,
    DateTime today,
    DateTime weekStart,
    double labelW,
    double dayW,
    double rowH,
    Color domainColor,
  ) {
    final todayN = DateTime(today.year, today.month, today.day);

    return SizedBox(
      height: rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label avec petit cercle domaine à gauche
          SizedBox(
            width: labelW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: domainColor.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      routine.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 7 day cells
          for (int d = 0; d < 7; d++) ...[
            _buildRoutineDayCell(
              cs,
              routine,
              weekStart.add(Duration(days: d)),
              todayN,
              dayW,
              rowH,
            ),
          ],
        ],
      ),
    );
  }

  /// Cellule jour pour une routine
  Widget _buildRoutineDayCell(
    ColorScheme cs,
    RecurringAction routine,
    DateTime day,
    DateTime todayN,
    double dayW,
    double rowH,
  ) {
    final cellDay = DateTime(day.year, day.month, day.day);

    // Divider vertical léger
    final divider = Positioned(
      left: 0,
      top: 4,
      bottom: 4,
      width: 1,
      child: Container(color: cs.outlineVariant.withOpacity(0.1)),
    );

    // Vérifier si la routine est planifiée ce jour
    bool isScheduled = false;
    bool daysUnknown = false;
    if (routine.type == RecurrenceType.daily) {
      isScheduled = true;
    } else if (routine.type == RecurrenceType.specificDays) {
      if (routine.weekdays.isEmpty) {
        // Jours non définis → afficher sur tous les jours avec indicateur "?"
        isScheduled = true;
        daysUnknown = true;
      } else {
        isScheduled = routine.weekdays.contains(cellDay.weekday);
      }
    }

    // Vérifier les bornes startDate/endDate
    if (isScheduled) {
      if (routine.startDate != null) {
        final s = DateTime(routine.startDate!.year, routine.startDate!.month, routine.startDate!.day);
        if (cellDay.isBefore(s)) isScheduled = false;
      }
      if (isScheduled && routine.endDate != null) {
        final e = DateTime(routine.endDate!.year, routine.endDate!.month, routine.endDate!.day);
        if (cellDay.isAfter(e)) isScheduled = false;
      }
    }

    if (!isScheduled) {
      return SizedBox(
        width: dayW,
        height: rowH,
        child: Stack(children: [divider]),
      );
    }

    final isToday = cellDay == todayN;
    final isPast = cellDay.isBefore(todayN);

    // Jours non définis → afficher "?" en orange sur toutes les cellules
    if (daysUnknown) {
      return SizedBox(
        width: dayW, height: rowH,
        child: Stack(children: [
          divider,
          Center(child: Text('?', style: TextStyle(fontSize: 11, color: Colors.orange.shade300, fontWeight: FontWeight.w600))),
        ]),
      );
    }

    IconData icon;
    Color iconColor;
    double opacity;
    double iconSize;

    if (isToday) {
      icon = Icons.radio_button_unchecked;
      iconColor = Colors.teal;
      opacity = 1.0;
      iconSize = 16;
    } else if (isPast) {
      icon = Icons.radio_button_unchecked;
      iconColor = Colors.red.shade300;
      opacity = 0.4;
      iconSize = 14;
    } else {
      // futur
      icon = Icons.radio_button_unchecked;
      iconColor = cs.onSurface.withOpacity(0.3);
      opacity = 0.5;
      iconSize = 14;
    }

    return SizedBox(
      width: dayW,
      height: rowH,
      child: Stack(
        children: [
          divider,
          Center(
            child: Opacity(
              opacity: opacity,
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Ligne tâche Gantt : barre horizontale
  Widget _buildTaskBarRow(
    BuildContext context,
    ColorScheme cs,
    ProjectTask task,
    Project project,
    DateTime today,
    DateTime weekStart,
    double labelW,
    double dayW,
    double rowH,
    Color domainColor,
  ) {
    final isDone = task.status == 'done';
    final weekEnd = weekStart.add(const Duration(days: 6));
    final totalDayW = dayW * 7;

    // Calcul position et largeur de la barre dans la semaine
    final effectiveEnd = task.endDate ?? task.startDate;
    final taskStart = DateTime(task.startDate.year, task.startDate.month, task.startDate.day);
    final taskEnd = DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day);
    final wStart = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final wEnd = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);

    // Clamp dans la semaine
    final barStart = taskStart.isBefore(wStart) ? wStart : taskStart;
    final barEnd = taskEnd.isAfter(wEnd) ? wEnd : taskEnd;

    // Offset en pixels depuis le début de la grille jour
    final startOffset = barStart.difference(wStart).inDays * dayW;
    final barDays = barEnd.difference(barStart).inDays + 1;
    final barWidth = barDays * dayW;

    final resolvedColor = _parseTaskColor(task.color) ?? domainColor;
    final barColor = isDone
        ? resolvedColor.withOpacity(0.35)
        : resolvedColor.withOpacity(0.75);

    return SizedBox(
      height: rowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label
          SizedBox(
            width: labelW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  if (isDone) ...[
                    Icon(Icons.check_circle,
                        size: 11, color: Colors.green.shade500),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(isDone ? 0.35 : 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Grille jour avec barre
          SizedBox(
            width: totalDayW,
            height: rowH,
            child: Stack(
              children: [
                // Séparateurs verticaux
                for (int d = 0; d < 7; d++)
                  Positioned(
                    left: d * dayW,
                    top: 4,
                    bottom: 4,
                    width: 1,
                    child: Container(color: cs.outlineVariant.withOpacity(0.1)),
                  ),

                // Jalon ◆
                if (task.isMilestone) ...[
                  Positioned(
                    left: startOffset + dayW / 2 - 6,
                    top: rowH / 2 - 6,
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isDone
                              ? Colors.green.shade600
                              : Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ] else if (barWidth > 0) ...[
                  // Barre horizontale — clic pour changer la couleur
                  Positioned(
                    left: startOffset,
                    top: rowH / 2 - 6,
                    width: barWidth,
                    height: 12,
                    child: GestureDetector(
                      onTapUp: (details) => _showColorPicker(
                        context,
                        task,
                        project,
                        details.globalPosition,
                        resolvedColor,
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── SIDEBAR ───────────────────────────────────────────────────────────────

  Widget _buildSidebar(
    BuildContext context,
    ColorScheme cs,
    DateTime today,
    DateTime weekStart,
    DateTime weekEnd,
    List<({ProjectTask task, Project project})> overduePairs,
    List<({ProjectTask task, Project project})> weekPairs,
    List<Project> allProjects,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card En retard ──────────────────────────────────────────────
          _SidebarCard(
            title: 'En retard',
            titleColor: cs.error,
            icon: Icons.warning_amber_rounded,
            cs: cs,
            child: overduePairs.isEmpty
                ? Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Aucun retard',
                        style: TextStyle(
                            fontSize: 13, color: Colors.green.shade600),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in overduePairs) ...[
                        _OverdueItem(
                            task: e.task, today: today, cs: cs),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // ── Card Cette semaine ──────────────────────────────────────────
          _SidebarCard(
            title: 'Cette semaine',
            icon: Icons.calendar_view_week_outlined,
            cs: cs,
            child: Builder(builder: (_) {
              // Count active (non-milestone, non-done/skipped) tasks per project
              final countByProject = <String, int>{};
              for (final e in weekPairs) {
                if (!e.task.isMilestone &&
                    e.task.status != 'done' &&
                    e.task.status != 'skipped') {
                  countByProject[e.project.id] =
                      (countByProject[e.project.id] ?? 0) + 1;
                }
              }
              if (countByProject.isEmpty) {
                return Text(
                  'Aucune tâche active',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.4),
                      fontStyle: FontStyle.italic),
                );
              }
              final entries = countByProject.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in entries) ...[
                    Builder(builder: (_) {
                      final proj = allProjects
                          .where((p) => p.id == entry.key)
                          .firstOrNull;
                      if (proj == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text('• ',
                                style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700)),
                            Expanded(
                              child: Text(
                                proj.title,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${entry.value} tâche${entry.value > 1 ? 's' : ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.5)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              );
            }),
          ),
          const SizedBox(height: 12),

          // ── Card Avancement ─────────────────────────────────────────────
          _SidebarCard(
            title: 'Avancement',
            titleColor: Colors.teal.shade700,
            icon: Icons.trending_up_outlined,
            cs: cs,
            child: allProjects.isEmpty
                ? Text(
                    'Aucun projet actif',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.4),
                        fontStyle: FontStyle.italic),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in allProjects) ...[
                        _ProjectProgressItem(
                          project: p,
                          domains: domains,
                          cs: cs,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => GanttScreen(
                                      project: p, domains: domains))),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          // ── ORION ───────────────────────────────────────────────────────
          _OrionSidebarSection(sync: sync, cs: cs),
        ],
      ),
    );
  }
}

// ── Peintre ligne pointillée ──────────────────────────────────────────────────

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ── Sidebar widgets ───────────────────────────────────────────────────────────

class _SidebarCard extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final IconData icon;
  final ColorScheme cs;
  final Widget child;

  const _SidebarCard({
    required this.title,
    required this.icon,
    required this.cs,
    required this.child,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = titleColor ?? cs.onSurface.withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _OverdueItem extends StatelessWidget {
  final ProjectTask task;
  final DateTime today;
  final ColorScheme cs;

  const _OverdueItem({
    required this.task,
    required this.today,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final daysLate = task.endDate != null
        ? today.difference(task.endDate!).inDays
        : 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            task.title,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '−$daysLate j',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.error,
          ),
        ),
      ],
    );
  }
}

class _ProjectProgressItem extends StatelessWidget {
  final Project project;
  final List<Domain> domains;
  final ColorScheme cs;
  final VoidCallback? onTap;

  const _ProjectProgressItem({
    required this.project,
    required this.domains,
    required this.cs,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = project.tasks.length;
    final done = project.tasks.where((t) => t.status == 'done').length;
    final progress = total > 0 ? done / total : 0.0;

    // Resolve domain color for progress bar
    final domain = project.domainId == null
        ? null
        : domains.where((d) => d.id == project.domainId).firstOrNull;
    Color barColor;
    if (domain != null) {
      if (domain.colorValue != null) {
        barColor = Color(domain.colorValue!);
      } else {
        final idx = domains.indexWhere((d) => d.id == domain.id);
        barColor = idx >= 0
            ? kDomainPalette[idx % kDomainPalette.length]
            : cs.primary;
      }
    } else {
      barColor = cs.primary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                project.title,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$done / $total',
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withOpacity(0.45)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          minHeight: 5,
          borderRadius: BorderRadius.circular(3),
          backgroundColor: cs.onSurface.withOpacity(0.08),
          color: barColor,
        ),
      ],
      ), // Column
    ); // InkWell
  }
}

// ── Objectif stratégique header ───────────────────────────────────────────────

class _ObjectiveHeader extends StatelessWidget {
  final StrategicObjective objective;
  const _ObjectiveHeader({required this.objective});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.flag_outlined, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            objective.title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.primary,
            ),
          ),
        ),
        if (objective.kpiTarget != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              objective.kpiTarget!,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.primary),
            ),
          ),
      ],
    );
  }
}

// ── Carte projet ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final Project project;
  final List<Domain> domains;
  final List<Map<String, dynamic>> documents;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final FirestoreSync sync;
  final VoidCallback? onDocumentDeleted;
  const _ProjectCard({
    required this.project,
    required this.domains,
    required this.documents,
    required this.onTap,
    required this.sync,
    this.onArchive,
    this.onDocumentDeleted,
  });

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin', 'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tasks = project.tasks;
    final done = tasks.where((t) => t.status == 'done').length;
    final total = tasks.length;
    final progress = total > 0 ? done / total : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _SourceBadge(source: project.sourceType),
                  if (onArchive != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.archive_outlined,
                          size: 16, color: cs.onSurface.withOpacity(0.35)),
                      tooltip: 'Mettre en veille',
                      visualDensity: VisualDensity.compact,
                      onPressed: onArchive,
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withOpacity(0.3)),
                ],
              ),
              if (project.description != null &&
                  project.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  project.description!,
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withOpacity(0.55)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              Builder(builder: (context) {
                final domain = project.domainId == null
                    ? null
                    : domains
                        .where((d) => d.id == project.domainId)
                        .firstOrNull;
                if (domain == null) return const SizedBox.shrink();
                final color = _WebHomeScreenState._domainColor(domain, cs, domains);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    domain.name,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13,
                      color: cs.onSurface.withOpacity(0.4)),
                  const SizedBox(width: 5),
                  Text(
                    '${_fmt(project.startDate)} → ${project.endDate != null ? _fmt(project.endDate!) : '—'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.5)),
                  ),
                  const Spacer(),
                  if (total > 0)
                    Text(
                      '$done / $total tâches',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(0.45)),
                    ),
                ],
              ),
              if (total > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: cs.onSurface.withOpacity(0.07),
                  color: cs.primary,
                ),
              ],
              if (documents.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(
                      Icons.description_outlined,
                      size: 14,
                      color: cs.primary.withOpacity(0.7),
                    ),
                    label: Text(
                      documents.length == 1 ? 'Voir le programme' : 'Voir les programmes (${documents.length})',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.primary.withOpacity(0.7),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        builder: (_) => _DocumentViewerDialog(
                          projectTitle: project.title,
                          documents: documents,
                          sync: sync,
                          onDeleted: onDocumentDeleted,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section En veille ─────────────────────────────────────────────────────────

class _ArchivedSection extends StatefulWidget {
  final List<Project> projects;
  final void Function(Project) onRestore;
  final void Function(Project) onTap;
  final void Function(Project) onDelete;
  const _ArchivedSection({
    required this.projects,
    required this.onRestore,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ArchivedSection> createState() => _ArchivedSectionState();
}

class _ArchivedSectionState extends State<_ArchivedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: cs.onSurface.withOpacity(0.4)),
                const SizedBox(width: 8),
                Icon(Icons.archive_outlined,
                    size: 14, color: cs.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Text(
                  'En veille (${widget.projects.length})',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.45)),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          for (final p in widget.projects) ...[
            _ArchivedProjectCard(
              project: p,
              onRestore: () => widget.onRestore(p),
              onTap: () => widget.onTap(p),
              onDelete: () => widget.onDelete(p),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _ArchivedProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onRestore;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ArchivedProjectCard({
    required this.project,
    required this.onRestore,
    required this.onTap,
    required this.onDelete,
  });

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.archive_outlined,
                  size: 16, color: cs.onSurface.withOpacity(0.3)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(0.5))),
                    if (project.endDate != null)
                      Text('jusqu\'au ${_fmt(project.endDate!)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(0.3))),
                  ],
                ),
              ),
              TextButton.icon(
                icon: Icon(Icons.unarchive_outlined, size: 14,
                    color: cs.primary.withOpacity(0.7)),
                label: Text('Réactiver',
                    style: TextStyle(
                        fontSize: 12, color: cs.primary.withOpacity(0.7))),
                onPressed: onRestore,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
              TextButton.icon(
                icon: Icon(Icons.delete_outline, size: 14,
                    color: cs.error.withOpacity(0.7)),
                label: Text('Supprimer',
                    style: TextStyle(
                        fontSize: 12, color: cs.error.withOpacity(0.7))),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Supprimer définitivement ?'),
                      content: Text(
                        'Le projet "${project.title}" sera supprimé définitivement. Cette action est irréversible.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: cs.error),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) onDelete();
                },
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dialog visualisation documents ───────────────────────────────────────────

class _DocumentViewerDialog extends StatefulWidget {
  final String projectTitle;
  final List<Map<String, dynamic>> documents;
  final FirestoreSync sync;
  final VoidCallback? onDeleted;

  const _DocumentViewerDialog({
    required this.projectTitle,
    required this.documents,
    required this.sync,
    this.onDeleted,
  });

  @override
  State<_DocumentViewerDialog> createState() => _DocumentViewerDialogState();
}

class _DocumentViewerDialogState extends State<_DocumentViewerDialog> {
  int _selectedIndex = 0;
  late List<Map<String, dynamic>> _docs;

  @override
  void initState() {
    super.initState();
    _docs = List.of(widget.documents);
  }

  Map<String, dynamic> get _current => _docs[_selectedIndex];

  Future<void> _deleteDocument() async {
    final doc = _current;
    final docId = doc['id'] as String?;
    if (docId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text('"${doc['title'] ?? 'Document'}" sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.sync.hardDelete('documents', docId);
    widget.onDeleted?.call();

    if (_docs.length == 1) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _docs.removeAt(_selectedIndex);
      if (_selectedIndex >= _docs.length) _selectedIndex = _docs.length - 1;
    });
  }

  void _download() {
    final title = _current['title'] as String? ?? 'document';
    final htmlContent = _current['content'] as String? ?? '';
    final content = htmlContent.contains('<html')
        ? htmlContent
        : '<html><head><meta charset="utf-8"></head><body>$htmlContent</body></html>';
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrl(blob);
    final filename =
        '${title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_')}.html';
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasMultiple = _docs.length > 1;
    final title = _current['title'] as String? ?? 'Document';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          children: [
            // AppBar-like header
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
                border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.4)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasMultiple
                          ? '${widget.projectTitle} — $title'
                          : title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.download_outlined,
                        size: 18, color: cs.onSurface.withOpacity(.6)),
                    tooltip: 'Télécharger (.html)',
                    onPressed: _download,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: cs.onSurface.withOpacity(.45)),
                    tooltip: 'Supprimer ce document',
                    onPressed: _deleteDocument,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_outlined, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Row(
                children: [
                  // Sidebar list (only when multiple docs)
                  if (hasMultiple) ...[
                    Container(
                      width: 200,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                              color: cs.outlineVariant.withOpacity(0.4)),
                        ),
                      ),
                      child: ListView.builder(
                        itemCount: _docs.length,
                        itemBuilder: (_, i) {
                          final doc = _docs[i];
                          final docTitle =
                              doc['title'] as String? ?? 'Document ${i + 1}';
                          final isSelected = i == _selectedIndex;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            selectedTileColor:
                                cs.primaryContainer.withOpacity(0.4),
                            leading: Icon(
                              Icons.article_outlined,
                              size: 16,
                              color: isSelected
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.5),
                            ),
                            title: Text(
                              docTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurface,
                              ),
                            ),
                            onTap: () =>
                                setState(() => _selectedIndex = i),
                          );
                        },
                      ),
                    ),
                  ],

                  // HTML content viewer
                  Expanded(
                    child: _HtmlDocViewer(
                      key: ValueKey(_current['id'] ?? _selectedIndex),
                      documentId:
                          _current['id'] as String? ?? 'doc-$_selectedIndex',
                      htmlContent: _current['content'] as String? ?? '',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget rendu HTML via iframe ──────────────────────────────────────────────

class _HtmlDocViewer extends StatefulWidget {
  final String documentId;
  final String htmlContent;

  const _HtmlDocViewer({
    super.key,
    required this.documentId,
    required this.htmlContent,
  });

  @override
  State<_HtmlDocViewer> createState() => _HtmlDocViewerState();
}

class _HtmlDocViewerState extends State<_HtmlDocViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'html-doc-${widget.documentId}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) {
      final iframe = html.IFrameElement()
        ..srcdoc = widget.htmlContent
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}

// ── Badge source ──────────────────────────────────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon) = switch (source) {
      'claude_api' => ('Claude', Icons.auto_awesome_outlined),
      'coach' => ('Coach', Icons.person_outlined),
      _ => ('Manuel', Icons.edit_outlined),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer)),
        ],
      ),
    );
  }
}

// ── Panel Connecter Claude / Tokens ──────────────────────────────────────────

class _TokensPanel extends StatefulWidget {
  final FirestoreSync sync;
  const _TokensPanel({required this.sync});

  @override
  State<_TokensPanel> createState() => _TokensPanelState();
}

class _TokensPanelState extends State<_TokensPanel>
    with SingleTickerProviderStateMixin {
  List<ApiToken> _tokens = [];
  bool _loading = true;
  String? _newTokenValue;
  late TabController _tabs;

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tokens = await widget.sync.fetchApiTokens();
    if (!mounted) return;
    setState(() {
      _tokens = tokens;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final label = await _askLabel();
    if (label == null) return;
    final token = await widget.sync.createApiToken(label);
    if (!mounted) return;
    setState(() => _newTokenValue = token.token);
    await _load();
  }

  Future<String?> _askLabel() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau token'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'ex: Claude MCP',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  String _mcpUrl(String token) =>
      'https://productivitwo-app.web.app/mcp/$_uid/$token';

  String _mcpConfig(String token) => '''{
  "mcpServers": {
    "productivitwo": {
      "url": "${_mcpUrl(token)}"
    }
  }
}''';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeTokens = _tokens.where((t) => t.active).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          // Titre
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Connecter Claude',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Connexion Claude Desktop'),
              Tab(text: 'Mes tokens'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                // ── Onglet 1 : Connexion ──────────────────────────────────
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Étapes
                          _Step(
                            number: '1',
                            title: 'Génère un token',
                            child: activeTokens.isEmpty
                                ? FilledButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Créer un token Claude'),
                                    onPressed: () async {
                                      await _create();
                                      _tabs.animateTo(0);
                                    },
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Token actif : ${activeTokens.first.label}',
                                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
                                      const SizedBox(height: 6),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Créer un autre token'),
                                        onPressed: _create,
                                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _Step(
                            number: '2',
                            title: 'Copie ton URL de connexion',
                            child: activeTokens.isEmpty
                                ? Text('Crée d\'abord un token (étape 1)',
                                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.45),
                                        fontStyle: FontStyle.italic))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // URL principale (simple)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer.withOpacity(0.4),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: cs.primary.withOpacity(0.25)),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: SelectableText(
                                                _mcpUrl(activeTokens.first.token),
                                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy_outlined, size: 16),
                                              onPressed: () => _copy(_mcpUrl(activeTokens.first.token), 'URL copiée'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      // Option A : Claude.ai web
                                      _ConnectOption(
                                        icon: Icons.language_outlined,
                                        title: 'Claude.ai web',
                                        description: 'Paramètres → Personnaliser → Connecteurs → colle l\'URL',
                                      ),
                                      const SizedBox(height: 8),
                                      // Option B : Claude Desktop
                                      _ConnectOption(
                                        icon: Icons.desktop_mac_outlined,
                                        title: 'Claude Desktop',
                                        description: 'Paramètres → Développeur → Modifier la config → colle le JSON ci-dessous',
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: SelectableText(
                                                _mcpConfig(activeTokens.first.token),
                                                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.copy_outlined, size: 14),
                                              onPressed: () => _copy(_mcpConfig(activeTokens.first.token), 'Config copiée'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _Step(
                            number: '3',
                            title: 'Parle à Claude',
                            child: Text(
                              'Dis à Claude : "Crée un Gantt pour [description de ton projet]" '
                              'et il le poussera directement dans Productivitwo.',
                              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.65), height: 1.5),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Note token visible
                          if (_newTokenValue != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Token créé (visible une seule fois)',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                                        SelectableText(_newTokenValue!,
                                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_outlined, size: 14),
                                    onPressed: () => _copy(_newTokenValue!, 'Token copié'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                // ── Onglet 2 : Tokens ─────────────────────────────────────
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Tokens actifs',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withOpacity(0.6))),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Nouveau'),
                            onPressed: _create,
                            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : activeTokens.isEmpty
                              ? Center(
                                  child: Text('Aucun token actif',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.4))))
                              : ListView.builder(
                                  itemCount: activeTokens.length,
                                  itemBuilder: (_, i) {
                                    final t = activeTokens[i];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(Icons.key_outlined, size: 16, color: cs.primary),
                                      title: Text(t.label, style: const TextStyle(fontSize: 13)),
                                      subtitle: Text(
                                        t.lastUsedAt != null
                                            ? 'Utilisé le ${t.lastUsedAt!.day}/${t.lastUsedAt!.month}'
                                            : 'Jamais utilisé',
                                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4)),
                                      ),
                                      trailing: TextButton(
                                        child: Text('Révoquer', style: TextStyle(color: cs.error, fontSize: 12)),
                                        onPressed: () async {
                                          await widget.sync.revokeApiToken(t.id);
                                          _load();
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget étape numérotée ────────────────────────────────────────────────────

class _ConnectOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _ConnectOption({required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurface.withOpacity(0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.65), height: 1.4),
              children: [
                TextSpan(text: '$title — ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final String title;
  final Widget child;
  const _Step({required this.number, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Vue Archives ─────────────────────────────────────────────────────────────

class _ArchivesView extends StatefulWidget {
  final FirestoreSync sync;
  const _ArchivesView({required this.sync});

  @override
  State<_ArchivesView> createState() => _ArchivesViewState();
}

class _ArchivesViewState extends State<_ArchivesView> {
  List<Domain> _domains = [];
  List<Activity> _activities = [];
  List<RecurringAction> _routines = [];
  List<Project> _projects = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _search = '';
  // Filtre : 'all' | 'active' | 'archived'
  String _filter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.sync.fetchAllDomains(),
        widget.sync.fetchActivities(),
        widget.sync.fetchRoutines(),
        widget.sync.fetchProjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _domains    = results[0] as List<Domain>;
        _activities = results[1] as List<Activity>;
        _routines   = results[2] as List<RecurringAction>;
        _projects   = results[3] as List<Project>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _archive(String col, String id) async {
    await widget.sync.archiveItem(col, id);
    _load();
  }

  Future<void> _restore(String col, String id) async {
    await widget.sync.restoreDeleted(col, id);
    _load();
  }

  Future<void> _confirmHardDelete(String col, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text(
          'L\'élément sera masqué partout (app iOS + web).\n\n'
          'Note : si l\'élément existe encore localement sur iOS, '
          'il sera supprimé au prochain démarrage de l\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.sync.hardDelete(col, id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    // ── Données avec filtres ─────────────────────────────────────────────────
    final q = _search.toLowerCase().trim();

    bool matchesSearch(String name) =>
        q.isEmpty || name.toLowerCase().contains(q);

    bool showActive(bool isArchived) =>
        _filter == 'all' || (_filter == 'active' && !isArchived) || (_filter == 'archived' && isArchived);

    final archivedProjects = _projects
        .where((p) => p.status == 'archived' && matchesSearch(p.title) && showActive(true))
        .toList()..sort((a, b) => a.title.compareTo(b.title));
    final activeProjects = _projects
        .where((p) => p.status != 'archived' && matchesSearch(p.title) && showActive(false))
        .toList()..sort((a, b) => a.title.compareTo(b.title));

    // Domaines actifs + archivés triés
    final activeDomains = _domains
        .where((d) => !d.deleted && showActive(false))
        .toList()..sort((a, b) => a.name.compareTo(b.name));
    final archivedDomains = _domains
        .where((d) => d.deleted && showActive(true))
        .toList()..sort((a, b) => a.name.compareTo(b.name));
    final allDomains = [...activeDomains, ...archivedDomains];

    // Activités et routines (filtrées)
    final filteredActivities = _activities
        .where((a) => matchesSearch(a.name) && showActive(a.deleted))
        .toList();
    final filteredRoutines = _routines
        .where((r) => matchesSearch(r.title) && showActive(r.deleted))
        .toList();

    // Activités et routines indexées
    final activitiesByDomain = <String, List<Activity>>{};
    final activitiesWithoutDomain = <Activity>[];
    for (final a in filteredActivities) {
      if (a.domainId.isEmpty) {
        activitiesWithoutDomain.add(a);
      } else {
        activitiesByDomain.putIfAbsent(a.domainId, () => []).add(a);
      }
    }
    final routinesByActivity = <String, List<RecurringAction>>{};
    final routinesWithoutActivity = <RecurringAction>[];
    for (final r in filteredRoutines) {
      if (r.activityId == null || r.activityId!.isEmpty) {
        routinesWithoutActivity.add(r);
      } else {
        routinesByActivity.putIfAbsent(r.activityId!, () => []).add(r);
      }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: cs.onSurface.withOpacity(0.45),
            ),
          ),
        );

    Widget domainHeader(Domain d) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: d.deleted ? cs.error.withOpacity(0.5) : cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              d.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: d.deleted ? cs.error.withOpacity(0.6) : cs.primary,
              ),
            ),
            if (d.deleted) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('archivé',
                    style: TextStyle(fontSize: 10, color: cs.error)),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
            IconButton(
              icon: Icon(d.deleted ? Icons.restore_outlined : Icons.archive_outlined,
                  size: 15, color: cs.onSurface.withOpacity(0.4)),
              tooltip: d.deleted ? 'Restaurer' : 'Archiver',
              visualDensity: VisualDensity.compact,
              onPressed: d.deleted
                  ? () => _restore('domains', d.id)
                  : () => _archive('domains', d.id),
            ),
          ]),
        );

    List<Widget> buildActivityBlock(Activity a) {
      final routines = (routinesByActivity[a.id] ?? [])
        ..sort((x, y) => x.title.compareTo(y.title));
      return [
        // Activité
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 6),
          child: _ArchiveItemRow(
            label: a.name,
            isArchived: a.deleted,
            subtitle: a.isHabit ? 'Routine' : 'Activité temps',
            onArchive: () => _archive('activities', a.id),
            onRestore: () => _restore('activities', a.id),
            onDelete: () => _confirmHardDelete('activities', a.id),
            cs: cs,
          ),
        ),
        // Routines de cette activité
        for (final r in routines)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: _ArchiveItemRow(
              label: r.title,
              isArchived: r.deleted,
              onArchive: () => _archive('recurringActions', r.id),
              onRestore: () => _restore('recurringActions', r.id),
              onDelete: () => _confirmHardDelete('recurringActions', r.id),
              cs: cs,
            ),
          ),
        if (routines.isNotEmpty) const SizedBox(height: 4),
      ];
    }

    // ── Rendu ────────────────────────────────────────────────────────────────
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            // En-tête
            Row(children: [
              sectionLabel('ARCHIVES'),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_outlined, size: 14),
                label: const Text('Rafraîchir'),
                onPressed: _load,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ]),
            // Barre de recherche
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Rechercher…',
                prefixIcon: const Icon(Icons.search_outlined, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
            const SizedBox(height: 8),
            // Filtres actif / archivé / tout
            Row(children: [
              for (final (val, label) in [
                ('all',      'Tout'),
                ('active',   'Actifs'),
                ('archived', 'Archivés'),
              ]) ...[
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _filter == val,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = val),
                ),
                const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 16),

            // ── PROJETS ─────────────────────────────────────────────────────
            sectionLabel('PROJETS (${activeProjects.length + archivedProjects.length})'),
            if (activeProjects.isEmpty && archivedProjects.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Aucun projet',
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic)),
              )
            else ...[
              if (activeProjects.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Actifs', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                ),
                for (final p in activeProjects) ...[
                  _ArchiveItemRow(
                    label: p.title,
                    isArchived: false,
                    subtitle: () {
                      final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                      return d != null ? d.name : null;
                    }(),
                    onArchive: () async {
                      await widget.sync.saveProject(p..status = 'archived');
                      _load();
                    },
                    onRestore: () async {},
                    cs: cs,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
              if (archivedProjects.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Archivés', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                ),
                for (final p in archivedProjects) ...[
                  _ArchiveItemRow(
                    label: p.title,
                    isArchived: true,
                    subtitle: () {
                      final d = _domains.where((d) => d.id == p.domainId).firstOrNull;
                      return d != null ? d.name : null;
                    }(),
                    onArchive: () async {},
                    onRestore: () async {
                      await widget.sync.saveProject(p..status = 'active');
                      _load();
                    },
                    cs: cs,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── ACTIVITÉS & ROUTINES par domaine ─────────────────────────────
            sectionLabel('ACTIVITÉS & ROUTINES PAR DOMAINE'),

            for (final d in allDomains) ...[
              domainHeader(d),
              if ((activitiesByDomain[d.id] ?? []).isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text('Aucune activité dans ce domaine',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.35), fontStyle: FontStyle.italic)),
                )
              else
                for (final a in [...(activitiesByDomain[d.id] ?? [])
                    ..sort((x, y) => x.name.compareTo(y.name))])
                  ...buildActivityBlock(a),
              const SizedBox(height: 4),
            ],

            // Sans domaine
            if (activitiesWithoutDomain.isNotEmpty || routinesWithoutActivity.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                child: Row(children: [
                  Container(width: 8, height: 8,
                      decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.3), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('SANS DOMAINE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: cs.onSurface.withOpacity(0.4))),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.3))),
                ]),
              ),
              for (final a in activitiesWithoutDomain..sort((x, y) => x.name.compareTo(y.name)))
                ...buildActivityBlock(a),
              for (final r in routinesWithoutActivity..sort((x, y) => x.title.compareTo(y.title)))
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: _ArchiveItemRow(
                    label: r.title,
                    isArchived: r.deleted,
                    onArchive: () => _archive('recurringActions', r.id),
                    onRestore: () => _restore('recurringActions', r.id),
                    onDelete: () => _confirmHardDelete('recurringActions', r.id),
                    cs: cs,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Vue ORION ─────────────────────────────────────────────────────────────────

class _OrionView extends StatefulWidget {
  final FirestoreSync sync;
  const _OrionView({required this.sync});

  @override
  State<_OrionView> createState() => _OrionViewState();
}

class _OrionViewState extends State<_OrionView> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _config;
  int _runCount = 0;
  bool _loading = true;
  bool _triggering = false;
  final _customCtrl = TextEditingController();

  static const _webhookUrl = 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';

  // Actions pré-établies
  // taskId non vide = déterministe ($0), need non vide = LLM (coût API)
  static const _presets = [
    (icon: '📋', label: 'Analyser mes retards',       taskId: 'overdue_summary',  need: ''),
    (icon: '📅', label: 'Deadlines de la semaine',    taskId: 'weekly_deadlines', need: ''),
    (icon: '🗄', label: 'Archiver projets inactifs',  taskId: 'archive_inactive', need: ''),
    (icon: '📊', label: 'Rapport de progression',     taskId: 'progress_report',  need: ''),
    (icon: '🧹', label: 'Nettoyer messages expirés',  taskId: 'clean_expired',    need: ''),
    (icon: '🎯', label: 'Bilan de semaine',            taskId: '',  need: 'Fais un bilan de ma semaine et propose des ajustements pour la suivante'),
    (icon: '⚡', label: 'Optimiser plan du jour',     taskId: '',  need: 'Optimise mon plan du jour en fonction de mes priorités et deadlines'),
    (icon: '🔗', label: 'Lier objectifs et tâches',   taskId: '',  need: 'Lie mes objectifs GTD aux tâches Gantt correspondantes'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = widget.sync.uid;
      if (uid == null) return;

      final tokens = await widget.sync.fetchApiTokens();
      final token = tokens.where((t) => t.active).firstOrNull?.token ?? '';

      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users/$uid/orion_logs')
            .orderBy('cycleAt', descending: true)
            .limit(15)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/assistant_messages')
            .orderBy('targetDate', descending: true)
            .limit(30)
            .get(),
        FirebaseFirestore.instance
            .collection('users/$uid/orion_config')
            .doc('main')
            .get(),
        // Compteur via HTTP (orion_runs est hors users/{uid}, règles Firestore restrictives)
        if (token.isNotEmpty)
          http.get(Uri.parse('https://orionruncount-dzos75b65q-uc.a.run.app?uid=$uid&token=$token'))
        else
          Future.value(null),
      ]);

      final logsSnap = results[0] as QuerySnapshot;
      final msgsSnap = results[1] as QuerySnapshot;
      final configSnap = results[2] as DocumentSnapshot;
      final countResp = results[3];

      int runCount = 0;
      if (countResp is http.Response && countResp.statusCode == 200) {
        final data = jsonDecode(countResp.body) as Map<String, dynamic>;
        runCount = (data['count'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _logs = logsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          _messages = msgsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          _config = configSnap.exists ? configSnap.data() as Map<String, dynamic> : null;
          _runCount = runCount;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerWithPreset({required String taskId, required String need}) async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.token;
    if (uid == null || token == null) return;

    final isDeterministic = taskId.isNotEmpty;
    setState(() => _triggering = true);
    try {
      final body = isDeterministic
          ? {'uid': uid, 'token': token, 'taskId': taskId}
          : {'uid': uid, 'token': token, 'userNeeds': need};
      final url = isDeterministic
          ? 'https://orionwebhook-dzos75b65q-uc.a.run.app'
          : _webhookUrl;
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200 && mounted) {
        final label = isDeterministic ? taskId : need.substring(0, need.length.clamp(0, 40));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isDeterministic ? 'Tâche ORION exécutée : $label' : 'ORION activé (LLM) : $label…'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  Future<void> _triggerNow() async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.token;
    if (uid == null || token == null) return;

    setState(() => _triggering = true);
    try {
      final resp = await http.post(
        Uri.parse('https://orionwebhook-dzos75b65q-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cycle ORION déclenché'), behavior: SnackBarBehavior.floating),
        );
        await Future.delayed(const Duration(seconds: 2));
        _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _triggering = false);
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate() as DateTime;
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final pendingMsgs = _messages.where((m) => m['status'] == 'pending').toList();
    final shownMsgs = _messages.where((m) => m['status'] == 'shown').toList();
    final otherMsgs = _messages.where((m) => m['status'] != 'pending' && m['status'] != 'shown').toList();

    Widget sectionLabel(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 1.1, color: cs.onSurface.withOpacity(0.45))),
        );

    Widget msgChip(String status) {
      final colors = {
        'pending': Colors.blue,
        'shown': Colors.green,
        'dismissed': Colors.orange,
        'expired': Colors.grey,
      };
      final c = colors[status] ?? Colors.grey;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(status, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
          children: [
            // ── En-tête ──────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                child: Icon(Icons.smart_toy_outlined, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Agent ORION', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('$_runCount / 50 activations aujourd\'hui',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5))),
              ]),
              const SizedBox(width: 12),
              // Badge plan tarifaire
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Gratuit ', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7))),
                    TextSpan(text: '∞', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                    TextSpan(text: '  ·  Pro ', style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5))),
                    TextSpan(text: '5/j', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.7))),
                  ]),
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_outlined, size: 14),
                label: const Text('Rafraîchir'),
                onPressed: _load,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _triggering
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow_outlined, size: 16),
                label: const Text('Déclencher'),
                onPressed: _triggering ? null : _triggerNow,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _runCount / 50,
                minHeight: 4,
                backgroundColor: cs.onSurface.withOpacity(0.08),
                color: _runCount >= 50 ? cs.error : cs.primary,
              ),
            ),

            // ── Comment ça marche ────────────────────────────────────────
            const SizedBox(height: 20),
            const _OrionHowItWorksCard(),

            // ── Config actuelle ───────────────────────────────────────────
            if (_config != null) ...[
              const SizedBox(height: 24),
              sectionLabel('INSTRUCTIONS ACTUELLES'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((_config!['userNeeds'] as String? ?? '').isNotEmpty) ...[
                    Text('Besoins :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 4),
                    Text(_config!['userNeeds'] as String, style: const TextStyle(fontSize: 14)),
                  ],
                  if ((_config!['userReply'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Dernière réponse (${_config!['replyTimestamp'] ?? ''}) :',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.5))),
                    const SizedBox(height: 4),
                    Text(_config!['userReply'] as String,
                        style: TextStyle(fontSize: 14, color: cs.primary)),
                  ],
                ]),
              ),
            ],

            // ── Actions pré-établies ─────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('ACTIONS RAPIDES'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) => ActionChip(
                avatar: Text(p.icon, style: const TextStyle(fontSize: 14)),
                label: Text(p.label, style: const TextStyle(fontSize: 13)),
                backgroundColor: p.taskId.isNotEmpty
                    ? Colors.green.withOpacity(0.08)
                    : cs.surfaceContainerHighest.withOpacity(0.5),
                side: p.taskId.isNotEmpty
                    ? BorderSide(color: Colors.green.withOpacity(0.3))
                    : null,
                onPressed: _triggering ? null : () => _triggerWithPreset(taskId: p.taskId, need: p.need),
              )).toList(),
            ),

            // ── Demande libre ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('DEMANDE LIBRE'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _customCtrl,
                    enabled: !_triggering,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ex : Crée un projet "Lancement produit" avec 3 phases, analyse mes retards…',
                      hintStyle: TextStyle(
                          fontSize: 13, color: cs.onSurface.withOpacity(.4)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isEmpty) return;
                      _triggerWithPreset(taskId: '', need: t);
                      _customCtrl.clear();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: _triggering
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Envoyer'),
                  onPressed: _triggering
                      ? null
                      : () {
                          final t = _customCtrl.text.trim();
                          if (t.isEmpty) return;
                          _triggerWithPreset(taskId: '', need: t);
                          _customCtrl.clear();
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),

            // ── Logs des cycles récents ───────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('CYCLES RÉCENTS (${_logs.length})'),
            if (_logs.isEmpty)
              Text('Aucun cycle enregistré',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic))
            else
              for (final log in _logs) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    title: Row(children: [
                      Text(_fmtTs(log['cycleAt']),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                      const SizedBox(width: 10),
                      if (log['skipped'] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: cs.errorContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(4)),
                          child: Text('skippé', style: TextStyle(fontSize: 10, color: cs.error)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${log['pushed'] ?? 0} message(s)', style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    subtitle: (log['userNeeds'] as String? ?? '').isNotEmpty
                        ? Text('"${(log['userNeeds'] as String).substring(0, ((log['userNeeds'] as String).length).clamp(0, 60))}…"',
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    children: [
                      if (log['skipped'] == true && log['skippedReason'] != null)
                        Text(log['skippedReason'] as String,
                            style: TextStyle(fontSize: 13, color: cs.error)),
                      for (final action in (log['actions'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $action', style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
              ],

            // ── Messages ORION ────────────────────────────────────────────
            const SizedBox(height: 24),
            sectionLabel('MESSAGES ORION (${_messages.length})'),
            if (_messages.isEmpty)
              Text('Aucun message',
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4), fontStyle: FontStyle.italic))
            else
              for (final group in [
                ('EN ATTENTE', pendingMsgs),
                ('AFFICHÉS', shownMsgs),
                ('AUTRES', otherMsgs),
              ]) ...[
                if ((group.$2).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(group.$1,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            letterSpacing: 0.8, color: cs.onSurface.withOpacity(0.4))),
                  ),
                  for (final msg in group.$2)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(left: BorderSide(color: cs.primary.withOpacity(0.4), width: 3)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(msg['text'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(msg['targetDate'] as String? ?? '',
                                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.45))),
                              const SizedBox(width: 8),
                              Text('condition: ${(msg['condition'] as Map?)?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? ''}',
                                  style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.4))),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        msgChip(msg['status'] as String? ?? ''),
                      ]),
                    ),
                ],
              ],
          ],
        ),
      ),
    );
  }
}

// ── Ligne d'un item dans la vue Archives ─────────────────────────────────────

class _ArchiveItemRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool isArchived;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDelete;
  final ColorScheme cs;

  const _ArchiveItemRow({
    required this.label,
    required this.isArchived,
    required this.onArchive,
    required this.onRestore,
    required this.cs,
    this.subtitle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isArchived
        ? cs.errorContainer.withOpacity(0.2)
        : cs.surfaceContainerHighest.withOpacity(0.3);
    final borderColor = isArchived
        ? cs.error.withOpacity(0.25)
        : cs.outlineVariant.withOpacity(0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ● bullet
          Text(
            '●',
            style: TextStyle(
              fontSize: 10,
              color: isArchived
                  ? cs.error.withOpacity(0.6)
                  : Colors.green.shade600,
            ),
          ),
          const SizedBox(width: 10),
          // Nom + sous-titre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Badge statut
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isArchived
                  ? cs.errorContainer
                  : Colors.green.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isArchived ? 'Archivé' : 'Actif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isArchived
                    ? cs.error
                    : Colors.green.shade800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Boutons d'action
          if (!isArchived) ...[
            OutlinedButton(
              onPressed: onArchive,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade800,
                side: BorderSide(color: Colors.amber.shade600),
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Archiver'),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: onRestore,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade700,
                side: BorderSide(color: Colors.green.shade400),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Restaurer'),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  foregroundColor: cs.error,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Dialog liaison compte iOS ─────────────────────────────────────────────────

class _LinkIosDialog extends StatefulWidget {
  final VoidCallback onLinked;
  const _LinkIosDialog({required this.onLinked});

  @override
  State<_LinkIosDialog> createState() => _LinkIosDialogState();
}

class _LinkIosDialogState extends State<_LinkIosDialog> {
  final _uidCtrl   = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _customTokenUrl =
      'https://getcustomtoken-dzos75b65q-uc.a.run.app';

  @override
  void dispose() {
    _uidCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final uid   = _uidCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (uid.isEmpty || token.isEmpty) {
      setState(() => _error = 'UID et token requis');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse(_customTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uid': uid, 'token': token}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        throw Exception(body['error'] ?? 'Erreur (${res.statusCode})');
      }
      final customToken = body['customToken'] as String?;
      if (customToken == null) throw Exception('Token Firebase manquant');

      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      if (mounted) Navigator.pop(context);
      widget.onLinked();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.link_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Connecter mon compte iOS',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Ouvre Productivitwo iOS → menu ⋮ → Tokens API\n'
                '2. Copie ton UID (en haut) et génère un token\n'
                '3. Colle-les ici',
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(0.6),
                    height: 1.5),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style:
                          TextStyle(fontSize: 12, color: cs.onErrorContainer)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _uidCtrl,
                decoration: const InputDecoration(
                  labelText: 'UID iOS',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Token',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _link,
                child: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Comment ça marche — ORION ─────────────────────────────────────────────────

class _OrionHowItWorksCard extends StatefulWidget {
  const _OrionHowItWorksCard();

  @override
  State<_OrionHowItWorksCard> createState() => _OrionHowItWorksCardState();
}

class _OrionHowItWorksCardState extends State<_OrionHowItWorksCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          // ── Header cliquable ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded,
                      size: 16, color: cs.primary.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Text(
                    'Comment ça marche ?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu ──────────────────────────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Schéma 3 acteurs
                  LayoutBuilder(builder: (ctx, constraints) {
                    final narrow = constraints.maxWidth < 600;
                    final actors = [
                      _OrionActor(
                        icon: '✦',
                        iconColor: const Color(0xFF6366f1),
                        title: 'Claude',
                        subtitle: 'claude.ai · Claude Desktop',
                        description:
                            'Tu lui parles en langage naturel. Via MCP, il lit et modifie tes données directement : crée des projets, planifie tes journées, gère tes objectifs.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '◉',
                        iconColor: const Color(0xFF10b981),
                        title: 'ORION',
                        subtitle: 'Agent autonome · toutes les 6h',
                        description:
                            'Tourne en arrière-plan sans que tu aies à lui demander. Il analyse ton contexte, détecte tes retards et te pousse des messages actionnables sur iOS.',
                        cs: cs,
                      ),
                      _OrionActor(
                        icon: '⬡',
                        iconColor: const Color(0xFF8b5cf6),
                        title: 'App web',
                        subtitle: 'Projets · Documents · Pilotage',
                        description:
                            'Ton tableau de bord Gantt. Tu peux aussi déclencher ORION manuellement, voir ses logs et configurer ses instructions depuis ici.',
                        cs: cs,
                      ),
                    ];

                    return narrow
                        ? Column(
                            children: actors
                                .map((a) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: a,
                                    ))
                                .toList(),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: actors[0]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[1]),
                              _Arrow(cs: cs),
                              Expanded(child: actors[2]),
                            ],
                          );
                  }),

                  const SizedBox(height: 20),

                  // Firestore — socle commun
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf97316).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFf97316).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Text('🗄', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Firestore — tes données, partagées en temps réel',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withOpacity(0.8),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Domaines · Activités · Projets Gantt · Plan du jour · Messages ORION',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withOpacity(0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Flux en 4 étapes
                  Text(
                    'Le flux en pratique',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(0.55),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final step in [
                    ('1', 'Tu configures tes données',
                        'Depuis l\'app iOS ou en demandant à Claude de le faire.'),
                    ('2', 'ORION analyse toutes les 6h',
                        'Il lit ton contexte complet et génère 1 à 3 messages ciblés.'),
                    ('3', 'Tu reçois une notification push',
                        'Le message apparaît dans l\'app iOS avec une action directe.'),
                    ('4', 'Tu peux aussi déclencher manuellement',
                        'Via les actions rapides ci-dessous ou en activant depuis iOS.'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(top: 1, right: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              step.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.$2,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(step.$3,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            cs.onSurface.withOpacity(0.5))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrionActor extends StatelessWidget {
  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;
  final ColorScheme cs;

  const _OrionActor({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon,
                style: TextStyle(
                    fontSize: 16,
                    color: iconColor,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 10,
                  color: iconColor.withOpacity(0.8),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(description,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.55),
                  height: 1.5)),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final ColorScheme cs;
  const _Arrow({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: Icon(Icons.sync_alt_rounded,
          size: 18, color: cs.onSurface.withOpacity(0.2)),
    );
  }
}

// ── Vue Projets simple (cards → Gantt) ───────────────────────────────────────

class _SimpleProjectsView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final FirestoreSync sync;
  final VoidCallback onRefresh;
  const _SimpleProjectsView({
    required this.projects,
    required this.domains,
    required this.sync,
    required this.onRefresh,
  });
  @override
  State<_SimpleProjectsView> createState() => _SimpleProjectsViewState();
}

class _SimpleProjectsViewState extends State<_SimpleProjectsView> {
  String? _selectedDomainId;
  bool _showOutOfScope = false;

  Future<void> _archiveProject(Project p, bool archive) async {
    await widget.sync.saveProject(p..status = archive ? 'archived' : 'active');
    widget.onRefresh();
  }

  Future<void> _deleteProject(Project p) async {
    await widget.sync.deleteProject(p.id);
    widget.onRefresh();
  }

  bool _hasActiveTasks(Project p) {
    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);
    return p.tasks.any((t) =>
        t.status != 'done' &&
        t.status != 'skipped' &&
        !t.startDate.isAfter(todayD));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.projects.isEmpty) {
      return Center(
        child: Text('Aucun projet Gantt',
            style: TextStyle(
                fontSize: 16,
                color: cs.onSurface.withOpacity(.4),
                fontWeight: FontWeight.w500)),
      );
    }

    final allActive = widget.projects
        .where((p) => p.status != 'archived')
        .toList();
    final archived = widget.projects
        .where((p) => p.status == 'archived')
        .toList();

    final filtered = _selectedDomainId == null
        ? allActive
        : allActive.where((p) => p.domainId == _selectedDomainId).toList();

    // Séparer : avec tâches actives aujourd'hui vs hors scope
    final inScope = filtered.where(_hasActiveTasks).toList();
    final outOfScope = filtered.where((p) => !_hasActiveTasks(p)).toList();

    void openGantt(Project p) => Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => GanttScreen(project: p, domains: widget.domains)));

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Filtre domaine
          if (widget.domains.isNotEmpty) ...[
            Wrap(
              spacing: 8, runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Tous'),
                  selected: _selectedDomainId == null,
                  onSelected: (_) => setState(() => _selectedDomainId = null),
                ),
                for (int i = 0; i < widget.domains.length; i++)
                  FilterChip(
                    label: Text(widget.domains[i].name),
                    selected: _selectedDomainId == widget.domains[i].id,
                    selectedColor: (widget.domains[i].colorValue != null
                            ? Color(widget.domains[i].colorValue!)
                            : kDomainPalette[i % kDomainPalette.length])
                        .withOpacity(0.25),
                    onSelected: (_) => setState(() =>
                        _selectedDomainId =
                            _selectedDomainId == widget.domains[i].id
                                ? null
                                : widget.domains[i].id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Projets avec tâches actives aujourd'hui
          for (final p in inScope) ...[
            _ProjectCard(
              project: p,
              domains: widget.domains,
              documents: const [],
              sync: widget.sync,
              onTap: () => openGantt(p),
              onArchive: () => _archiveProject(p, true),
            ),
            const SizedBox(height: 10),
          ],

          // Hors scope (projets sans tâche active aujourd'hui)
          if (outOfScope.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showOutOfScope = !_showOutOfScope),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(
                    _showOutOfScope ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: cs.onSurface.withOpacity(.4)),
                  const SizedBox(width: 8),
                  Text(
                    'Hors scope (${outOfScope.length})',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.45)),
                  ),
                ]),
              ),
            ),
            if (_showOutOfScope)
              for (final p in outOfScope) ...[
                _ProjectCard(
                  project: p,
                  domains: widget.domains,
                  documents: const [],
                  sync: widget.sync,
                  onTap: () => openGantt(p),
                  onArchive: () => _archiveProject(p, true),
                ),
                const SizedBox(height: 10),
              ],
          ],

          // En veille
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArchivedSection(
              projects: archived,
              onRestore: (p) => _archiveProject(p, false),
              onTap: (p) => openGantt(p),
              onDelete: _deleteProject,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Vue Projets style iOS ─────────────────────────────────────────────────────

class _WebProjectsListView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final FirestoreSync sync;
  final VoidCallback onRefresh;

  const _WebProjectsListView({
    required this.projects,
    required this.domains,
    required this.sync,
    required this.onRefresh,
  });

  @override
  State<_WebProjectsListView> createState() => _WebProjectsListViewState();
}

class _WebProjectsListViewState extends State<_WebProjectsListView> {
  bool _showOutOfScope = false;
  bool _showArchived = false;
  String? _selectedDomainId;

  Color _domainColor(String? domainId, ColorScheme cs) {
    if (domainId == null) return cs.primary;
    final idx = widget.domains.indexWhere((d) => d.id == domainId);
    if (idx < 0) return cs.primary;
    final d = widget.domains[idx];
    if (d.colorValue != null) return Color(d.colorValue!);
    return kDomainPalette[idx % kDomainPalette.length];
  }

  void _openGantt(BuildContext context, Project project, {String? taskId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GanttScreen(
          project: project,
          targetTaskId: taskId,
          domains: widget.domains,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);

    final allActive = widget.projects.where((p) => p.status != 'archived').toList();
    final archived = widget.projects.where((p) => p.status == 'archived').toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    final filtered = _selectedDomainId == null
        ? allActive
        : allActive.where((p) => p.domainId == _selectedDomainId).toList();

    // Tâches actives aujourd'hui par domaine
    final byDomain = <String?, List<({Project project, ProjectTask task})>>{};
    for (final p in filtered) {
      for (final t in p.tasks) {
        if (t.status == 'skipped') continue;
        if (t.startDate.isAfter(todayD)) continue;
        byDomain.putIfAbsent(p.domainId, () => []).add((project: p, task: t));
      }
    }

    // Hors scope
    final projectsWithTodayTasks = <String>{};
    for (final pair in byDomain.values.expand((l) => l)) {
      projectsWithTodayTasks.add(pair.project.id);
    }
    final outOfScope = filtered
        .where((p) => !projectsWithTodayTasks.contains(p.id))
        .toList();

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          // Filtres domaine
          if (widget.domains.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('Tous'),
                    selected: _selectedDomainId == null,
                    onSelected: (_) => setState(() => _selectedDomainId = null),
                  ),
                  for (int i = 0; i < widget.domains.length; i++)
                    FilterChip(
                      label: Text(widget.domains[i].name),
                      selected: _selectedDomainId == widget.domains[i].id,
                      selectedColor: _domainColor(widget.domains[i].id, cs)
                          .withOpacity(0.25),
                      onSelected: (_) => setState(() =>
                          _selectedDomainId =
                              _selectedDomainId == widget.domains[i].id
                                  ? null
                                  : widget.domains[i].id),
                    ),
                ],
              ),
            ),

          // Tâches actives ou résumé projets
          if (byDomain.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'AUCUNE TÂCHE DÉMARRÉE AUJOURD\'HUI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ),
            ),
            for (final p in filtered)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: _WebProjectSummaryCard(
                  project: p,
                  color: _domainColor(p.domainId, cs),
                  cs: cs,
                  onTap: () => _openGantt(context, p),
                ),
              ),
          ] else
            ..._buildDomainSections(context, cs, byDomain, todayD),

          // Hors scope
          if (outOfScope.isNotEmpty) ...[
            _WebCollapsibleHeader(
              label: 'HORS SCOPE (${outOfScope.length})',
              expanded: _showOutOfScope,
              onToggle: () =>
                  setState(() => _showOutOfScope = !_showOutOfScope),
              cs: cs,
            ),
            if (_showOutOfScope)
              for (final p in outOfScope)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _WebProjectSummaryCard(
                    project: p,
                    color: _domainColor(p.domainId, cs),
                    cs: cs,
                    onTap: () => _openGantt(context, p),
                  ),
                ),
          ],

          // En veille
          if (archived.isNotEmpty) ...[
            _WebCollapsibleHeader(
              label: 'EN VEILLE (${archived.length})',
              expanded: _showArchived,
              onToggle: () =>
                  setState(() => _showArchived = !_showArchived),
              cs: cs,
            ),
            if (_showArchived)
              for (final p in archived)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _WebProjectSummaryCard(
                    project: p,
                    color: _domainColor(p.domainId, cs),
                    cs: cs,
                    onTap: () => _openGantt(context, p),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildDomainSections(
    BuildContext context,
    ColorScheme cs,
    Map<String?, List<({Project project, ProjectTask task})>> byDomain,
    DateTime todayD,
  ) {
    final widgets = <Widget>[];
    final knownIds = widget.domains.map((d) => d.id).toSet();
    final orderedIds = [
      ...widget.domains.map((d) => d.id).where(byDomain.containsKey),
      ...byDomain.keys.where((k) => k != null && !knownIds.contains(k)),
      if (byDomain.containsKey(null)) null,
    ];

    for (final domainId in orderedIds) {
      final pairs = byDomain[domainId]!;
      final domain = domainId != null
          ? widget.domains.where((d) => d.id == domainId).firstOrNull
          : null;
      final color = _domainColor(domainId, cs);

      // Header domaine
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            (domain?.name ?? 'Sans domaine').toUpperCase(),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1, color: color,
            ),
          ),
        ]),
      ));

      // Grouper par projet
      final byProject = <String, List<ProjectTask>>{};
      final projectMap = <String, Project>{};
      for (final pair in pairs) {
        byProject.putIfAbsent(pair.project.id, () => []).add(pair.task);
        projectMap[pair.project.id] = pair.project;
      }

      for (final projectId in byProject.keys) {
        final project = projectMap[projectId]!;
        final tasks = byProject[projectId]!;

        widgets.add(Padding(
          padding: EdgeInsets.fromLTRB(24, byProject.length > 1 ? 12 : 4, 24, 4),
          child: InkWell(
            onTap: () => _openGantt(context, project),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(project.title,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: cs.onSurface.withOpacity(.6))),
                ),
                Icon(Icons.account_tree_outlined,
                    size: 13, color: cs.onSurface.withOpacity(.25)),
                const SizedBox(width: 3),
                Text('Gantt',
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withOpacity(.25))),
              ]),
            ),
          ),
        ));

        // Grouper par phase
        final phaseMap = {for (final ph in project.phases) ph.id: ph};
        final byPhase = <String?, List<ProjectTask>>{};
        for (final t in tasks) byPhase.putIfAbsent(t.phaseId, () => []).add(t);

        final orderedPhaseIds = [
          ...project.phases.map((ph) => ph.id).where(byPhase.containsKey),
          if (byPhase.containsKey(null)) null,
        ];

        for (final phaseId in orderedPhaseIds) {
          final phaseTasks = byPhase[phaseId]!;
          final phase = phaseId != null ? phaseMap[phaseId] : null;

          if (phase != null) {
            Color phaseColor = color;
            if (phase.color != null) {
              try {
                final hex = phase.color!.replaceAll('#', '');
                phaseColor = Color(int.parse('FF$hex', radix: 16));
              } catch (_) {}
            }
            widgets.add(Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
              child: Row(children: [
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
                    color: cs.onSurface.withOpacity(.45),
                  ),
                ),
              ]),
            ));
          }

          for (final task in phaseTasks) {
            widgets.add(Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: _WebTaskCard(
                project: project,
                task: task,
                color: color,
                projectTitle: byProject.length == 1 ? project.title : '',
                today: todayD,
                cs: cs,
                onTap: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _FocusTaskDialog(
                      project: project,
                      task: task,
                      color: color,
                      domains: widget.domains,
                      sync: widget.sync,
                    ),
                  );
                  widget.onRefresh();
                },
              ),
            ));
          }
        }
      }
    }

    return widgets;
  }
}

// ── Carte tâche (style iOS GoalsView) ────────────────────────────────────────

class _WebTaskCard extends StatelessWidget {
  final Project project;
  final ProjectTask task;
  final Color color;
  final String projectTitle;
  final DateTime today;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _WebTaskCard({
    required this.project,
    required this.task,
    required this.color,
    required this.projectTitle,
    required this.today,
    required this.cs,
    required this.onTap,
  });

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    final isLate = task.endDate != null &&
        task.endDate!.isBefore(today) &&
        !isDone;
    final daysLate = isLate ? today.difference(task.endDate!).inDays : 0;
    final doneActions = task.actions.where((a) => a.done).length;
    final totalActions = task.actions.length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.35),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: isLate ? cs.error : color, width: 3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (projectTitle.isNotEmpty)
                    Text(
                      projectTitle,
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(isDone ? .4 : .9),
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (isLate)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '−$daysLate j',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cs.onErrorContainer),
                        ),
                      )
                    else if (task.endDate != null)
                      Text(
                        _fmt(task.endDate!),
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.4)),
                      ),
                    if (totalActions > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.checklist_outlined,
                          size: 12,
                          color: cs.onSurface.withOpacity(.4)),
                      const SizedBox(width: 3),
                      Text(
                        '$doneActions/$totalActions',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.4)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: cs.onSurface.withOpacity(.25)),
          ],
        ),
      ),
    );
  }
}

// ── Carte résumé projet ───────────────────────────────────────────────────────

class _WebProjectSummaryCard extends StatelessWidget {
  final Project project;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _WebProjectSummaryCard({
    required this.project,
    required this.color,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = project.tasks.length;
    final done = project.tasks.where((t) => t.status == 'done').length;
    final progress = total > 0 ? done / total : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: cs.onSurface.withOpacity(.08),
                  color: color,
                ),
                const SizedBox(height: 4),
                Text(
                  '$done / $total tâches',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.4)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right,
              size: 16, color: cs.onSurface.withOpacity(.25)),
        ]),
      ),
    );
  }
}

// ── Header section repliable ──────────────────────────────────────────────────

class _WebCollapsibleHeader extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final ColorScheme cs;

  const _WebCollapsibleHeader({
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(children: [
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 16, color: cs.onSurface.withOpacity(.4),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: cs.onSurface.withOpacity(.45),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Dialog gestion tâche (panneau Focus) ─────────────────────────────────────

class _FocusTaskDialog extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final Color color;
  final List<Domain> domains;
  final FirestoreSync sync;

  const _FocusTaskDialog({
    required this.project,
    required this.task,
    required this.color,
    required this.domains,
    required this.sync,
  });

  @override
  State<_FocusTaskDialog> createState() => _FocusTaskDialogState();
}

class _FocusTaskDialogState extends State<_FocusTaskDialog> {
  late ProjectTask _task;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _toggleStatus() async {
    setState(() => _task.status = _task.status == 'done' ? 'pending' : 'done');
    await widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);
  }

  Future<void> _toggleAction(int idx) async {
    setState(() => _task.actions[idx].done = !_task.actions[idx].done);
    await widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);
  }

  static String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDone = _task.status == 'done';
    final today = DateTime.now();
    final isLate = _task.endDate != null &&
        _task.endDate!.isBefore(today) && !isDone;
    final doneA = _task.actions.where((a) => a.done).length;
    final totalA = _task.actions.length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 56),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: cs.outlineVariant.withOpacity(.4)),
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                Container(
                    width: 3, height: 22,
                    decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.project.title,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.color)),
                      Text(_task.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statut + date
                    Row(children: [
                      InkWell(
                        onTap: _toggleStatus,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.withOpacity(.12)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDone
                                  ? Colors.green.withOpacity(.4)
                                  : cs.outlineVariant.withOpacity(.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDone
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: isDone
                                    ? Colors.green.shade600
                                    : cs.onSurface.withOpacity(.5),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                isDone ? 'Terminée' : 'En cours',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDone
                                      ? Colors.green.shade600
                                      : cs.onSurface.withOpacity(.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_task.endDate != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.calendar_today_outlined,
                            size: 13,
                            color: isLate
                                ? cs.error
                                : cs.onSurface.withOpacity(.4)),
                        const SizedBox(width: 5),
                        Text(
                          _fmt(_task.endDate!),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isLate ? FontWeight.w700 : FontWeight.normal,
                            color: isLate
                                ? cs.error
                                : cs.onSurface.withOpacity(.5),
                          ),
                        ),
                        if (isLate) ...[
                          const SizedBox(width: 5),
                          Text(
                            '(${today.difference(_task.endDate!).inDays} j de retard)',
                            style: TextStyle(
                                fontSize: 11, color: cs.error.withOpacity(.7)),
                          ),
                        ],
                      ],
                    ]),

                    // Sous-actions
                    if (totalA > 0) ...[
                      const SizedBox(height: 20),
                      Row(children: [
                        Text('Sous-actions',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface.withOpacity(.55))),
                        const Spacer(),
                        Text('$doneA / $totalA',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(.4))),
                      ]),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: totalA > 0 ? doneA / totalA : 0,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                        color: widget.color,
                        backgroundColor: cs.onSurface.withOpacity(.08),
                      ),
                      const SizedBox(height: 10),
                      for (int i = 0; i < _task.actions.length; i++)
                        InkWell(
                          onTap: () => _toggleAction(i),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 4),
                            child: Row(children: [
                              Icon(
                                _task.actions[i].done
                                    ? Icons.check_box_outlined
                                    : Icons.check_box_outline_blank,
                                size: 18,
                                color: _task.actions[i].done
                                    ? widget.color
                                    : cs.onSurface.withOpacity(.4),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _task.actions[i].title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withOpacity(
                                        _task.actions[i].done ? .4 : .85),
                                    decoration: _task.actions[i].done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Aucune sous-action définie.',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(.35),
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withOpacity(.4))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.account_tree_outlined, size: 14),
                    label: const Text('Voir dans le Gantt'),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GanttScreen(
                            project: widget.project,
                            targetTaskId: _task.id,
                            domains: widget.domains,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── ORION dans la sidebar Focus ───────────────────────────────────────────────

class _OrionSidebarSection extends StatefulWidget {
  final FirestoreSync sync;
  final ColorScheme cs;
  const _OrionSidebarSection({required this.sync, required this.cs});

  @override
  State<_OrionSidebarSection> createState() => _OrionSidebarSectionState();
}

class _OrionSidebarSectionState extends State<_OrionSidebarSection> {
  bool _triggering = false;
  String? _activeLabel;
  final _ctrl = TextEditingController();

  static const _quickActions = [
    (icon: '📋', label: 'Analyser retards',    taskId: 'overdue_summary',  need: ''),
    (icon: '📅', label: 'Deadlines semaine',   taskId: 'weekly_deadlines', need: ''),
    (icon: '📊', label: 'Rapport progression', taskId: 'progress_report',  need: ''),
    (icon: '🎯', label: 'Bilan semaine',        taskId: '',  need: 'Fais un bilan de ma semaine et propose des ajustements pour la suivante'),
    (icon: '⚡', label: 'Optimiser plan',      taskId: '',  need: 'Optimise mon plan du jour en fonction de mes priorités et deadlines'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _trigger({required String taskId, required String need, required String label}) async {
    final uid = widget.sync.uid;
    final tokens = await widget.sync.fetchApiTokens();
    final token = tokens.where((t) => t.active).firstOrNull?.token;
    if (uid == null || token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Token API requis (Connecter Claude)')),
        );
      }
      return;
    }
    setState(() { _triggering = true; _activeLabel = label; });
    try {
      final isDeterministic = taskId.isNotEmpty;
      final body = isDeterministic
          ? {'uid': uid, 'token': token, 'taskId': taskId}
          : {'uid': uid, 'token': token, 'userNeeds': need};
      final url = isDeterministic
          ? 'https://orionwebhook-dzos75b65q-uc.a.run.app'
          : 'https://orionsaveconfig-dzos75b65q-uc.a.run.app';
      await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ORION activé : $label'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
    if (mounted) setState(() { _triggering = false; _activeLabel = null; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    const orionColor = Color(0xFFe8c94a);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orionColor.withOpacity(.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orionColor.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.smart_toy_outlined, size: 14, color: orionColor),
            const SizedBox(width: 6),
            Text(
              'ORION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: orionColor,
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Boutons actions rapides
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final action in _quickActions)
                _OrionActionChip(
                  icon: action.icon,
                  label: action.label,
                  loading: _triggering && _activeLabel == action.label,
                  disabled: _triggering,
                  onTap: () => _trigger(
                    taskId: action.taskId,
                    need: action.need,
                    label: action.label,
                  ),
                  orionColor: orionColor,
                  cs: cs,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Champ libre
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                enabled: !_triggering,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Demande libre à ORION…',
                  hintStyle: TextStyle(
                      fontSize: 12, color: cs.onSurface.withOpacity(.35)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: orionColor.withOpacity(.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: orionColor.withOpacity(.25)),
                  ),
                ),
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isEmpty) return;
                  _trigger(taskId: '', need: t, label: t.substring(0, t.length.clamp(0, 30)));
                  _ctrl.clear();
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: _triggering && _activeLabel != null && _quickActions.every((a) => a.label != _activeLabel)
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: orionColor))
                  : Icon(Icons.send_rounded, size: 16, color: orionColor),
              onPressed: _triggering
                  ? null
                  : () {
                      final t = _ctrl.text.trim();
                      if (t.isEmpty) return;
                      _trigger(taskId: '', need: t, label: t.substring(0, t.length.clamp(0, 30)));
                      _ctrl.clear();
                    },
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
            ),
          ]),
        ],
      ),
    );
  }
}

class _OrionActionChip extends StatelessWidget {
  final String icon;
  final String label;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;
  final Color orionColor;
  final ColorScheme cs;

  const _OrionActionChip({
    required this.icon,
    required this.label,
    required this.loading,
    required this.disabled,
    required this.onTap,
    required this.orionColor,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: orionColor.withOpacity(loading ? .18 : .08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: orionColor.withOpacity(.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: orionColor),
              )
            else
              Text(icon, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: disabled
                    ? cs.onSurface.withOpacity(.35)
                    : cs.onSurface.withOpacity(.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
