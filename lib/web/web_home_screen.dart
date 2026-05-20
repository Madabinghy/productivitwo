import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/help_sheet.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

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
  String? _selectedDomainId;
  bool _loading = true;
  late TabController _mainTabs;

  @override
  void initState() {
    super.initState();
    _mainTabs = TabController(length: 3, vsync: this);
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
      ]);
      if (!mounted) return;
      final tokens = results[2] as List;
      setState(() {
        _projects = results[0] as List<Project>;
        _objectives = results[1] as List<StrategicObjective>;
        _domains = results[3] as List<Domain>;
        _hasIosData = tokens.isNotEmpty;
        _loading = false;
      });
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
                ],
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _mainTabs,
              children: [
                _buildBody(cs),
                _FocusView(
                  projects: _projects
                      .where((p) => p.status != 'archived')
                      .toList(),
                  domains: _domains,
                ),
                _ArchivesView(sync: _sync),
              ],
            ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_projects.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 56, color: cs.onSurface.withOpacity(0.15)),
                const SizedBox(height: 20),
                Text('Aucun projet Gantt',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.4))),
                const SizedBox(height: 8),

                if (_hasIosData) ...[
                  // ── Connecté iOS — invite à créer avec Claude ─────────
                  Text(
                    'Ton compte iOS est connecté ✓\nDemande à Claude de créer ton premier Gantt.',
                    style: TextStyle(
                        fontSize: 14,
                        color: cs.primary.withOpacity(0.8),
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Exemple de prompt Claude',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface.withOpacity(0.45),
                                letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        Text(
                          '"Crée un plan de lancement pour mon projet '
                          'sur 3 mois avec des phases et des jalons"',
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: cs.primary,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ── Pas connecté — invite à connecter iOS ─────────────
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: cs.primary.withOpacity(0.2), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.smartphone_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Text('Tu as Productivitwo sur iPhone ?',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connecte ton compte iOS pour que Claude '
                          'accède à tes activités, routines et objectifs.',
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.65),
                              height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.link_outlined, size: 16),
                            label: const Text('Connecter mon compte iOS'),
                            onPressed: () => _showLinkIosDialog(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ou génère ton premier Gantt avec Claude',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(0.35)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Séparer actifs et archivés
    final allActive = _projects.where((p) => p.status != 'archived').toList();
    final archived = _projects.where((p) => p.status == 'archived').toList();

    // Filtre par domaine
    final active = _selectedDomainId == null
        ? allActive
        : allActive.where((p) => p.domainId == _selectedDomainId).toList();

    // Grouper les actifs filtrés par objectif stratégique
    final withObj = <StrategicObjective, List<Project>>{};
    final withoutObj = <Project>[];
    for (final p in active) {
      final obj = _objectiveFor(p);
      if (obj != null) {
        withObj.putIfAbsent(obj, () => []).add(p);
      } else {
        withoutObj.add(p);
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Filtre par domaine ─────────────────────────────────────────
          if (_domains.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('Tous'),
                  selected: _selectedDomainId == null,
                  onSelected: (_) => setState(() => _selectedDomainId = null),
                ),
                for (int i = 0; i < _domains.length; i++)
                  FilterChip(
                    label: Text(_domains[i].name),
                    selected: _selectedDomainId == _domains[i].id,
                    selectedColor: (_domains[i].colorValue != null
                        ? Color(_domains[i].colorValue!)
                        : kDomainPalette[i % kDomainPalette.length])
                        .withOpacity(0.25),
                    onSelected: (_) => setState(() =>
                        _selectedDomainId =
                            _selectedDomainId == _domains[i].id ? null : _domains[i].id),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Projets actifs avec objectif stratégique
          for (final entry in withObj.entries) ...[
            _ObjectiveHeader(objective: entry.key),
            const SizedBox(height: 12),
            for (final p in entry.value) ...[
              _ProjectCard(
                project: p,
                domains: _domains,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GanttScreen(project: p))),
                onArchive: () => _archiveProject(p, true),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
          ],
          // Projets actifs sans objectif
          if (withoutObj.isNotEmpty) ...[
            if (withObj.isNotEmpty) ...[
              Divider(color: cs.outlineVariant.withOpacity(0.4)),
              const SizedBox(height: 16),
            ],
            for (final p in withoutObj) ...[
              _ProjectCard(
                project: p,
                domains: _domains,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GanttScreen(project: p))),
                onArchive: () => _archiveProject(p, true),
              ),
              const SizedBox(height: 10),
            ],
          ],

          // ── Section En veille ─────────────────────────────────────────
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ArchivedSection(
              projects: archived,
              onRestore: (p) => _archiveProject(p, false),
              onTap: (p) => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => GanttScreen(project: p))),
            ),
          ],
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
}

// ── Vue Focus ────────────────────────────────────────────────────────────────

class _FocusView extends StatelessWidget {
  final List<Project> projects;
  final List<Domain> domains;
  const _FocusView({required this.projects, required this.domains});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Week boundaries (Monday–Sunday)
    final weekday = today.weekday; // 1=Mon..7=Sun
    final weekStart = today.subtract(Duration(days: weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    // Gather (task, project) pairs from all active projects
    final allPairs = <({ProjectTask task, Project project})>[];
    for (final p in projects) {
      for (final t in p.tasks) {
        allPairs.add((task: t, project: p));
      }
    }

    // ── Overdue ──────────────────────────────────────────────────────────────
    final overdue = allPairs
        .where((e) =>
            e.task.endDate != null &&
            e.task.endDate!.isBefore(today) &&
            e.task.status != 'done' &&
            e.task.status != 'skipped')
        .toList()
      ..sort((a, b) => a.task.endDate!.compareTo(b.task.endDate!));

    // ── This week ────────────────────────────────────────────────────────────
    final thisWeek = allPairs
        .where((e) =>
            e.task.status != 'done' &&
            e.task.status != 'skipped' &&
            !e.task.startDate.isAfter(weekEnd) &&
            (e.task.endDate == null || !e.task.endDate!.isBefore(weekStart)))
        .toList()
      ..sort((a, b) => a.task.startDate.compareTo(b.task.startDate));

    // ── Upcoming milestones (14 days) ────────────────────────────────────────
    final milestoneDeadline = today.add(const Duration(days: 14));
    final milestones = allPairs
        .where((e) =>
            e.task.isMilestone &&
            !e.task.startDate.isBefore(today) &&
            !e.task.startDate.isAfter(milestoneDeadline))
        .toList()
      ..sort((a, b) => a.task.startDate.compareTo(b.task.startDate));

    final allEmpty =
        overdue.isEmpty && thisWeek.isEmpty && milestones.isEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: allEmpty
            ? Center(
                child: Text(
                  'Aucune tâche en cours cette semaine',
                  style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withOpacity(0.4)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 24),
                children: [
                  // ── En retard ─────────────────────────────────────────────
                  if (overdue.isNotEmpty) ...[
                    _FocusSectionHeader(
                        label: 'En retard',
                        color: cs.error),
                    const SizedBox(height: 8),
                    for (final e in overdue) ...[
                      _FocusTaskTile(
                        task: e.task,
                        project: e.project,
                        domains: domains,
                        today: today,
                        cs: cs,
                        isOverdue: true,
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  // ── Cette semaine ─────────────────────────────────────────
                  _FocusSectionHeader(label: 'Cette semaine'),
                  const SizedBox(height: 8),
                  if (thisWeek.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Aucune tâche cette semaine',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.4),
                            fontStyle: FontStyle.italic),
                      ),
                    )
                  else
                    for (final e in thisWeek) ...[
                      _FocusTaskTile(
                        task: e.task,
                        project: e.project,
                        domains: domains,
                        today: today,
                        cs: cs,
                        isOverdue: false,
                      ),
                    ],

                  // ── Prochains jalons ──────────────────────────────────────
                  if (milestones.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _FocusSectionHeader(label: 'Prochains jalons (14 jours)'),
                    const SizedBox(height: 8),
                    for (final e in milestones) ...[
                      _FocusTaskTile(
                        task: e.task,
                        project: e.project,
                        domains: domains,
                        today: today,
                        cs: cs,
                        isOverdue: false,
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

class _FocusSectionHeader extends StatelessWidget {
  final String label;
  final Color? color;
  const _FocusSectionHeader({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: color ?? cs.onSurface.withOpacity(0.45),
      ),
    );
  }
}

class _FocusTaskTile extends StatelessWidget {
  final ProjectTask task;
  final Project project;
  final List<Domain> domains;
  final DateTime today;
  final ColorScheme cs;
  final bool isOverdue;
  const _FocusTaskTile({
    required this.task,
    required this.project,
    required this.domains,
    required this.today,
    required this.cs,
    required this.isOverdue,
  });

  static String _fmtDate(DateTime d) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  String get _statusIcon {
    if (task.isMilestone) return '◆';
    return switch (task.status) {
      'done' => '✓',
      'skipped' => '⏭',
      _ => '○',
    };
  }

  @override
  Widget build(BuildContext context) {
    final dateToShow = task.endDate ?? task.startDate;
    final daysLate = isOverdue && task.endDate != null
        ? today.difference(task.endDate!).inDays
        : 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOverdue
              ? cs.error.withOpacity(0.3)
              : cs.outlineVariant.withOpacity(0.4),
        ),
      ),
      color: isOverdue
          ? cs.errorContainer.withOpacity(0.15)
          : cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Status icon
            Text(
              _statusIcon,
              style: TextStyle(
                fontSize: 14,
                color: task.isMilestone
                    ? cs.primary
                    : isOverdue
                        ? cs.error
                        : cs.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(width: 12),
            // Task info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        project.title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.primary,
                        ),
                      ),
                      Builder(builder: (context) {
                        final domain = project.domainId == null
                            ? null
                            : domains
                                .where((d) => d.id == project.domainId)
                                .firstOrNull;
                        if (domain == null) return const SizedBox.shrink();
                        final color = _WebHomeScreenState._domainColor(domain, cs, domains);
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: color.withOpacity(0.4), width: 1),
                            ),
                            child: Text(
                              domain.name,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Date + overdue badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmtDate(dateToShow),
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withOpacity(0.45)),
                ),
                if (isOverdue && daysLate > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '−$daysLate j',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.error),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  const _ProjectCard({
    required this.project,
    required this.domains,
    required this.onTap,
    this.onArchive,
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
  const _ArchivedSection({
    required this.projects,
    required this.onRestore,
    required this.onTap,
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
  const _ArchivedProjectCard({
    required this.project,
    required this.onRestore,
    required this.onTap,
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
            ],
          ),
        ),
      ),
    );
  }
}

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
                                        description: 'Paramètres → Intégrations → Ajouter un serveur MCP → colle l\'URL',
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
  bool _loading = true;

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
      ]);
      if (!mounted) return;
      setState(() {
        _domains    = results[0] as List<Domain>;
        _activities = results[1] as List<Activity>;
        _routines   = results[2] as List<RecurringAction>;
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
        content: const Text('Cette action est irréversible.'),
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

    // Tri : actifs en premier, archivés ensuite
    final sortedDomains = [
      ..._domains.where((d) => !d.deleted),
      ..._domains.where((d) => d.deleted),
    ];

    final sortedActivities = [
      ..._activities.where((a) => !a.deleted),
      ..._activities.where((a) => a.deleted),
    ];

    final sortedRoutines = [
      ..._routines.where((r) => !r.deleted),
      ..._routines.where((r) => r.deleted),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── En-tête ───────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'ARCHIVES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: cs.onSurface.withOpacity(0.45),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_outlined, size: 14),
                  label: const Text('Rafraîchir'),
                  onPressed: _load,
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Section Domaines ──────────────────────────────────────────
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'DOMAINES (${sortedDomains.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: cs.onSurface.withOpacity(0.55),
                ),
              ),
              children: [
                if (sortedDomains.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucun domaine',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.4),
                          fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  for (final d in sortedDomains) ...[
                    _ArchiveItemRow(
                      label: d.name,
                      isArchived: d.deleted,
                      onArchive: () => _archive('domains', d.id),
                      onRestore: () => _restore('domains', d.id),
                      onDelete: () => _confirmHardDelete('domains', d.id),
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                  ],
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),

            // ── Section Activités ─────────────────────────────────────────
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'ACTIVITÉS (${sortedActivities.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: cs.onSurface.withOpacity(0.55),
                ),
              ),
              children: [
                if (sortedActivities.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucune activité',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.4),
                          fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  for (final a in sortedActivities) ...[
                    _ArchiveItemRow(
                      label: a.name,
                      isArchived: a.deleted,
                      subtitle: () {
                        if (a.domainId.isEmpty) return null;
                        final domain =
                            _domains.where((d) => d.id == a.domainId).firstOrNull;
                        return 'domaine: ${domain?.name ?? a.domainId.substring(0, 8)}…';
                      }(),
                      onArchive: () => _archive('activities', a.id),
                      onRestore: () => _restore('activities', a.id),
                      onDelete: () => _confirmHardDelete('activities', a.id),
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                  ],
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),

            // ── Section Routines ──────────────────────────────────────────
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'ROUTINES (${sortedRoutines.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: cs.onSurface.withOpacity(0.55),
                ),
              ),
              children: [
                if (sortedRoutines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucune routine',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(0.4),
                          fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  for (final r in sortedRoutines) ...[
                    _ArchiveItemRow(
                      label: r.title,
                      isArchived: r.deleted,
                      subtitle: () {
                        if (r.activityId == null || r.activityId!.isEmpty)
                          return null;
                        final activity = _activities
                            .where((a) => a.id == r.activityId)
                            .firstOrNull;
                        return activity != null ? 'activité: ${activity.name}' : null;
                      }(),
                      onArchive: () => _archive('recurringActions', r.id),
                      onRestore: () => _restore('recurringActions', r.id),
                      onDelete: () =>
                          _confirmHardDelete('recurringActions', r.id),
                      cs: cs,
                    ),
                    const SizedBox(height: 6),
                  ],
                const SizedBox(height: 8),
              ],
            ),
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
  final VoidCallback onDelete;
  final ColorScheme cs;

  const _ArchiveItemRow({
    required this.label,
    required this.isArchived,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
    required this.cs,
    this.subtitle,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Restaurer'),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: cs.error,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Supprimer'),
            ),
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
