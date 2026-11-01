import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject, clientRoots, inClient, rootProjectOf, kFlowTaskId;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/coups.dart' show coupProjectIds;
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/project_fiche_sheet.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart' show kBSurface, kBLine;
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/utils/projects_today.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone;
import 'package:productivitwo_v1/widgets/confirm_done.dart' show confirmDone;
import 'package:productivitwo_v1/widgets/action_focus_screen.dart' show showActionFocusScreen;
import 'package:productivitwo_v1/widgets/capture_triage_sheet.dart' show showCaptureTriageSheet;
import 'package:productivitwo_v1/widgets/actions_view.dart' show ActionsView;

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
  /// Onglet affiché : à chaque retour sur Projets, tous les projets se replient.
  final bool visible;
  /// État des chronos pour la fiche de tâche (chip « chrono en cours », temps passé, Arrêter).
  final AppLogic? logic;

  const GoalsView({
    this.visible = true,
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
  Set<String> _folded = {'upcoming', 'done', 'archived', 'loose'};
  /// Filtres Domaine / Pour (2026-10), persistés comme dans Actions.
  static const _kDomainKey = 'projects_domain_filter';
  static const _kClientKey = 'projects_client_filter';
  Set<String> _domainFilter = {};
  String? _clientFilter;
  /// Aide « Touche une brique… » affichée jusqu'au premier tap (retour user 2026-10).
  static const _kHintKey = 'bricks_hint_seen';
  bool _hintSeen = true;
  ProjectMoment? _firstLive;
  // 3 onglets (2026-11-01) : les actions vivent ici.
  StreamSubscription<List<CaptureItem>>? _captureSub;
  List<CaptureItem> _pendingCaptures = const [];
  bool _todayAll = false;
  static const _kTodayMax = 5;

  List<Domain> get domains => widget.domains;

  @override
  void initState() {
    super.initState();
    _subscribeProjects();
    _captureSub = _sync.streamCaptures().listen((items) {
      if (mounted) setState(() => _pendingCaptures = items.where((i) => i.status == 'pending').toList());
    }, onError: (_) {});
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
      });
    });
  }

  @override
  void didUpdateWidget(covariant GoalsView old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _open.reset();
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
    _captureSub?.cancel();
    _scroll.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projets'),
        centerTitle: false,
        actions: [
          Center(
            child: Text(
              '${live.length} actif${live.length > 1 ? 's' : ''}${upcoming.isNotEmpty ? ' · ${upcoming.length} à venir' : ''}'
              '${hidden > 0 ? ' · $hidden masqué${hidden > 1 ? 's' : ''}' : ''}',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55)),
            ),
          ),
          if (hasFilters) _filterButton(cs, filterDomains, roots) else const SizedBox(width: 12),
        ],
      ),
      body: nothingAtAll && looseActions(widget.activities).isEmpty
          ? _emptyState(cs)
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                if (widget.header != null) widget.header!,
                ..._actionsTop(cs, now),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('Aucun projet ne passe les filtres.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: .5))),
                  ),
                if (live.isNotEmpty) ...[
                  ListSectionTitle('MES PROJETS · ${live.length}'),
                  for (final m in live) _item(m, liveRows[m.project.id]!, now, defaultId: null, moment: m == live.first),
                ],
                if (upcoming.isNotEmpty) ..._section('upcoming', 'À VENIR · ${upcoming.length}', [
                  for (final m in upcoming) _item(m, rowOf(m.project), now, defaultId: null),
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
                ..._looseSection(cs, now),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _openAllActions,
                    icon: const Icon(Icons.checklist_rtl_rounded, size: 18),
                    label: const Text('Toutes les actions ›'),
                  ),
                ),
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

  /// Bouton « Filtrer » de la barre (retour user 2026-10-30 : pas de filtres
  /// dans la page) : pastille du nombre de filtres actifs, tap = feuille.
  Widget _filterButton(ColorScheme cs, List<Domain> filterDomains, List<Project> roots) {
    final n = _domainFilter.length + (_clientFilter == null ? 0 : 1);
    return IconButton(
      tooltip: 'Filtrer',
      onPressed: () => _openFilters(filterDomains, roots),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        backgroundColor: cs.primary,
        textColor: cs.onPrimary,
        child: Icon(Icons.tune_rounded, color: n > 0 ? cs.primary : null),
      ),
    );
  }

  Future<void> _openFilters(List<Domain> filterDomains, List<Project> roots) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        final n = _domainFilter.length + (_clientFilter == null ? 0 : 1);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Filtrer les projets', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                if (n > 0)
                  TextButton(
                    onPressed: () async {
                      for (final id in _domainFilter.toList()) {
                        await _toggleDomain(id);
                      }
                      await _setClient(null);
                      setLocal(() {});
                    },
                    child: const Text('Tout effacer'),
                  ),
              ]),
              const SizedBox(height: 10),
              _filtersBar(cs, filterDomains, roots, onChanged: () => setLocal(() {})),
            ]),
          ),
        );
      }),
    );
  }

  Widget _filtersBar(ColorScheme cs, List<Domain> filterDomains, List<Project> roots, {VoidCallback? onChanged}) {
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
              chip(d.name, _domainFilter.contains(d.id), () async {
                await _toggleDomain(d.id);
                onChanged?.call();
              }, color: domainColor(d.id, domains)),
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
              chip(r.title, _clientFilter == r.id, () async {
                await _setClient(_clientFilter == r.id ? null : r.id);
                onChanged?.call();
              }, color: domainColor(r.domainId, domains)),
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


  /// Ligne du mur : nom · k / n · état, la rangée de briques, puis la prochaine action.
  /// Un projet = un item à deux états : la ligne du mur (repliée) ou la carte
  /// du moment (ouverte), à sa place dans la liste.
  Widget _item(ProjectMoment m, BrickRow row, DateTime now, {required String? defaultId, bool moment = false}) {
    final id = m.project.id;
    // Tap = le projet déplié (retour user 2026-10-30) ; appui long = la fiche
    // du projet (prochaine action en page focus, décisions, actions).
    return MomentItem(
      key: _open.keyFor(id),
      open: false,
      collapsed: _wallRow(m, row, now),
      expanded: const SizedBox.shrink(),
      onToggle: () => _openPlan(m.project),
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
              // Projet dans un dossier (retour user 2026-10-30) : « Chérubins › »
              // en petit sur la ligne du compteur, le nom du projet seul dessous,
              // sur toute la largeur.
              Row(crossAxisAlignment: m.rootTitle == null ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
                Expanded(
                  child: m.rootTitle == null
                      ? Text(p.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface))
                      : Row(children: [
                          Icon(Icons.folder_outlined, size: 13, color: text3),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('${m.rootTitle} ›',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text3)),
                          ),
                        ]),
                ),
                const SizedBox(width: 8),
                Text('${row.done} / ${row.total}',
                    style: TextStyle(fontSize: 12, color: text3, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                StateChip(chip, color: m.upcoming ? kPalierMuted : st),
              ]),
              if (m.rootTitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(p.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ),
              const SizedBox(height: 2),
              // Retour user 2026-10 : la ligne entière ouvre le bloc, les briques ne
              // sont plus un geste à part (elles le restent dans le bloc ouvert).
              const SizedBox(height: 6),
              ProgressBricks(row: row),
              const SizedBox(height: 6),
              if (!_hintSeen && m == _firstLive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined, size: 13, color: cs.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('Touche la ligne pour l\'ouvrir ici',
                          style: TextStyle(fontSize: 11.5, color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              if (m.next != null && !m.upcoming && !row.hasRunning && widget.logic != null && !_inToday.contains(m.next!.action.id))
                _nextActionRow(cs, m)
              else
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


  // ── Les actions dans Projets (3 onglets, 2026-11-01) ──────────────────────

  Set<String> _inToday = const {};

  Activity? _activityById(String? id) => id == null ? null : widget.activities.where((a) => a.id == id && !a.deleted).firstOrNull;

  Future<void> _done(TaskAction a, {Project? project, Activity? owner, bool confirm = true}) async {
    if (confirm && !await confirmDone(context, title: a.title)) return;
    setActionDone(a, true);
    if (project != null) {
      unawaited(_sync.patchActionOf(project, a));
    } else if (owner != null) {
      unawaited(_sync.updateOwnActions(owner.id, owner.ownActions));
    }
    widget.logic?.onChange();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('« ${a.title} » faite'),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          setActionDone(a, false);
          if (project != null) {
            unawaited(_sync.patchActionOf(project, a));
          } else if (owner != null) {
            unawaited(_sync.updateOwnActions(owner.id, owner.ownActions));
          }
          widget.logic?.onChange();
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  Future<void> _aimTomorrow(TaskAction a, {Project? project, Activity? owner}) async {
    final prev = a.focusDate;
    final t = DateTime.now();
    a.focusDate = DateTime(t.year, t.month, t.day + 1);
    Future<void> save() async {
      if (project != null) {
        await _sync.patchActionOf(project, a);
      } else if (owner != null) {
        await _sync.updateOwnActions(owner.id, owner.ownActions);
      }
    }

    unawaited(save());
    widget.logic?.onChange();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('« ${a.title} » visée demain'),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          a.focusDate = prev;
          unawaited(save());
          widget.logic?.onChange();
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  Future<void> _focus(TaskAction a, {Project? project, ProjectTask? task, Activity? owner}) async {
    final logic = widget.logic;
    if (logic == null) return;
    final chrono = _activityById(a.linkedActivityId) ?? _activityById(project?.linkedActivityId) ?? owner;
    await showActionFocusScreen(context, logic: logic, action: a, project: project, task: task, ownerActivity: owner, chronoActivity: chrono, sync: _sync);
    if (mounted) setState(() {});
  }

  void _openAllActions() {
    final logic = widget.logic;
    if (logic == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('Toutes les actions')), body: ActionsView(logic: logic)),
    ));
  }

  String _reasonLabel(TodayReason r) => switch (r) {
        TodayReason.parole => 'parole',
        TodayReason.program => 'au programme',
        TodayReason.focus => '☀ visée',
        TodayReason.late => 'en retard',
      };

  Color _reasonColor(TodayReason r) => switch (r) {
        TodayReason.parole => const Color(0xFFC5A8FF),
        TodayReason.program => const Color(0xFF6FC3FF),
        TodayReason.focus => const Color(0xFFF2C14E),
        TodayReason.late => const Color(0xFFE5675B),
      };

  /// Une ligne d'action : rond = fait (confirmation), tap = page focus,
  /// glisser à droite = fait (annulable), à gauche = viser demain.
  Widget _actionLine(ColorScheme cs, TaskAction a, String sub, {Project? project, ProjectTask? task, Activity? owner, String? chip, Color? chipColor}) {
    final dark = cs.brightness == Brightness.dark;
    final text3 = cs.onSurface.withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
        key: ValueKey('act-${a.id}'),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            await _done(a, project: project, owner: owner, confirm: false);
          } else {
            await _aimTomorrow(a, project: project, owner: owner);
          }
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(color: const Color(0xFF16281F), borderRadius: BorderRadius.circular(12)),
          child: const Text('✓ Fait', style: TextStyle(color: Color(0xFF4CBF75), fontWeight: FontWeight.w800)),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(color: const Color(0xFF3A321B), borderRadius: BorderRadius.circular(12)),
          child: const Text('☀ Viser demain', style: TextStyle(color: Color(0xFFF2C14E), fontWeight: FontWeight.w800)),
        ),
        child: Material(
          color: dark ? kBSurface : cs.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _focus(a, project: project, task: task, owner: owner),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
              child: Row(children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fait',
                  icon: Icon(Icons.radio_button_unchecked, color: text3),
                  onPressed: () => _done(a, project: project, owner: owner),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: sub),
                        if (chip != null) TextSpan(text: '  $chip', style: TextStyle(color: chipColor, fontWeight: FontWeight.w700)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: text3),
                    ),
                  ]),
                ),
                Icon(Icons.play_arrow_rounded, color: cs.primary, size: 22),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Bandeau des captures, puis POUR AUJOURD'HUI (5 au plus).
  List<Widget> _actionsTop(ColorScheme cs, DateTime now) {
    final logic = widget.logic;
    if (logic == null) return const [];
    final today = DateTime(now.year, now.month, now.day);
    final parole = logic.paroles[logic.livedTodayYmd]?.ids.toSet() ?? const <String>{};
    final program = {for (final b in logic.todayBlocks) if (b.status == 'pending' && b.actionId != null) b.actionId!};
    final list = todayActions(projects: _projects, activities: widget.activities, today: today, paroleIds: parole, programActionIds: program);
    _inToday = {for (final x in list) x.action.id};
    final shown = _todayAll ? list : list.take(_kTodayMax).toList();
    final n = _pendingCaptures.length;
    return [
      if (n > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: const Color(0xFF1D2742),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showCaptureTriageSheet(context, logic: logic, sync: _sync, items: _pendingCaptures, onChanged: () {
                if (mounted) setState(() {});
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.inbox_outlined, size: 17, color: Color(0xFFBCD0FF)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('$n capture${n > 1 ? 's' : ''} à trier en action${n > 1 ? 's' : ''}', style: const TextStyle(fontSize: 13, color: Color(0xFFBCD0FF), fontWeight: FontWeight.w600))),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFBCD0FF)),
                ]),
              ),
            ),
          ),
        ),
      if (list.isNotEmpty) ...[
        ListSectionTitle('POUR AUJOURD\'HUI · ${list.length}'),
        for (final x in shown)
          _actionLine(
            cs,
            x.action,
            x.project != null ? '${x.project!.title}${x.task != null && x.task!.id != kFlowTaskId ? ' › ${x.task!.title}' : ''}' : (x.owner?.name ?? ''),
            project: x.project,
            task: x.task,
            owner: x.owner,
            chip: _reasonLabel(x.reason),
            chipColor: _reasonColor(x.reason),
          ),
        if (list.length > _kTodayMax)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _todayAll = !_todayAll),
              child: Text(_todayAll ? 'Réduire' : '+ ${list.length - _kTodayMax} autre${list.length - _kTodayMax > 1 ? 's' : ''}'),
            ),
          ),
      ],
    ];
  }

  /// La prochaine action d'un projet, cochable et lançable sur sa ligne.
  Widget _nextActionRow(ColorScheme cs, ProjectMoment m) {
    final n = m.next!;
    final text3 = cs.onSurface.withValues(alpha: .55);
    return Container(
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .07)))),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Fait',
          icon: Icon(Icons.radio_button_unchecked, size: 20, color: text3),
          onPressed: () => _done(n.action, project: m.project),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            onTap: () => _focus(n.action, project: m.project, task: n.task),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PROCHAINE ACTION', style: TextStyle(fontSize: 10, letterSpacing: .5, fontWeight: FontWeight.w800, color: text3)),
              Text(n.action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Page focus',
          icon: Icon(Icons.play_arrow_rounded, color: cs.primary),
          onPressed: () => _focus(n.action, project: m.project, task: n.task),
        ),
      ]),
    );
  }

  List<Widget> _looseSection(ColorScheme cs, DateTime now) {
    final loose = looseActions(widget.activities).where((x) => !_inToday.contains(x.$2.id)).toList();
    if (loose.isEmpty) return const [];
    return _section('loose', 'SANS PROJET · ${loose.length}', [
      for (final (act, a) in loose) _actionLine(cs, a, act.name, owner: act),
    ]);
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
