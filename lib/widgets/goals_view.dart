import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/coups.dart' show coupProjectIds;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';
import 'package:productivitwo_v1/widgets/project_fiche_sheet.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onglet Projets « une carte, une fiche » (2026-10, handoff
/// `docs/specs/une-carte-une-fiche-2026-10/README.md`, lot 1) : en haut la
/// carte PROJET DU MOMENT (séance la plus proche, sinon le plus en retard sur
/// son plan — `rankProjectMoments`), puis une ligne par projet (tâches faites
/// avec le repère « attendu aujourd'hui », état en couleur), et des sections
/// repliées À venir / Terminés / En veille. Tap = fiche projet
/// (`showProjectFiche`) ; le plan détaillé reste `showProjectSheet`.
class GoalsView extends StatefulWidget {
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Session> sessions;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;
  final void Function(int doneCount)? onBadgeCheck;
  final Widget? header;

  const GoalsView({
    super.key,
    required this.domains,
    this.activities = const [],
    this.sessions = const [],
    this.onStartTimer,
    this.onBadgeCheck,
    this.header,
  });

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  static const _kFoldedKey = 'projects_sections_folded';
  List<Project> _projects = [];
  final _sync = FirestoreSync();
  StreamSubscription<List<Project>>? _projectsSub;
  int _offset = 0; // « suivant » sur la carte du moment
  /// Coups en cours (Modes et coups) : en mode En forme, leurs projets passent en tête.
  Set<String> _coupProjectIds = const {};
  Set<String> _folded = {'upcoming', 'done', 'archived'};

  List<Domain> get domains => widget.domains;

