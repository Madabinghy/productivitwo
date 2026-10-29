import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, clientRoots, inClient, rootProjectOf;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/coups.dart' show coupProjectIds;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/project_fiche_sheet.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart' show kBSurface, kBLine;
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onglet Projets « une carte, une fiche » (2026-10, handoff
/// `docs/specs/une-carte-une-fiche-2026-10/README.md`, lot 1) : en haut la
/// carte PROJET DU MOMENT (séance la plus proche, sinon le plus en retard sur
/// son plan — `rankProjectMoments`), puis une ligne par projet (tâches faites
/// avec le repère « attendu aujourd'hui », état en couleur), et des sections
/// repliées À venir / Terminés / En veille. Tap = fiche projet
/// (`showProjectFiche`) ; le plan détaillé reste `showProjectSheet`.
/// **Mur des projets** (2026-10) : chaque ligne porte la rangée de briques du
/// projet (`projectBricks`, une brique par tâche remplie par ses actions, trait
/// « attendu aujourd'hui ») ; tap sur une brique = la fiche de cette tâche.
class GoalsView extends StatefulWidget {
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Session> sessions;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;
  final void Function(int doneCount)? onBadgeCheck;
  final Widget? header;
  /// État des chronos pour la fiche de tâche (chip « chrono en cours », temps passé, Arrêter).
  final AppLogic? logic;

  const GoalsView({
    super.key,
    required this.domains,
    this.activities = const [],
    this.sessions = const [],
    this.onStartTimer,
    this.onBadgeCheck,
    this.header,
    this.logic,
  });

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  static const _kFoldedKey = 'projects_sections_folded';
  List<Project> _projects = [];
  final _sync = FirestoreSync();
  StreamSubscription<List<Project>>? _projectsSub;
  /// « Une liste, un seul bloc ouvert » : l'item ouvert (le premier par défaut).
  final _open = OpenItem();
  final _scroll = ScrollController();
  /// Coups en cours (Modes et coups) : en mode En forme, leurs projets passent en tête.
  Set<String> _coupProjectIds = const {};
  Set<String> _folded = {'upcoming', 'done', 'archived'};
  /// Filtres Domaine / Pour (2026-10), persistés comme dans Actions.
  static const _kDomainKey = 'projects_domain_filter';
  static const _kClientKey = 'projects_client_filter';
  Set<String> _domainFilter = {};
  String? _clientFilter;
  bool _filtersOpen = false;
  /// Aide « Touche une brique… » affichée jusqu'au premier tap (retour user 2026-10).
  static const _kHintKey = 'bricks_hint_seen';
  bool _hintSeen = true;
  ProjectMoment? _firstLive;

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
      final d = prefs.getStringList(_kDomainKey);
      final c = prefs.getString(_kClientKey);
      if (!mounted) return;
      setState(() {
        if (v != null) _folded = v.toSet();
        if (d != null) _domainFilter = d.toSet();
        _hintSeen = prefs.getBool(_kHintKey) ?? false;
        _clientFilter = c;
        _filtersOpen = _domainFilter.isNotEmpty || c != null;
      });
    });
  }

  Future<void> _toggleDomain(String id) async {
    setState(() => _domainFilter.contains(id) ? _domainFilter.remove(id) : _domainFilter.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDomainKey, _domainFilter.toList());
  }

  Future<void> _setClient(String? id) async {
    setState(() => _clientFilter = id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kClientKey);
    } else {
      await prefs.setString(_kClientKey, id);
    }
  }

  /// Domaine effectif d'un projet : le sien, sinon celui de sa racine.
  String? _domainOf(Project p) => p.domainId ?? rootProjectOf(p, _projects).domainId;

  bool _passes(Project p) =>
      (_domainFilter.isEmpty || _domainFilter.contains(_domainOf(p))) && inClient(_clientFilter, p, _projects);

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
    _scroll.dispose();
    super.dispose();
  }

  void _toggleItem(String id, String? defaultId) =>
      _open.settle(id, _scroll, () => setState(() => _open.toggle(id, defaultId)));

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
        logic: widget.logic,
        onStartTimer: widget.onStartTimer);
    if (mounted) setState(() {});
  }

  void _openPlan(Project p, {String? taskId}) =>
      showProjectSheet(context,
          project: p,
          domains: domains,
          targetTaskId: taskId,
          activities: widget.activities,
          sessions: widget.sessions,
          logic: widget.logic,
          onStartTimer: widget.onStartTimer);

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
    // Un seul niveau dans Projets (retour user 2026-10) : sans chrono possible,
    // la prochaine action s'ouvre dans le projet déplié, sa tâche dépliée.
    _openPlan(m.project, taskId: n.task.id);
  }

  void _newProject() => showNewProjectSheet(context, domains: domains, onCreated: () {}, sync: _sync, activities: widget.activities);

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    // Domaines qui portent au moins un projet (hors veille) et racines « Pour ».
    final usedDomainIds = {for (final p in _projects) if (p.status != 'archived') _domainOf(p)};
    final filterDomains = domains.where((d) => usedDomainIds.contains(d.id)).toList();
    final roots = clientRoots(_projects);
    if (_clientFilter != null && !roots.any((r) => r.id == _clientFilter)) _clientFilter = null;
    final hasFilters = filterDomains.length > 1 || roots.length > 1;
    final allRanked = rankProjectMoments(_projects, widget.sessions, now,
        priorityIds: AppLogic.modeNotifier.value == DayMode.high ? _coupProjectIds : const {});
    final ranked = allRanked.where((m) => _passes(m.project)).toList();
    final hidden = allRanked.length - ranked.length;
    final live = ranked.where((m) => !m.upcoming).toList();
    final upcoming = ranked.where((m) => m.upcoming).toList();
    final done = _projects.where((p) => p.status == 'done' && _passes(p)).toList()..sort((a, b) => a.title.compareTo(b.title));
    final archived = _projects.where((p) => p.status == 'archived' && _passes(p)).toList()..sort((a, b) => a.title.compareTo(b.title));
    final paused = _projects.where((p) => p.status == 'active' && p.paused && !isFolderProject(p, _projects) && _passes(p)).toList();
    final nothingAtAll = _projects.isEmpty;
    final empty = ranked.isEmpty && done.isEmpty && archived.isEmpty && paused.isEmpty;
    final running = runningTargets(widget.sessions);
    BrickRow rowOf(Project p) => projectBricks(p, now, runningTaskIds: running.taskIds, runningActionIds: running.actionIds);
    final liveRows = {for (final m in live) m.project.id: rowOf(m.project)};
    _firstLive = live.firstOrNull;
    final digest = wallDigest(liveRows.values);
    final nextSession = live.where((m) => m.session != null).fold<ProjectMoment?>(
        null, (best, m) => best == null || m.daysToSession! < best.daysToSession! ? m : best);

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
      body: nothingAtAll
          ? _emptyState(cs)
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                if (widget.header != null) widget.header!,
                if (hasFilters) _filtersToggle(cs, hidden),
                if (hasFilters && _filtersOpen) _filtersBar(cs, filterDomains, roots),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('Aucun projet ne passe les filtres.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .5))),
                  ),
                if (live.isNotEmpty) _digest(cs, digest, nextSession, now),
                if (live.isNotEmpty) ...[
                  const ListSectionTitle('TOUS LES PROJETS'),
                  for (final m in live) _item(m, liveRows[m.project.id]!, now, defaultId: live.first.project.id, moment: m == live.first),
                ],
                if (upcoming.isNotEmpty) ..._section('upcoming', 'À VENIR · ${upcoming.length}', [
                  for (final m in upcoming) _item(m, rowOf(m.project), now, defaultId: live.firstOrNull?.project.id),
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

  /// Ligne « FILTRES » repliable (même grammaire que l'onglet Actions).
  Widget _filtersToggle(ColorScheme cs, int hidden) {
    final n = _domainFilter.length + (_clientFilter == null ? 0 : 1);
    final on = n > 0;
    return InkWell(
      onTap: () => setState(() => _filtersOpen = !_filtersOpen),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Row(children: [
          Icon(Icons.tune_rounded, size: 14, color: on ? cs.primary : cs.onSurface.withValues(alpha: .5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              on
                  ? 'FILTRES · $n actif${n > 1 ? 's' : ''}${hidden > 0 ? ' · $hidden masqué${hidden > 1 ? 's' : ''}' : ''}'
                  : 'FILTRES · DOMAINE · POUR',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: on ? cs.primary : cs.onSurface.withValues(alpha: .5)),
            ),
          ),
          Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.onSurface.withValues(alpha: .45)),
        ]),
      ),
    );
  }

  Widget _filtersBar(ColorScheme cs, List<Domain> filterDomains, List<Project> roots) {
    Widget chip(String label, bool on, VoidCallback onTap, {Color? color}) => ChoiceChip(
          selected: on,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? (color ?? cs.primary) : cs.onSurface.withValues(alpha: .65),
          ),
          selectedColor: (color ?? cs.primary).withValues(alpha: .14),
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: .35),
          side: BorderSide(color: on ? (color ?? cs.primary).withValues(alpha: .5) : Colors.transparent),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(t,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withValues(alpha: .45))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (filterDomains.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            label('DOMAINE'),
            for (final d in filterDomains) ...[
              chip(d.name, _domainFilter.contains(d.id), () => _toggleDomain(d.id), color: domainColor(d.id, domains)),
              const SizedBox(width: 6),
            ],
          ]),
        ),
      if (roots.length > 1) ...[
        if (filterDomains.length > 1) const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            label('POUR'),
            for (final r in roots) ...[
              chip(r.title, _clientFilter == r.id, () => _setClient(_clientFilter == r.id ? null : r.id),
                  color: domainColor(r.domainId, domains)),
              const SizedBox(width: 6),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 4),
    ]);
  }

  List<Widget> _section(String key, String title, List<Widget> rows) {
    final open = !_folded.contains(key);
    return [
      ListSectionTitle(title, onAction: () => _toggle(key), expanded: open),
      if (open) ...rows,
    ];
  }

  /// Trois chiffres en tête du mur : tâches faites, projets derrière le trait, prochaine séance.
  Widget _digest(ColorScheme cs, ({int done, int total, int behind}) d, ProjectMoment? nextSession, DateTime now) {
    Widget tile(String v, String l, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color ?? cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(l, maxLines: 2, style: TextStyle(fontSize: 10.5, height: 1.2, color: cs.onSurface.withValues(alpha: .55))),
            ]),
          ),
        );
    final s = nextSession?.session;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        tile('${d.done} / ${d.total}', 'tâches faites, tous projets'),
        const SizedBox(width: 8),
        tile('${d.behind}', d.behind == 1 ? 'projet derrière le trait' : 'projets derrière le trait',
            color: d.behind == 0 ? kPalierGreen : (d.behind >= 3 ? kPalierCoral : kPalierAmber)),
        const SizedBox(width: 8),
        if (s != null)
          tile(sessionLabel(s, now).replaceFirst('séance ', ''), 'prochaine séance · ${nextSession!.project.title}')
        else
          tile('—', 'aucune séance à venir'),
      ]),
    );
  }

  /// Tap sur une brique = le projet déplié, CETTE tâche dépliée (même
  /// destination que la ligne : un seul niveau à retenir).
  void _openBrick(Project p, BrickRow row, int i) {
    if (!_hintSeen) {
      setState(() => _hintSeen = true);
      SharedPreferences.getInstance().then((prefs) => prefs.setBool(_kHintKey, true));
    }
    if (i < 0 || i >= row.total) return;
    _openPlan(p, taskId: row.bricks[i].id);
  }

  /// Ligne du mur : nom · k / n · état, la rangée de briques, puis la prochaine action.
  /// Un projet = un item à deux états : la ligne du mur (repliée) ou la carte
  /// du moment (ouverte), à sa place dans la liste.
  Widget _item(ProjectMoment m, BrickRow row, DateTime now, {required String? defaultId, bool moment = false}) {
    final id = m.project.id;
    return MomentItem(
      key: _open.keyFor(id),
      open: _open.isOpen(id, defaultId),
      collapsed: _wallRow(m, row, now),
      expanded: _momentCard(m, row, now, eyebrow: moment ? 'PROJET DU MOMENT' : (m.upcoming ? 'PROJET À VENIR' : 'PROJET')),
      onToggle: () => _toggleItem(id, defaultId),
      onLongPress: () => _openFiche(m.project),
    );
  }

  Widget _wallRow(ProjectMoment m, BrickRow row, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final p = m.project;
    final s = m.session;
    final st = palierColor(m.pctInt);
    final text3 = cs.onSurface.withValues(alpha: .55);
    final String foot;
    final IconData? footIcon;
    if (row.hasRunning) {
      foot = m.next == null ? 'chrono en cours' : '${m.next!.action.title} · chrono en cours';
      footIcon = Icons.timer_outlined;
    } else if (m.upcoming) {
      foot = 'démarre le ${_date(_firstStart(p))}';
      footIcon = Icons.schedule_rounded;
    } else if (m.next != null) {
      final n = m.next!;
      final steps = n.action.checklist.isEmpty ? '' : ' · ${n.action.checklist.where((c) => c.done).length} / ${n.action.checklist.length} étapes';
      foot = '${n.action.title}$steps';
      footIcon = Icons.play_arrow_rounded;
    } else if (row.total > 0 && row.done == row.total) {
      foot = 'Tout est fait · Terminer le projet';
      footIcon = Icons.check_rounded;
    } else {
      foot = 'Définir la prochaine action';
      footIcon = Icons.add;
    }
    final chip = m.upcoming ? 'à venir' : (m.plan.delta == 0 ? 'à jour' : '${m.deltaLabel.split(' ').first} sur le plan');
    return Material(
        color: dark ? kBSurface : cs.surface,
        borderRadius: BorderRadius.circular(14),
        child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: dark ? kBLine : cs.outlineVariant.withValues(alpha: .4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(m.rootTitle == null ? p.title : '${m.rootTitle} › ${p.title}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ),
                const SizedBox(width: 8),
                Text('${row.done} / ${row.total}',
                    style: TextStyle(fontSize: 12, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                StateChip(chip, color: m.upcoming ? kPalierMuted : st),
              ]),
              const SizedBox(height: 2),
              ProgressBricks(row: row, onBrick: (i) => _openBrick(p, row, i), pickerTitle: 'Tâches · ${p.title}'),
              if (!_hintSeen && m == _firstLive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined, size: 13, color: cs.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('Touche la ligne pour l\'ouvrir ici · une brique pour aller à sa tâche',
                          style: TextStyle(fontSize: 11.5, color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              Row(children: [
                Icon(footIcon, size: 14, color: s != null && m.sessionSoon ? cs.primary : text3),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    s != null ? '$foot · ${sessionLabel(s, now)}' : foot,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: text3, fontWeight: m.next != null ? FontWeight.w600 : null),
                  ),
                ),
              ]),
            ]),
        ),
    );
  }

  /// Bloc ouvert d'un projet (= l'ancienne carte PROJET DU MOMENT) : anneau =
  /// tâches faites / total, rangée de briques en détail, geste = la prochaine
  /// action, liens Déplier · Fiche · Autres.
  Widget _momentCard(ProjectMoment m, BrickRow row, DateTime now, {required String eyebrow}) {
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
    return MomentCard(
        accent: kPalierGreen,
        eyebrow: eyebrow,
        pill: s != null && m.sessionSoon ? sessionLabel(s, now) : (m.upcoming ? 'à venir' : (m.plan.delta == 0 ? 'à jour' : '${m.deltaLabel} sur le plan')),
        ring: plan.total == 0 ? 0 : plan.done / plan.total,
        ringColor: st,
        ringBig: '${plan.done} / ${plan.total}',
        ringSmall: 'TÂCHES',
        context_: ctx.isEmpty ? null : ctx,
        contextIcon: s != null ? Icons.event_rounded : null,
        title: p.title,
        sub: subParts.join(' · '),
        subColor: m.behind ? st : null,
        detail: row.total == 0
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ProgressBricks(row: row, height: 14, onBrick: (i) => _openBrick(p, row, i), pickerTitle: 'Tâches · ${p.title}'),
                if (behindLabel(row) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(behindLabel(row)!, style: const TextStyle(fontSize: 11.5, color: kPalierCoral, fontWeight: FontWeight.w600)),
                  ),
              ]),
        primaryLabel: m.next == null ? 'Définir la prochaine action' : m.next!.action.title,
        primaryIcon: m.next == null ? Icons.add : Icons.play_arrow_rounded,
        onPrimary: () => _startNext(m),
        ficheLabel: 'Déplier',
        onFiche: () => _openPlan(p),
        chainLabel: 'Fiche',
        chainIcon: null,
        onChain: () => _openFiche(p),
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
        onTap: () => _openPlan(p),
        onLongPress: () => _openFiche(p),
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
