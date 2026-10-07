import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/web/action_dialogs.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/web/quick_add_action_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Onglet Actions (refonte web § 5) : filtres « Je suis… / J'ai… / Domaine »
// (gauche), liste par projet avec la prochaine action en tête + « Possible
// maintenant » quand un chrono tourne (centre), engagements 7 jours et
// routines du jour (droite).

const _tabular = [FontFeature.tabularFigures()];
const _kPrefContexts = 'web.actions.contexts';
const _kPrefTime = 'web.actions.time';
const _kPrefDomain = 'web.actions.domain';
const _kPrefSort = 'web.actions.sort';
const _kPrefClient = 'web.actions.client';

class ActionsView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<Activity> activities;
  final FirestoreSync sync;
  final VoidCallback onRefresh;
  final void Function(Project project, {String? taskId}) onOpenProject;

  const ActionsView({
    super.key,
    required this.projects,
    required this.domains,
    required this.activities,
    required this.sync,
    required this.onRefresh,
    required this.onOpenProject,
  });

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<ActionsView> {
  final Set<String> _contexts = {};
  TimeBucket? _time;
  // Filtre actif : projets sans action correspondante masqués, sauf demande.
  bool _showUnmatched = false;
  bool get _filtering => _contexts.isNotEmpty || _time != null;
  String? _domainId;
  // « Pour… » : projet racine (client) ; null = tous.
  String? _clientId;
  ActionsSort _sort = ActionsSort.dueDate;
  bool _showPaused = false;
  final Set<String> _expanded = {};

  List<Session> _sessions = [];
  List<HabitHit> _hits = [];
  List<ScheduleBlock> _todayBlocks = [];
  AppLogic? _logic;
  StreamSubscription<List<Session>>? _sessionsSub;
  StreamSubscription<List<HabitHit>>? _hitsSub;
  StreamSubscription<DailySchedule?>? _scheduleSub;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _sessionsSub = widget.sync.streamSessions().listen((s) {
      if (mounted) setState(() => _sessions = s);
    });
    _hitsSub = widget.sync.streamHabitHits().listen((h) {
      if (mounted) setState(() => _hits = h);
    });
    _scheduleSub = widget.sync.streamDailySchedule(ymdOf(DateTime.now())).listen((s) {
      if (mounted) {
        setState(() => _todayBlocks =
            s?.blocks.where((b) => b.status != 'deleted').toList() ?? []);
      }
    });
    widget.sync.pull().then((state) {
      if (state == null || !mounted) return;
      final logic = AppLogic(state, () {})..sync = widget.sync;
      setState(() => _logic = logic);
    });
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _hitsSub?.cancel();
    _scheduleSub?.cancel();
    super.dispose();
  }

  // ── Préférences (par appareil) ──────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _contexts
          ..clear()
          ..addAll(p.getStringList(_kPrefContexts) ?? const []);
        final t = p.getString(_kPrefTime);
        _time = TimeBucket.values.where((b) => b.name == t).firstOrNull;
        _domainId = p.getString(_kPrefDomain);
        _clientId = p.getString(_kPrefClient);
        final s = p.getString(_kPrefSort);
        _sort = ActionsSort.values.where((x) => x.name == s).firstOrNull ?? ActionsSort.dueDate;
      });
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kPrefContexts, _contexts.toList());
      _time == null ? await p.remove(_kPrefTime) : await p.setString(_kPrefTime, _time!.name);
      _domainId == null
          ? await p.remove(_kPrefDomain)
          : await p.setString(_kPrefDomain, _domainId!);
      await p.setString(_kPrefSort, _sort.name);
      _clientId == null
          ? await p.remove(_kPrefClient)
          : await p.setString(_kPrefClient, _clientId!);
    } catch (_) {}
  }

  // ── Dérivation ──────────────────────────────────────────────────────────────

  bool _filter(TaskAction a) => passesContexts(a, _contexts) && passesTime(a, _time);

  List<Project> get _domainProjects => widget.projects
      .where((p) => _domainId == null || p.domainId == _domainId)
      .where((p) => _clientId == null || rootProjectOf(p, widget.projects).id == _clientId)
      .where((p) => !isFolderProject(p, widget.projects))
      .toList();

  int _openCountForClient(String? rootId) {
    var n = 0;
    for (final p in widget.projects) {
      if (p.status != 'active' || p.paused) continue;
      if (_domainId != null && p.domainId != _domainId) continue;
      if (rootId != null && rootProjectOf(p, widget.projects).id != rootId) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        n += t.actions.where((a) => !a.done && _filter(a)).length;
      }
    }
    return n;
  }

  List<Activity> get _domainActivities => _domainId == null
      ? widget.activities
      : widget.activities.where((a) => a.domainId == _domainId).toList();

  Session? get _openSession {
    Session? last;
    for (final s in _sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  Activity? _activity(String? id) =>
      id == null ? null : widget.activities.where((a) => a.id == id).firstOrNull;

  int _openCountForDomain(String? domainId) {
    var n = 0;
    for (final p in widget.projects) {
      if (p.status != 'active' || p.paused) continue;
      if (domainId != null && p.domainId != domainId) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        n += t.actions.where((a) => !a.done && _filter(a)).length;
      }
    }
    for (final act in widget.activities) {
      if (act.deleted) continue;
      if (domainId != null && act.domainId != domainId) continue;
      n += act.ownActions.where((a) => !a.done && _filter(a)).length;
    }
    return n;
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> _toggleProjectAction(Project p, TaskAction a) async {
    setState(() {
      a.done = !a.done;
      a.doneAt = a.done ? DateTime.now() : null;
    });
    await widget.sync.saveProjectTasks(p.id, p.tasks);
  }

  Future<void> _toggleOwnAction(Activity act, TaskAction a) async {
    setState(() {
      a.done = !a.done;
      a.doneAt = a.done ? DateTime.now() : null;
    });
    await widget.sync.updateOwnActions(act.id, act.ownActions);
  }

  Future<void> _edit(TaskAction a, {Project? project, ProjectTask? task, Activity? activity}) async {
    final changed = await showEditActionDialog(context,
        sync: widget.sync,
        action: a,
        projects: widget.projects,
        project: project,
        task: task,
        activity: activity);
    if (changed && mounted) {
      setState(() {});
      widget.onRefresh();
    }
  }

  Future<void> _resume(Project p) async {
    setState(() => p.paused = false);
    await widget.sync.saveProject(p);
    widget.onRefresh();
  }

  /// Coche une routine du jour : même règle que la frise d'Aujourd'hui
  /// (1 incrément, capé à la cible).
  Future<void> _checkRoutine(String activityId) async {
    final logic = _logic;
    if (logic == null) return;
    final act = logic.state.activities.where((a) => a.id == activityId).firstOrNull;
    if (act == null || !act.isHabit) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tgt = logic.activeHabitTarget(act);
    if (tgt > 0 && logic.habitValueOn(activityId, today) >= tgt) return;
    logic.incHabit(activityId, 1, today);
    final key = yyyymmdd(today);
    final hp = logic.state.habitProgress
        .where((h) => h.activityId == activityId && h.yyyymmdd == key)
        .lastOrNull;
    if (hp != null) await widget.sync.saveHabitProgress(hp);
    if (logic.state.habitHits.isNotEmpty) {
      await widget.sync.saveHabitHit(logic.state.habitHits.last);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Routine validée : ${act.name}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBBg,
      child: LayoutBuilder(builder: (ctx, box) {
        final narrow = box.maxWidth < 1000;
        if (narrow) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
            children: [
              _filtersColumn(),
              const SizedBox(height: 18),
              _center(),
              const SizedBox(height: 18),
              _sideColumn(),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 250,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 26), child: _filtersColumn()),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 26), child: _center()),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 26), child: _sideColumn()),
            ),
          ]),
        );
      }),
    );
  }

  // ── Filtres ─────────────────────────────────────────────────────────────────

  Widget _filtersColumn() {
    final contexts = knownContexts(widget.projects, widget.activities);
    final paused = widget.projects.where((p) => p.status != 'archived' && p.paused).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label('JE SUIS…'),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in contexts)
          _chip(c, selected: _contexts.contains(c), onTap: () {
            setState(() {
              _contexts.contains(c) ? _contexts.remove(c) : _contexts.add(c);
              _showUnmatched = false;
            });
            _savePrefs();
          }),
      ]),
      if (_contexts.isNotEmpty) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: _textLink('Effacer', () {
            setState(_contexts.clear);
            _savePrefs();
          }, muted: true),
        ),
      ],
      const SizedBox(height: 22),
      _label("J'AI…"),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (b, lbl) in const [
          (TimeBucket.quarter, '15 min'),
          (TimeBucket.hour, '1 h'),
          (TimeBucket.more, 'Plus'),
        ])
          _chip(lbl, selected: _time == b, onTap: () {
            setState(() => _time = _time == b ? null : b);
            _savePrefs();
          }),
      ]),
      if (clientRoots(widget.projects).length > 1) ...[
        const SizedBox(height: 22),
        _label('POUR…'),
        const SizedBox(height: 10),
        _clientRow(null, 'Tous'),
        for (final r in clientRoots(widget.projects)) _clientRow(r.id, r.title),
      ],
      const SizedBox(height: 22),
      _label('DOMAINE'),
      const SizedBox(height: 10),
      _domainRow(null, 'Tous'),
      for (final d in widget.domains.where((d) => !d.deleted)) _domainRow(d.id, d.name),
      const SizedBox(height: 22),
      _pillButton('Action simple',
          icon: Icons.add,
          onTap: () async {
            final ok = await showAddOwnActionDialog(context,
                sync: widget.sync, activities: widget.activities);
            if (ok && mounted) setState(() {});
          }),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: _textLink(
            _showPaused ? '‹ Actions' : 'En pause · $paused',
            () => setState(() => _showPaused = !_showPaused),
            muted: !_showPaused),
      ),
    ]);
  }

  Widget _clientRow(String? id, String name) {
    final selected = _clientId == id;
    final count = _openCountForClient(id);
    return InkWell(
      onTap: () {
        setState(() {
          _clientId = id;
          _showUnmatched = false;
        });
        _savePrefs();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(id == null ? Icons.all_inclusive : Icons.folder_outlined,
              size: 14, color: selected ? kBText : kBText3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kBText : kBText2)),
          ),
          Text('$count',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: count == 0 ? kBText4 : kBText3,
                  fontFeatures: _tabular)),
        ]),
      ),
    );
  }

  Widget _domainRow(String? id, String name) {
    final selected = _domainId == id;
    final color = id == null ? kBText3 : (domainColor(id, widget.domains) ?? kBText3);
    final count = _openCountForDomain(id);
    return InkWell(
      onTap: () {
        setState(() => _domainId = id);
        _savePrefs();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          if (id != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? kBText : kBText2)),
          ),
          Text('$count',
              style: TextStyle(
                  fontSize: 12,
                  color: count == 0 ? kBText4 : kBText3,
                  fontFeatures: _tabular)),
        ]),
      ),
    );
  }

  // ── Centre ──────────────────────────────────────────────────────────────────

  Widget _center() {
    if (_showPaused) return _pausedList();
    final open = _openSession;
    final now = open == null
        ? const <({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>[]
        : possibleNow(_domainProjects, _domainActivities, open.activityId, filter: _filter);
    final allGroups = projectActionGroups(_domainProjects,
        filter: _filter,
        sort: _sort,
        domainOrder: [for (final d in widget.domains) d.id]);
    final vis = visibleProjectGroups(allGroups, filtering: _filtering && !_showUnmatched);
    final groups = vis.shown;
    final filterLabel = [
      ...(_contexts.toList()..sort()),
      if (_time != null)
        switch (_time!) {
          TimeBucket.quarter => '15 min',
          TimeBucket.hour => '1 h',
          TimeBucket.more => 'plus d\'1 h',
        },
    ].join(' · ');
    final own = ownActionGroups(_domainActivities, filter: _filter);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (open != null) ...[
        _nowCard(open, now),
        const SizedBox(height: 18),
      ],
      _card(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _label('PAR PROJET · PROCHAINE ACTION EN TÊTE')),
            PopupMenuButton<ActionsSort>(
              tooltip: 'Trier',
              onSelected: (s) {
                setState(() => _sort = s);
                _savePrefs();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: ActionsSort.dueDate, child: Text('Échéance')),
                PopupMenuItem(value: ActionsSort.domain, child: Text('Domaine')),
                PopupMenuItem(value: ActionsSort.alpha, child: Text('Alphabétique')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.swap_vert, size: 15, color: kBText3),
                  const SizedBox(width: 4),
                  Text(
                      'Trier · ${switch (_sort) {
                        ActionsSort.dueDate => 'échéance',
                        ActionsSort.domain => 'domaine',
                        ActionsSort.alpha => 'A → Z',
                      }}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: kBText3)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                  allGroups.isEmpty
                      ? 'Aucun projet actif.'
                      : 'Aucune action de projet pour « $filterLabel » pour l\'instant.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: kBText3)),
            )
          else
            for (final g in groups) _projectGroup(g),
          if (_filtering && (vis.hidden > 0 || _showUnmatched))
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                      _showUnmatched
                          ? 'Tous les projets sont affichés.'
                          : '${vis.hidden} projet${vis.hidden > 1 ? 's' : ''} sans action pour « $filterLabel »',
                      style: const TextStyle(fontSize: 12, color: kBText4)),
                ),
                TextButton(
                  onPressed: () => setState(() => _showUnmatched = !_showUnmatched),
                  style: TextButton.styleFrom(
                      foregroundColor: kBPrimary, visualDensity: VisualDensity.compact),
                  child: Text(_showUnmatched ? 'Masquer' : 'Afficher'),
                ),
              ]),
            ),
        ]),
      ),
      if (own.isNotEmpty) ...[
        const SizedBox(height: 18),
        _card(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label('ACTIONS SIMPLES', color: kBText4),
            const SizedBox(height: 8),
            for (final g in own) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(g.activity.name,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: kBText3)),
              ),
              for (final a in g.actions)
                _actionRow(a,
                    height: 38,
                    onToggle: () => _toggleOwnAction(g.activity, a),
                    onMenu: () => _edit(a, activity: g.activity)),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _nowCard(Session open,
      List<({TaskAction action, Project? project, ProjectTask? task, Activity? activity})> items) {
    final act = _activity(open.activityId);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBPrimary.withOpacity(.55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: kBPrimary, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: _label(
                'POSSIBLE MAINTENANT · CHRONO « ${(act?.name ?? 'activité').toUpperCase()} » EN COURS',
                color: kBPrimary),
          ),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Aucune action liée à cette activité — lie une action à ce chrono pour la voir ici.',
                style: TextStyle(fontSize: 12.5, color: kBText3)),
          )
        else
          for (final it in items)
            _actionRow(it.action,
                height: 40,
                subtitle: it.project?.title ?? it.activity?.name,
                onToggle: () => it.project != null
                    ? _toggleProjectAction(it.project!, it.action)
                    : _toggleOwnAction(it.activity!, it.action),
                onMenu: () => _edit(it.action,
                    project: it.project, task: it.task, activity: it.activity)),
      ]),
    );
  }

  Widget _projectGroup(ProjectActions g) {
    final p = g.project;
    final color = domainColor(p.domainId, widget.domains) ?? kBText4;
    final today = DateTime.now();
    final expanded = _expanded.contains(p.id);
    final shown = expanded ? g.entries : g.entries.take(3).toList();
    final hidden = g.entries.length - shown.length;
    final root = rootProjectOf(p, widget.projects);
    final parentPrefix = root.id != p.id && _clientId == null ? '${root.title} › ' : '';
    final daysLeft = p.endDate == null
        ? null
        : DateTime(p.endDate!.year, p.endDate!.month, p.endDate!.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (parentPrefix.isNotEmpty)
                  TextSpan(text: parentPrefix, style: const TextStyle(color: kBText3, fontWeight: FontWeight.w500)),
                TextSpan(text: p.title),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kBText),
            ),
          ),
          if (p.endDate != null) ...[
            const SizedBox(width: 8),
            Text(daysLeftLabel(p.endDate, today),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: daysLeft! < 0
                        ? kBAlert
                        : daysLeft <= 7
                            ? kBAttention
                            : kBText3,
                    fontFeatures: _tabular)),
          ],
          const SizedBox(width: 6),
          _textLink('Ouvrir', () => widget.onOpenProject(p)),
        ]),
      ),
      if (g.entries.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 0, 8),
          child: Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final added = await showQuickAddActionDialog(context, project: p, sync: widget.sync);
                if (added && mounted) setState(() {});
              },
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Définir la prochaine action'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kBText2,
                side: const BorderSide(color: Color(0x33FFFFFF)),
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Sans action, le projet n\'avance pas.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kBText4)),
            ),
          ]),
        )
      else ...[
        for (var i = 0; i < shown.length; i++)
          _actionRow(shown[i].action,
              height: i == 0 ? 42 : 38,
              primary: i == 0,
              subtitle: i == 0 ? shown[i].task.title : null,
              onToggle: () => _toggleProjectAction(p, shown[i].action),
              onMenu: () => _edit(shown[i].action, project: p, task: shown[i].task)),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: _textLink('+ $hidden autre${hidden > 1 ? 's' : ''} action${hidden > 1 ? 's' : ''}',
                () => setState(() => _expanded.add(p.id)),
                muted: true),
          )
        else if (expanded && g.entries.length > 3)
          Align(
            alignment: Alignment.centerLeft,
            child: _textLink('Réduire', () => setState(() => _expanded.remove(p.id)), muted: true),
          ),
      ],
      const Divider(height: 1, color: kBLine),
    ]);
  }

  Widget _actionRow(TaskAction a,
      {required double height,
      bool primary = false,
      String? subtitle,
      required VoidCallback onToggle,
      required VoidCallback onMenu}) {
    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: primary ? const Color(0x08FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 17, color: a.done ? kBPrimaryDark : (primary ? kBText2 : kBText3)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: primary ? 13.5 : 13,
                      fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
                      color: primary ? kBText : kBText2)),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text('· $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: kBText4)),
              ),
            ],
            for (final c in a.allContexts.take(2)) ...[
              const SizedBox(width: 6),
              _badge(c, kBText3),
            ],
            if (a.estimatedMin != null) ...[
              const SizedBox(width: 6),
              _badge('${a.estimatedMin} min', kBText4),
            ],
            if (a.checklist.isNotEmpty) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Checklist : ${a.checklistDone}/${a.checklistTotal}',
                child: checklistBadge(a)!,
              ),
            ],
          ]),
        ),
        IconButton(
          tooltip: 'Éditer, déplacer, supprimer',
          icon: const Icon(Icons.more_horiz, size: 16, color: kBText4),
          visualDensity: VisualDensity.compact,
          onPressed: onMenu,
        ),
      ]),
    );
  }

  Widget _pausedList() {
    final paused = widget.projects.where((p) => p.status != 'archived' && p.paused).toList();
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('EN PAUSE · ${paused.length}'),
        const SizedBox(height: 8),
        if (paused.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Aucun projet en pause.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kBText3)),
          )
        else
          for (final p in paused)
            Container(
              height: 48,
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: domainColor(p.domainId, widget.domains) ?? kBText4,
                        shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: kBText)),
                ),
                _textLink('Ouvrir', () => widget.onOpenProject(p), muted: true),
                const SizedBox(width: 4),
                _pillButton('Reprendre', icon: Icons.play_arrow_outlined, onTap: () => _resume(p)),
              ]),
            ),
      ]),
    );
  }

  // ── Colonne droite ──────────────────────────────────────────────────────────

  Widget _sideColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _engagementsCard(),
      const SizedBox(height: 18),
      _routinesCard(),
    ]);
  }

  Widget _engagementsCard() {
    final domainIds = _domainId == null ? null : {_domainId!};
    final stats = rollingWeekEngagements(
        activities: widget.activities, hits: _hits, domainIds: domainIds);
    final trend = fourWeekTrend(activities: widget.activities, hits: _hits, domainIds: domainIds);
    final kept = stats.where((e) => e.kept).length;
    final prev = trend.length >= 2 ? trend[trend.length - 2].pct : null;
    final cur = trend.isEmpty ? null : trend.last.pct;
    final delta = prev == null || cur == null ? null : cur - prev;

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('MES ENGAGEMENTS · 7 JOURS'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(stats.isEmpty ? '—' : '$kept / ${stats.length}',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: kBText,
                  letterSpacing: -.5,
                  fontFeatures: _tabular)),
          const SizedBox(width: 10),
          if (delta != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${delta >= 0 ? '+' : ''}$delta pts vs S-1',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: delta > 0 ? kBPrimary : (delta < 0 ? kBAttention : kBText3),
                      fontFeatures: _tabular)),
            ),
          const Spacer(),
          _miniBars(trend),
        ]),
        const SizedBox(height: 14),
        if (stats.isEmpty)
          const Text('Aucun engagement hebdo pour l\'instant.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final e in stats)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                Icon(e.kept ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 15, color: e.kept ? kBPrimaryDark : kBText4),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: kBText)),
                ),
                Text('${e.done} / ${e.target}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: e.kept ? FontWeight.w600 : FontWeight.w400,
                        color: e.kept ? kBPrimary : kBText2,
                        fontFeatures: _tabular)),
              ]),
            ),
      ]),
    );
  }

  Widget _miniBars(List<({String label, int pct})> trend) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < trend.length; i++) ...[
        if (i > 0) const SizedBox(width: 5),
        Tooltip(
          message: '${trend[i].label} · ${trend[i].pct} %',
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 12,
              height: 6 + 30 * (trend[i].pct.clamp(0, 100) / 100),
              decoration: BoxDecoration(
                color: i == trend.length - 1 ? kBPrimary : kBPrimary.withOpacity(.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 3),
            Text(trend[i].label,
                style: const TextStyle(fontSize: 9, color: kBText4, fontFeatures: _tabular)),
          ]),
        ),
      ],
    ]);
  }

  Widget _routinesCard() {
    final domainIds = _domainId == null ? null : {_domainId!};
    final routines = todayEngagements(activities: widget.activities, hits: _hits, domainIds: domainIds)
      ..sort((a, b) {
        if (a.kept != b.kept) return a.kept ? 1 : -1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    String? blockTime(String activityId) {
      for (final b in _todayBlocks) {
        if (b.activityId == activityId && b.status == 'pending') return b.startTime;
      }
      return null;
    }
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('ROUTINES DU JOUR'),
        const SizedBox(height: 12),
        if (routines.isEmpty)
          const Text('Aucune routine quotidienne.', style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final r in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: r.kept || _logic == null ? null : () => _checkRoutine(r.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(r.kept ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 17, color: r.kept ? kBPrimaryDark : kBText3),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: r.kept ? kBText3 : kBText,
                          decoration: r.kept ? TextDecoration.lineThrough : null,
                          decorationColor: kBText3)),
                ),
                if (blockTime(r.id) != null) ...[
                  const SizedBox(width: 8),
                  Text(blockTime(r.id)!,
                      style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                ],
                if (r.target > 1) ...[
                  const SizedBox(width: 8),
                  Text('${r.done} / ${r.target}',
                      style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                ],
              ]),
            ),
      ]),
    );
  }

  // ── Briques ─────────────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBLine),
        ),
        child: child,
      );

  Widget _label(String text, {Color color = kBText3}) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: color));

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
      );

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected ? kBActive : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? kBPrimary.withOpacity(.35) : kBLine),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? kBText : kBText2)),
          ),
        ),
      );

  Widget _textLink(String label, VoidCallback onTap, {bool muted = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: muted ? kBText3 : kBPrimary,
                  fontFeatures: _tabular)),
        ),
      );

  Widget _pillButton(String label, {IconData? icon, VoidCallback? onTap}) => SizedBox(
        height: 36,
        child: TextButton.icon(
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16, color: kBText),
          label: Text(label),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0x12FFFFFF),
            foregroundColor: kBText,
            shape: const StadiumBorder(),
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      );
}