  @override
  void initState() {
    super.initState();
    _subscribeProjects();
    _sync.fetchStrategicObjectives().then((all) {
      if (mounted) setState(() => _coupProjectIds = coupProjectIds(all, DateTime.now()));
    }).catchError((_) {});
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getStringList(_kFoldedKey);
      if (v != null && mounted) setState(() => _folded = v.toSet());
    });
  }

  /// Abonnement au stream projets AVEC réabonnement sur erreur : un stream
  /// Firestore tué (ex. bascule d'auth) figeait la liste.
  void _subscribeProjects() {
    _projectsSub?.cancel();
    _projectsSub = _sync.streamProjects().listen(
      (projects) {
        if (mounted) setState(() => _projects = projects);
      },
      onError: (_) {
        if (!mounted) return;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _subscribeProjects();
        });
      },
    );
  }

  @override
  void dispose() {
    _projectsSub?.cancel();
    super.dispose();
  }

  Future<void> _toggle(String key) async {
    setState(() => _folded.contains(key) ? _folded.remove(key) : _folded.add(key));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFoldedKey, _folded.toList());
  }

  Future<void> _openFiche(Project p) async {
    await showProjectFiche(context,
        project: p,
        allProjects: _projects,
        domains: domains,
        activities: widget.activities,
        sessions: widget.sessions,
        sync: _sync,
        onStartTimer: widget.onStartTimer);
    if (mounted) setState(() {});
  }

  void _openPlan(Project p, {String? taskId}) =>
      showProjectSheet(context, project: p, domains: domains, targetTaskId: taskId, activities: widget.activities);

  void _startNext(ProjectMoment m) {
    final n = m.next;
    if (n == null) {
      _openPlan(m.project);
      return;
    }
    final act = widget.activities.where((a) => a.id == (n.action.linkedActivityId ?? m.project.linkedActivityId)).firstOrNull;
    if (act != null && widget.onStartTimer != null) {
      widget.onStartTimer!(act, m.project, n.task);
      return;
    }
    _openPlan(m.project, taskId: n.task.id);
  }

  void _newProject() => showNewProjectSheet(context, domains: domains, onCreated: () {}, sync: _sync, activities: widget.activities);

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final ranked = rankProjectMoments(_projects, widget.sessions, now,
        priorityIds: AppLogic.modeNotifier.value == DayMode.high ? _coupProjectIds : const {});
    final live = ranked.where((m) => !m.upcoming).toList();
    final upcoming = ranked.where((m) => m.upcoming).toList();
    final done = _projects.where((p) => p.status == 'done').toList()..sort((a, b) => a.title.compareTo(b.title));
    final archived = _projects.where((p) => p.status == 'archived').toList()..sort((a, b) => a.title.compareTo(b.title));
    final paused = _projects.where((p) => p.status == 'active' && p.paused && !isFolderProject(p, _projects)).toList();
    final empty = ranked.isEmpty && done.isEmpty && archived.isEmpty && paused.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projets'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${live.length} actif${live.length > 1 ? 's' : ''}${upcoming.isNotEmpty ? ' · ${upcoming.length} à venir' : ''}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55)),
              ),
            ),
          ),
        ],
      ),
      body: empty
          ? _emptyState(cs)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                if (widget.header != null) widget.header!,
                if (ranked.isNotEmpty) _momentCard(ranked, now),
                if (live.isNotEmpty) ...[
                  const ListSectionTitle('TOUS LES PROJETS'),
                  for (final m in live) _projectRow(m, now),
                ],
                if (upcoming.isNotEmpty) ..._section('upcoming', 'À VENIR · ${upcoming.length}', [
                  for (final m in upcoming) _projectRow(m, now),
                ]),
                if (paused.isNotEmpty) ..._section('paused', 'EN PAUSE · ${paused.length}', [
                  for (final p in paused) _plainRow(p, 'en pause'),
                ]),
                if (done.isNotEmpty) ..._section('done', 'TERMINÉS · ${done.length}', [
                  for (final p in done) _plainRow(p, 'terminé', muted: true),
                ]),
                if (archived.isNotEmpty) ..._section('archived', 'EN VEILLE · ${archived.length}', [
                  for (final p in archived) _plainRow(p, 'en veille'),
                ]),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newProject,
        icon: const Icon(Icons.auto_awesome, size: 18),
        label: const Text('Nouveau projet'),
        backgroundColor: Colors.deepPurple.shade500,
        foregroundColor: Colors.white,
      ),
    );
  }

  List<Widget> _section(String key, String title, List<Widget> rows) {
    final open = !_folded.contains(key);
    return [
      ListSectionTitle(title, onAction: () => _toggle(key), expanded: open),
      if (open) ...rows,
    ];
  }

  /// PROJET DU MOMENT : anneau = tâches faites / total, geste = la prochaine action.
  Widget _momentCard(List<ProjectMoment> ranked, DateTime now) {
    final m = ranked[_offset % ranked.length];
    final p = m.project;
    final plan = m.plan;
    final st = palierColor(m.pctInt);
    final s = m.session;
    final subParts = <String>[
      if (s != null && m.sessionSoon)
        '${m.weekActions.length} action${m.weekActions.length > 1 ? 's' : ''} avant la séance'
      else if (m.weekActions.isNotEmpty)
        '${m.weekActions.length} action${m.weekActions.length > 1 ? 's' : ''} cette semaine',
      if (s?.prep != null && m.sessionSoon) 'prépa ${s!.prepTotal - s.prepOpen} / ${s.prepTotal}',
      m.upcoming ? 'démarre plus tard' : (plan.delta == 0 ? 'à jour sur le plan' : '${m.deltaLabel} sur le plan'),
    ];
    final ctx = [
      if (m.rootTitle != null) 'Pour ${m.rootTitle}',
      if (s != null) sessionLabel(s, now) else if (p.endDate != null) 'échéance ${_date(p.endDate!)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MomentCard(
        accent: kPalierGreen,
        eyebrow: 'PROJET DU MOMENT',
        pill: ranked.length > 1 ? '${_offset % ranked.length + 1} / ${ranked.length} · suivant ›' : (s != null && m.sessionSoon ? sessionLabel(s, now) : null),
        onPill: ranked.length > 1 ? () => setState(() => _offset = (_offset + 1) % ranked.length) : null,
        ring: plan.total == 0 ? 0 : plan.done / plan.total,
        ringColor: st,
        ringBig: '${plan.done} / ${plan.total}',
        ringSmall: 'TÂCHES',
        context_: ctx.isEmpty ? null : ctx,
        contextIcon: s != null ? Icons.event_rounded : null,
        title: p.title,
        sub: subParts.join(' · '),
        subColor: m.behind ? st : null,
        primaryLabel: m.next == null ? 'Définir la prochaine action' : m.next!.action.title,
        primaryIcon: m.next == null ? Icons.add : Icons.play_arrow_rounded,
        onPrimary: () => _startNext(m),
        onFiche: () => _openFiche(p),
      ),
    );
  }

  Widget _projectRow(ProjectMoment m, DateTime now) {
    final p = m.project;
    final plan = m.plan;
    final s = m.session;
    final sub = <String>[
      '${plan.done} / ${plan.total} tâche${plan.total > 1 ? 's' : ''}',
      if (!m.upcoming) 'attendu ${plan.expected}',
      if (s != null)
        sessionLabel(s, now)
      else if (m.next != null)
        m.next!.action.title
      else if (m.upcoming)
        'démarre le ${_date(_firstStart(p))}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Icon(s != null && m.sessionSoon ? Icons.event_rounded : Icons.account_tree_outlined),
        title: m.rootTitle == null ? p.title : '${m.rootTitle} › ${p.title}',
        sub: sub,
        bar: (done: plan.done, total: plan.total, expected: m.upcoming ? 0 : plan.expected),
        pct: m.pctInt,
        chip: m.stateLabel,
        onTap: () => _openFiche(p),
        onLongPress: () => _openPlan(p),
      ),
    );
  }

  Widget _plainRow(Project p, String chip, {bool muted = false}) {
    final plan = projectPlan(p, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StatusRow(
        leading: Icon(muted ? Icons.check_rounded : Icons.inventory_2_outlined),
        title: p.title,
        sub: '${plan.done} / ${plan.total} tâche${plan.total > 1 ? 's' : ''}',
        pct: 100,
        muted: muted,
        trailing: StateChip(chip, color: kPalierMuted),
        onTap: () => _openFiche(p),
        onLongPress: () => _openPlan(p),
      ),
    );
  }

  DateTime _firstStart(Project p) {
    final open = p.tasks.where((t) => t.status != 'done' && t.status != 'skipped').map((t) => t.startDate).toList()..sort();
    return open.isEmpty ? p.startDate : open.first;
  }

  String _date(DateTime d) {
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${d.day} ${months[d.month - 1]}';
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_tree_outlined, size: 48, color: cs.onSurface.withValues(alpha: .2)),
          const SizedBox(height: 16),
          Text('Aucun projet actif', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface.withValues(alpha: .5))),
          const SizedBox(height: 8),
          Text('Décris tes idées et ORION structure le projet pour toi.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: .35))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Nouveau projet'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade500),
          ),
        ]),
      ),
    );
  }
}
