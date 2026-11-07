import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/time_spent.dart' show estimateFactor, estimateFactorLabel, spentByAction;
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;
import 'package:productivitwo_v1/web/action_dialogs.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setChecklistItem, addChecklistItem, setActionDone;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:productivitwo_v1/web/quick_add_action_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Onglet Actions (refonte web § 5, remis en ordre le 2026-11-07) : une phrase
// et les filtres en une ligne de menus, puis la liste pleine page (« Possible
// maintenant » quand un chrono tourne, par projet, à venir, actions simples).

const _tabular = [FontFeature.tabularFigures()];
const _kPrefContexts = 'web.actions.contexts';
const _kPrefTime = 'web.actions.time';
const _kPrefOverdue = 'web.actions.overdue';
const _kPrefDomain = 'web.actions.domain';
const _kPrefSort = 'web.actions.sort';
const _kPrefClient = 'web.actions.client';
const _kPrefView = 'web.actions.by_urgency';

class ActionsView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<Activity> activities;
  final FirestoreSync sync;
  final VoidCallback onRefresh;
  final void Function(Project project, {String? taskId}) onOpenProject;
  final int dayStartMin;

  const ActionsView({
    super.key,
    required this.projects,
    required this.domains,
    required this.activities,
    required this.sync,
    required this.onRefresh,
    required this.onOpenProject,
    this.dayStartMin = kDefaultDayStartMin,
  });

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<ActionsView> {
  final Set<String> _contexts = {};
  TimeBucket? _time;
  // Filtre actif : projets sans action correspondante masqués, sauf demande.
  bool _showUnmatched = false;
  bool _showUpcoming = false;
  // « En retard » : PAR ACTION, sur l'échéance effective (la sienne, sinon
  // celle de la tâche — `isOverdueAction`) ; les actions simples n'ont pas
  // d'échéance de tâche → seules celles datées peuvent être en retard.
  bool _overdue = false;
  bool get _filtering => _contexts.isNotEmpty || _time != null || _overdue || _query.isNotEmpty;
  /// Tâche retenue : jamais une tâche pas encore commencée (elle va dans
  /// « À venir »).
  bool Function(ProjectTask) get _taskFilter {
    final now = _livedToday;
    return (t) => !isUpcomingTask(t, now);
  }

  /// Journée vécue (jour seul) : « aujourd'hui » bascule à l'heure réglée.
  DateTime get _livedToday => livedDate(DateTime.now(), widget.dayStartMin);

  /// Couple tâche + action retenu : avec « En retard », l'échéance effective
  /// de l'action est dépassée.
  bool _entryOk(ProjectTask t, TaskAction a) => !_overdue || isOverdueAction(a, t, _livedToday);
  String? _domainId;
  // « Pour… » : projet racine (client) ; null = tous.
  String? _clientId;
  ActionsSort _sort = ActionsSort.dueDate;
  bool _showPaused = false;
  final Set<String> _expanded = {};

  List<Session> _sessions = [];
  List<ScheduleBlock> _todayBlocks = [];
  StreamSubscription<List<Session>>? _sessionsSub;
  StreamSubscription<DailySchedule?>? _scheduleSub;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _sessionsSub = widget.sync.streamSessions().listen((s) {
      if (mounted) setState(() => _sessions = s);
    });
    _scheduleSub = widget.sync.streamDailySchedule(livedProgramYmd(DateTime.now(), widget.dayStartMin)).listen((s) {
      if (mounted) {
        setState(() => _todayBlocks =
            s?.blocks.where((b) => b.status != 'deleted').toList() ?? []);
      }
    });
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    _sessionsSub?.cancel();
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
        _overdue = p.getBool(_kPrefOverdue) ?? false;
        _domainId = p.getString(_kPrefDomain);
        _clientId = p.getString(_kPrefClient);
        _byUrgency = p.getBool(_kPrefView) ?? true;
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
      _overdue ? await p.setBool(_kPrefOverdue, true) : await p.remove(_kPrefOverdue);
      _domainId == null
          ? await p.remove(_kPrefDomain)
          : await p.setString(_kPrefDomain, _domainId!);
      await p.setString(_kPrefSort, _sort.name);
      _clientId == null
          ? await p.remove(_kPrefClient)
          : await p.setString(_kPrefClient, _clientId!);
      await p.setBool(_kPrefView, _byUrgency);
    } catch (_) {}
  }

  // ── Dérivation ──────────────────────────────────────────────────────────────

  bool _filter(TaskAction a) =>
      passesContexts(a, _contexts) && passesTime(a, _time) && (_query.isEmpty || a.title.toLowerCase().contains(_query));

  List<Project> get _domainProjects => widget.projects
      .where((p) => _domainId == null || p.domainId == _domainId)
      .where((p) => inClient(_clientId, p, widget.projects))
      .where((p) => !isFolderProject(p, widget.projects))
      .toList();

  int _openCountForClient(String? rootId) {
    var n = 0;
    if (!_overdue && (rootId == null || rootId == kPersoClientId)) {
      for (final a in _activitiesInDomain) {
        n += a.ownActions.where((x) => !x.done && _filter(x)).length;
      }
    }
    for (final p in widget.projects) {
      if (p.status != 'active' || p.paused) continue;
      if (_domainId != null && p.domainId != _domainId) continue;
      if (!inClient(rootId, p, widget.projects)) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (!_taskFilter(t)) continue;
        n += t.actions.where((a) => !a.done && _filter(a) && _entryOk(t, a)).length;
      }
    }
    return n;
  }

  /// Activités dont les actions simples sont montrées : un client choisi n'en
  /// a aucune (elles ne sont « pour » personne), « Perso » les a toutes.
  List<Activity> get _domainActivities =>
      _overdue || (_clientId != null && _clientId != kPersoClientId)
          ? const []
          : _activitiesInDomain;

  List<Activity> get _activitiesInDomain => _domainId == null
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
        if (!_taskFilter(t)) continue;
        n += t.actions.where((a) => !a.done && _filter(a) && _entryOk(t, a)).length;
      }
    }
    for (final act in widget.activities) {
      if (_overdue) break;
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
    await widget.sync.patchActionOf(p, a);
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBBg,
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pageHeader(),
        const SizedBox(height: 10),
        _filterBar(),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 26), child: _center()),
            ),
            if (_selectedEntry() case final e?) ...[
              const SizedBox(width: 20),
              SizedBox(width: 420, child: Padding(padding: const EdgeInsets.only(bottom: 20), child: _actionPanel(e))),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── En-tête (2026-11-07, maquette « Web Actions, remis en ordre », lot 1) ──
  // Une phrase, la recherche et « + Action » ; les filtres en une ligne de
  // menus juste dessous (plus de colonne de gauche ni de colonne de droite).

  String _query = '';

  ({int open, int program, int focused, int late, int stale}) _counts() {
    final today = _livedToday;
    final programIds = {
      for (final b in _todayBlocks)
        if (b.actionId != null && b.status == 'pending') b.actionId!,
    };
    var open = 0, program = 0, focused = 0, late = 0, stale = 0;
    void count(TaskAction a, ProjectTask? t) {
      if (a.done) return;
      open++;
      if (programIds.contains(a.id)) program++;
      if (isFocusedOn(a, today)) focused++;
      if (isOverdueAction(a, t, today)) late++;
      if (isStaleFocus(a, today)) stale++;
    }
    for (final p in widget.projects) {
      if (p.status != 'active' || p.paused) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped' || isUpcomingTask(t, today)) continue;
        for (final a in t.actions) {
          count(a, t);
        }
      }
    }
    for (final act in widget.activities) {
      if (act.deleted) continue;
      for (final a in act.ownActions) {
        count(a, null);
      }
    }
    return (open: open, program: program, focused: focused, late: late, stale: stale);
  }

  Widget _pageHeader() {
    final c = _counts();
    final summary = [
      '${c.open} ouverte${c.open > 1 ? 's' : ''}',
      if (c.program > 0) '${c.program} au programme',
      if (c.focused > 0) '${c.focused} visée${c.focused > 1 ? 's' : ''} aujourd’hui',
      if (c.late > 0) '${c.late} en retard',
      if (c.stale > 0) '${c.stale} à re-viser',
    ].join(' · ');
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Actions',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
          const SizedBox(height: 2),
          Text(summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
        ]),
      ),
      const SizedBox(width: 12),
      _viewSwitch(),
      const SizedBox(width: 10),
      SizedBox(
        width: 220,
        height: 36,
        child: TextField(
          key: const ValueKey('actions-search'),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13, color: kBText),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Rechercher',
            hintStyle: const TextStyle(fontSize: 13, color: kBText4),
            prefixIcon: const Icon(Icons.search, size: 16, color: kBText3),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            filled: true,
            fillColor: const Color(0x12FFFFFF),
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _pillButton('Action',
          icon: Icons.add,
          onTap: () async {
            final ok = await showAddOwnActionDialog(context,
                sync: widget.sync, activities: widget.activities, domains: widget.domains.where((d) => !d.deleted).toList());
            if (ok && mounted) setState(() {});
          }),
    ]);
  }

  Widget _menuPill(String label, {required bool active, VoidCallback? onClear}) => Container(
        height: 32,
        padding: EdgeInsets.only(left: 12, right: onClear == null ? 10 : 4),
        decoration: BoxDecoration(
          color: active ? kBActive : const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kBPrimary.withOpacity(.4) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? kBText : kBText2)),
          if (onClear != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onClear,
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 14, color: kBText3)),
            )
          else
            const Padding(padding: EdgeInsets.only(left: 2), child: Icon(Icons.expand_more, size: 16, color: kBText3)),
        ]),
      );

  Widget _filterBar() {
    final contexts = knownContexts(widget.projects, widget.activities);
    final paused = widget.projects.where((p) => p.status != 'archived' && p.paused).length;
    final clients = clientRoots(widget.projects);
    final domains = widget.domains.where((d) => !d.deleted).toList();
    final domainName = domains.where((d) => d.id == _domainId).firstOrNull?.name;
    final clientName = _clientId == null
        ? null
        : _clientId == kPersoClientId
            ? kPersoClientLabel
            : clients.where((c) => c.id == _clientId).firstOrNull?.title;
    String timeLabel(TimeBucket b) => switch (b) {
          TimeBucket.quarter => '15 min',
          TimeBucket.hour => '1 h',
          TimeBucket.more => 'Plus',
        };
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      PopupMenuButton<String>(
        key: const ValueKey('actions-filter-contexts'),
        tooltip: 'Je suis…',
        onSelected: (c) {
          setState(() {
            _contexts.contains(c) ? _contexts.remove(c) : _contexts.add(c);
            _showUnmatched = false;
          });
          _savePrefs();
        },
        itemBuilder: (_) => [
          for (final c in contexts) CheckedPopupMenuItem(value: c, checked: _contexts.contains(c), child: Text(c)),
        ],
        child: _menuPill(
            _contexts.isEmpty ? 'Je suis : partout' : 'Je suis : ${(_contexts.toList()..sort()).join(', ')}',
            active: _contexts.isNotEmpty,
            onClear: _contexts.isEmpty
                ? null
                : () {
                    setState(_contexts.clear);
                    _savePrefs();
                  }),
      ),
      PopupMenuButton<TimeBucket>(
        key: const ValueKey('actions-filter-time'),
        tooltip: 'J’ai…',
        onSelected: (b) {
          setState(() => _time = _time == b ? null : b);
          _savePrefs();
        },
        itemBuilder: (_) => [
          for (final b in TimeBucket.values) CheckedPopupMenuItem(value: b, checked: _time == b, child: Text(timeLabel(b))),
        ],
        child: _menuPill(_time == null ? 'J’ai : du temps' : 'J’ai : ${timeLabel(_time!)}',
            active: _time != null,
            onClear: _time == null
                ? null
                : () {
                    setState(() => _time = null);
                    _savePrefs();
                  }),
      ),
      PopupMenuButton<String>(
        key: const ValueKey('actions-filter-domain'),
        tooltip: 'Domaine',
        onSelected: (id) {
          setState(() => _domainId = id.isEmpty ? null : id);
          _savePrefs();
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: '', checked: _domainId == null, child: Text('Tous · ${_openCountForDomain(null)}')),
          for (final d in domains)
            CheckedPopupMenuItem(
                value: d.id, checked: _domainId == d.id, child: Text('${d.name} · ${_openCountForDomain(d.id)}')),
        ],
        child: _menuPill(domainName == null ? 'Domaine : tous' : 'Domaine : $domainName',
            active: _domainId != null,
            onClear: _domainId == null
                ? null
                : () {
                    setState(() => _domainId = null);
                    _savePrefs();
                  }),
      ),
      if (clients.length > 1)
        PopupMenuButton<String>(
          key: const ValueKey('actions-filter-client'),
          tooltip: 'Pour…',
          onSelected: (id) {
            setState(() {
              _clientId = id.isEmpty ? null : id;
              _showUnmatched = false;
            });
            _savePrefs();
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: '', checked: _clientId == null, child: Text('Tous · ${_openCountForClient(null)}')),
            for (final r in clients)
              CheckedPopupMenuItem(
                  value: r.id, checked: _clientId == r.id, child: Text('${r.title} · ${_openCountForClient(r.id)}')),
            CheckedPopupMenuItem(
                value: kPersoClientId,
                checked: _clientId == kPersoClientId,
                child: Text('$kPersoClientLabel · ${_openCountForClient(kPersoClientId)}')),
          ],
          child: _menuPill(clientName == null ? 'Pour : tous' : 'Pour : $clientName',
              active: _clientId != null,
              onClear: _clientId == null
                  ? null
                  : () {
                      setState(() => _clientId = null);
                      _savePrefs();
                    }),
        ),
      InkWell(
        key: const ValueKey('actions-filter-overdue'),
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() {
            _overdue = !_overdue;
            _showUnmatched = false;
          });
          _savePrefs();
        },
        child: _menuPill('En retard seulement', active: _overdue, onClear: _overdue ? () {
          setState(() => _overdue = false);
          _savePrefs();
        } : null),
      ),
      if (paused > 0 || _showPaused)
        _textLink(_showPaused ? '‹ Actions' : 'En pause · $paused', () => setState(() => _showPaused = !_showPaused),
            muted: !_showPaused),
    ]);
  }

  // ── Centre ──────────────────────────────────────────────────────────────────

  Widget _center() {
    if (_showPaused) return _pausedList();
    final open = _openSession;
    final now = open == null
        ? const <({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>[]
        : possibleNow(_domainProjects, _domainActivities, open.activityId, filter: _filter)
            .where((x) => x.task == null || (_taskFilter(x.task!) && _entryOk(x.task!, x.action)))
            .toList();
    // « J'ai 20 min » + tri par échéance → d'abord ce qui sert la séance la
    // plus proche (brief 2.4) ; le tri explicite « Prochaine séance » fait pareil.
    final today = _livedToday;
    final effectiveSort =
        _time != null && _sort == ActionsSort.dueDate ? ActionsSort.milestone : _sort;
    final allGroups = projectActionGroups(_domainProjects,
        filter: _filter,
        taskFilter: _taskFilter,
        entryFilter: _entryOk,
        sort: effectiveSort,
        domainOrder: [for (final d in widget.domains) d.id],
        urgencyOf: (p) => nextInterventionOf(p, today)?.date);
    final factorLabel = estimateFactorLabel(estimateFactor(widget.projects, spentByAction(_sessions)));
    final vis = visibleProjectGroups(allGroups, filtering: _filtering && !_showUnmatched);
    final groups = vis.shown;
    final filterLabel = [
      if (_overdue) 'en retard',
      ...(_contexts.toList()..sort()),
      if (_time != null)
        switch (_time!) {
          TimeBucket.quarter => '15 min',
          TimeBucket.hour => '1 h',
          TimeBucket.more => 'plus d\'1 h',
        },
    ].join(' · ');
    final own = ownActionGroups(_domainActivities, filter: _filter);
    final upcoming = _overdue
        ? const <({Project project, ProjectTask task, TaskAction action})>[]
        : upcomingActions(_domainProjects, filter: _filter, today: today);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (open != null) ...[
        _nowCard(open, now),
        const SizedBox(height: 18),
      ],
      if (_byUrgency)
        _urgencyCard(allGroups, own, factorLabel)
      else
      _card(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _label('PAR PROJET · PROCHAINE ACTION EN TÊTE')),
            if (factorLabel != null) ...[
              Tooltip(
                message: 'Médiane du temps réel sur le temps estimé (actions faites avec chrono ciblé). '
                    'Sert à corriger vos estimations ; détail : estimate_accuracy via Claude.',
                child: Text(factorLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kBText3)),
              ),
              const SizedBox(width: 14),
            ],
            PopupMenuButton<ActionsSort>(
              tooltip: 'Trier',
              onSelected: (s) {
                setState(() => _sort = s);
                _savePrefs();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: ActionsSort.dueDate, child: Text('Échéance')),
                PopupMenuItem(value: ActionsSort.milestone, child: Text('Prochaine séance')),
                PopupMenuItem(value: ActionsSort.domain, child: Text('Domaine')),
                PopupMenuItem(value: ActionsSort.alpha, child: Text('Alphabétique')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.swap_vert, size: 15, color: kBText3),
                  const SizedBox(width: 4),
                  Text(
                      'Trier · ${switch (effectiveSort) {
                        ActionsSort.dueDate => 'échéance',
                        ActionsSort.milestone => 'prochaine séance',
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
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 18),
        _upcomingCard(upcoming, today),
      ],
      if (own.isNotEmpty && !_byUrgency) ...[
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
                    onMenu: () => _edit(a, activity: g.activity),
                    onOpen: () => _openEntry(_UrgentEntry(a, activity: g.activity))),
            ],
          ]),
        ),
      ],
    ]);
  }

  // ── Par urgence (2026-11-07, lot 2) : comme l'onglet Actions mobile ────────
  // Au programme · visées aujourd'hui · en retard · à re-viser · cette semaine
  // · ensuite (une par projet) · sans projet. Chaque action n'apparaît qu'une
  // fois, dans la première section qui la retient.

  bool _byUrgency = true;
  final Set<String> _urgencyOpen = {};

  Widget _viewSwitch() {
    Widget seg(String label, bool on, VoidCallback onTap, Key key) => InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? kBActive : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? kBPrimary.withOpacity(.35) : Colors.transparent),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? kBText : kBText2)),
          ),
        );
    void set(bool v) {
      setState(() => _byUrgency = v);
      _savePrefs();
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x12FFFFFF), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Par urgence', _byUrgency, () => set(true), const ValueKey('actions-view-urgency')),
        seg('Par projet', !_byUrgency, () => set(false), const ValueKey('actions-view-project')),
      ]),
    );
  }

  Widget _urgencyCard(List<ProjectActions> groups,
      List<({Activity activity, List<TaskAction> actions})> own, String? factorLabel) {
    final today = _livedToday;
    final week = today.add(const Duration(days: 6));
    final blockOf = <String, ScheduleBlock>{
      for (final b in _todayBlocks)
        if (b.actionId != null && b.status == 'pending') b.actionId!: b,
    };
    final seen = <String>{};
    final sections = <String, List<_UrgentEntry>>{
      'program': [], 'focus': [], 'late': [], 'stale': [], 'week': [], 'next': [], 'own': [],
    };
    void place(_UrgentEntry e) {
      final a = e.action;
      if (seen.contains(a.id)) return;
      final key = blockOf.containsKey(a.id)
          ? 'program'
          : isFocusedOn(a, today)
              ? 'focus'
              : isOverdueAction(a, e.task, today)
                  ? 'late'
                  : isStaleFocus(a, today)
                      ? 'stale'
                      : _inWeek(workDate(a, e.task), week)
                          ? 'week'
                          : null;
      if (key == null) return;
      seen.add(a.id);
      sections[key]!.add(e);
    }
    final all = <_UrgentEntry>[
      for (final g in groups)
        for (final x in g.entries) _UrgentEntry(x.action, project: g.project, task: x.task),
      for (final g in own)
        for (final a in g.actions) _UrgentEntry(a, activity: g.activity),
    ];
    for (final e in all) {
      place(e);
    }
    for (final g in groups) {
      final first = g.entries.where((x) => !seen.contains(x.action.id)).firstOrNull;
      if (first == null || g.entries.any((x) => seen.contains(x.action.id))) continue;
      seen.add(first.action.id);
      sections['next']!.add(_UrgentEntry(first.action, project: g.project, task: first.task));
    }
    for (final g in own) {
      for (final a in g.actions) {
        if (seen.add(a.id)) sections['own']!.add(_UrgentEntry(a, activity: g.activity));
      }
    }
    int byWork(_UrgentEntry x, _UrgentEntry y) {
      final wx = workDate(x.action, x.task), wy = workDate(y.action, y.task);
      if (wx == null || wy == null) return wx == null ? (wy == null ? 0 : 1) : -1;
      return wx.compareTo(wy);
    }
    sections['program']!.sort((x, y) =>
        blockStartMin(blockOf[x.action.id]!).compareTo(blockStartMin(blockOf[y.action.id]!)));
    for (final k in const ['late', 'stale', 'week']) {
      sections[k]!.sort(byWork);
    }
    const titles = {
      'program': ('AU PROGRAMME AUJOURD’HUI', kBPrimary),
      'focus': ('VISÉES AUJOURD’HUI', kBAttention),
      'late': ('EN RETARD', kBAlert),
      'stale': ('À RE-VISER · VISÉES UN JOUR PASSÉ', kBAttention),
      'week': ('CETTE SEMAINE', kBText3),
      'next': ('ENSUITE · UNE PAR PROJET', kBText3),
      'own': ('SANS PROJET', kBText3),
    };
    final total = sections.values.fold<int>(0, (n, l) => n + l.length);
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (factorLabel != null)
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'Médiane du temps réel sur le temps estimé (actions faites avec chrono ciblé).',
              child: Text(factorLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kBText3)),
            ),
          ),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_filtering ? 'Aucune action pour ce filtre.' : 'Aucune action ouverte.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kBText3)),
          ),
        for (final e in titles.entries)
          if (sections[e.key]!.isNotEmpty)
            ..._urgencySection(e.key, e.value.$1, e.value.$2, sections[e.key]!, blockOf),
      ]),
    );
  }

  static bool _inWeek(DateTime? w, DateTime week) =>
      w != null && !DateTime(w.year, w.month, w.day).isAfter(week);

  List<Widget> _urgencySection(String key, String title, Color color, List<_UrgentEntry> items,
      Map<String, ScheduleBlock> blockOf) {
    const cap = 6;
    final open = _urgencyOpen.contains(key);
    final shown = open ? items : items.take(cap).toList();
    final today = _livedToday;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Row(children: [
          Text(title,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: color)),
          const SizedBox(width: 8),
          Text('${items.length}', style: const TextStyle(fontSize: 12, color: kBText4, fontFeatures: _tabular)),
        ]),
      ),
      for (final e in shown)
        _entryRow(e,
            state: switch (key) {
              'program' => (text: 'bloc ${blockOf[e.action.id]!.startTime}', color: kBPrimary),
              'focus' => (text: '☀ visée', color: kBAttention),
              'late' => (
                  text: '⚑ ${actionDueLabel(effectiveDueDate(e.action, e.task)!, today)}',
                  color: kBAlert
                ),
              'stale' => (text: '☀ ${focusLabel(e.action.focusDate!, today)}', color: kBAttention),
              'week' => (
                  text: e.action.focusDate != null
                      ? '☀ ${focusLabel(e.action.focusDate!, today)}'
                      : '⚑ ${actionDueLabel(effectiveDueDate(e.action, e.task)!, today)}',
                  color: kBText3
                ),
              _ => null,
            },
            late: key == 'late'),
      if (items.length > cap)
        Align(
          alignment: Alignment.centerLeft,
          child: _textLink(open ? 'Réduire' : '+ ${items.length - cap} autre${items.length - cap > 1 ? 's' : ''}',
              () => setState(() => open ? _urgencyOpen.remove(key) : _urgencyOpen.add(key)),
              muted: true),
        ),
    ];
  }

  void _toggleEntry(_UrgentEntry e) =>
      e.project != null ? _toggleProjectAction(e.project!, e.action) : _toggleOwnAction(e.activity!, e.action);

  void _openEntry(_UrgentEntry e) => setState(() => _selectedId = _selectedId == e.action.id ? null : e.action.id);

  Widget _entryRow(_UrgentEntry e, {({String text, Color color})? state, bool late = false}) {
    final a = e.action;
    final where = e.project != null
        ? '${e.project!.title} › ${e.task!.title}'
        : '${e.activity?.name ?? 'Action'} · sans projet';
    return InkWell(
      key: ValueKey('actions-entry-${a.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openEntry(e),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: _selectedId == a.id ? kBActive : Colors.transparent,
          border: const Border(top: BorderSide(color: kBLine)),
        ),
        child: Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleEntry(e),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18, color: a.done ? kBPrimaryDark : (late ? kBAlert : kBText3)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(where,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kBText3)),
              const SizedBox(height: 1),
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: a.done ? kBText3 : kBText,
                      decoration: a.done ? TextDecoration.lineThrough : null)),
            ]),
          ),
          if (state != null) ...[
            const SizedBox(width: 8),
            _badge(state.text, state.color),
          ],
          if (a.checklist.isNotEmpty) ...[
            const SizedBox(width: 6),
            checklistBadge(a)!,
          ],
          if (a.estimatedMin != null) ...[
            const SizedBox(width: 8),
            Text('≈ ${a.estimatedMin} min', style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
          ],
          IconButton(
            tooltip: 'Éditer, déplacer, supprimer',
            icon: const Icon(Icons.more_horiz, size: 16, color: kBText4),
            visualDensity: VisualDensity.compact,
            onPressed: () => _edit(a, project: e.project, task: e.task, activity: e.activity),
          ),
        ]),
      ),
    );
  }

  // ── Panneau d'action (2026-11-07, lot 3) : l'action ouverte à droite ──────
  // Chemin complet, état, étapes cochables (+ ajouter), détail, Lancer le chrono
  // / Action faite, puis Viser demain · Modifier · Ouvrir le projet. L'action
  // est relue par son id à chaque dessin (les listes se reconstruisent).

  String? _selectedId;
  final TextEditingController _stepCtrl = TextEditingController();

  _UrgentEntry? _selectedEntry() {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in widget.projects) {
      for (final t in p.tasks) {
        for (final a in t.actions) {
          if (a.id == id) return _UrgentEntry(a, project: p, task: t);
        }
      }
    }
    for (final act in widget.activities) {
      for (final a in act.ownActions) {
        if (a.id == id) return _UrgentEntry(a, activity: act);
      }
    }
    return null;
  }

  Future<void> _saveEntry(_UrgentEntry e) async {
    if (e.project != null) {
      await widget.sync.patchActionOf(e.project!, e.action);
    } else if (e.activity != null) {
      await widget.sync.updateOwnActions(e.activity!.id, e.activity!.ownActions);
    }
  }

  String? _chronoActivityOf(_UrgentEntry e) =>
      e.action.linkedActivityId ?? e.project?.linkedActivityId ?? e.activity?.id;

  Future<void> _startEntryChrono(_UrgentEntry e) async {
    final activityId = _chronoActivityOf(e);
    if (activityId == null) return;
    final now = DateTime.now();
    for (final s in _sessions.where((s) => s.endAt == null)) {
      s.endAt = now;
      await widget.sync.saveSession(s);
    }
    await widget.sync
        .saveSession(Session(activityId: activityId, startAt: now, taskId: e.task?.id, actionId: e.action.id));
    _panelSnack('Chrono lancé · ${e.action.title}');
  }

  Future<void> _stopChrono(Session s) async {
    s.endAt = DateTime.now();
    await widget.sync.saveSession(s);
    if (mounted) setState(() {});
  }

  void _panelSnack(String msg, {VoidCallback? undo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: undo == null ? 2 : 5),
        action: undo == null ? null : SnackBarAction(label: 'Annuler', textColor: kBPrimary, onPressed: undo),
      ));
  }

  Future<void> _setDone(_UrgentEntry e, bool done) async {
    final a = e.action;
    final before = [for (final c in a.checklist) c.done];
    setState(() => setActionDone(a, done));
    await _saveEntry(e);
    if (!done) return;
    _panelSnack('« ${a.title} » faite', undo: () async {
      setState(() {
        a.done = false;
        a.doneAt = null;
        for (var i = 0; i < a.checklist.length && i < before.length; i++) {
          a.checklist[i].done = before[i];
          if (!before[i]) a.checklist[i].doneAt = null;
        }
      });
      await _saveEntry(e);
    });
  }

  Future<void> _focusTomorrow(_UrgentEntry e) async {
    final a = e.action;
    final old = a.focusDate;
    setState(() => a.focusDate = _livedToday.add(const Duration(days: 1)));
    await _saveEntry(e);
    _panelSnack('Visée demain · ${a.title}', undo: () async {
      setState(() => a.focusDate = old);
      await _saveEntry(e);
    });
  }

  Widget _panelChip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color, fontFeatures: _tabular)),
      );

  Widget _actionPanel(_UrgentEntry e) {
    final a = e.action;
    final today = _livedToday;
    final p = e.project;
    final root = p == null ? null : rootProjectOf(p, widget.projects);
    final where = p != null
        ? '${root != null && root.id != p.id ? '${root.title} › ' : ''}${p.title} › ${e.task!.title}'
        : '${e.activity?.name ?? 'Action'} · sans projet';
    final spent = spentByAction(_sessions)[a.id] ?? 0;
    final block = _todayBlocks.where((b) => b.actionId == a.id && b.status == 'pending').firstOrNull;
    final running = _sessions.where((s) => s.endAt == null && s.actionId == a.id).firstOrNull;
    final chronoId = _chronoActivityOf(e);
    final due = effectiveDueDate(a, e.task);
    final doneSteps = a.checklist.where((c) => c.done).length;
    return Container(
      key: const ValueKey('actions-panel'),
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2219),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A5A4A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label('ACTION')),
          IconButton(
            key: const ValueKey('actions-panel-close'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18, color: kBText3),
            onPressed: () => setState(() => _selectedId = null),
          ),
        ]),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(right: 8), children: [
            Text(where, style: const TextStyle(fontSize: 12, color: kBText3, height: 1.35)),
            const SizedBox(height: 4),
            Text(a.title,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: a.done ? kBText3 : kBText,
                    decoration: a.done ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (a.done) _panelChip('faite', kBPrimary),
              if (running != null) _panelChip('chrono en cours', kBPrimary),
              if (block != null) _panelChip('bloc ${block.startTime}', kBPrimary),
              if (a.focusDate != null)
                _panelChip('☀ ${focusLabel(a.focusDate!, today)}', isStaleFocus(a, today) ? kBAttention : kBPrimary),
              if (due != null)
                _panelChip('⚑ ${actionDueLabel(due, today)}', isOverdueAction(a, e.task, today) ? kBAlert : kBText3),
              if (a.estimatedMin != null || spent > 0)
                _panelChip(
                    [
                      if (a.estimatedMin != null) '≈ ${a.estimatedMin} min',
                      if (spent > 0) '${spent} min passées',
                    ].join(' · '),
                    kBText2),
              for (final c in a.allContexts) _panelChip(c, kBText3),
            ]),
            const SizedBox(height: 16),
            _label(a.checklist.isEmpty ? 'ÉTAPES' : 'ÉTAPES · $doneSteps / ${a.checklist.length}'),
            const SizedBox(height: 4),
            for (final c in a.checklist)
              InkWell(
                key: ValueKey('actions-step-${c.id}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  setState(() => setChecklistItem(a, c.id, !c.done));
                  await _saveEntry(e);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(c.done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18, color: c.done ? kBPrimary : kBText3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(c.title,
                          style: TextStyle(
                              fontSize: 13.5,
                              color: c.done ? kBText3 : kBText,
                              decoration: c.done ? TextDecoration.lineThrough : null)),
                    ),
                  ]),
                ),
              ),
            TextField(
              key: const ValueKey('actions-step-add'),
              controller: _stepCtrl,
              style: const TextStyle(fontSize: 13.5, color: kBText),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '+ Ajouter une étape',
                hintStyle: TextStyle(fontSize: 13, color: kBPrimary),
                border: InputBorder.none,
              ),
              onSubmitted: (v) async {
                final title = v.trim();
                if (title.isEmpty) return;
                setState(() => addChecklistItem(a, title));
                _stepCtrl.clear();
                await _saveEntry(e);
              },
            ),
            if ((a.note ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _label('DÉTAIL'),
              const SizedBox(height: 4),
              Text(a.note!.trim(), style: const TextStyle(fontSize: 13, color: kBText2, height: 1.45)),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: running != null
                ? _wideButton('Arrêter le chrono', () => _stopChrono(running), key: const ValueKey('actions-panel-stop'))
                : chronoId != null && !a.done
                    ? _wideButton('Lancer le chrono', () => _startEntryChrono(e), key: const ValueKey('actions-panel-start'))
                    : _wideButton(a.done ? 'Rouvrir' : 'Action faite', () => _setDone(e, !a.done),
                        key: const ValueKey('actions-panel-done')),
          ),
          if ((running != null || chronoId != null) && !a.done) ...[
            const SizedBox(width: 8),
            _pillButton('Action faite', onTap: () => _setDone(e, true)),
          ],
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          if (!a.done) _textLink('☀ Viser demain', () => _focusTomorrow(e), muted: true),
          _textLink('Modifier', () => _edit(a, project: e.project, task: e.task, activity: e.activity), muted: true),
          if (p != null) _textLink('Ouvrir le projet', () => widget.onOpenProject(p, taskId: e.task?.id), muted: true),
        ]),
      ]),
    );
  }

  Widget _wideButton(String label, VoidCallback onTap, {Key? key}) => SizedBox(
        height: 40,
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: kBPrimary,
            foregroundColor: kBBg,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      );

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
                    project: it.project, task: it.task, activity: it.activity),
                onOpen: () => _openEntry(_UrgentEntry(it.action, project: it.project, task: it.task, activity: it.activity))),
      ]),
    );
  }

  /// Projet dont les actions ouvertes sont toutes à venir : date de la
  /// première et nombre — pas de « Définir la prochaine action » trompeur.
  ({DateTime start, int count})? _nextUpcomingOf(Project p) {
    final u = upcomingActions([p], filter: _filter, today: _livedToday);
    return u.isEmpty ? null : (start: u.first.task.startDate, count: u.length);
  }

  Widget _projectGroup(ProjectActions g) {
    final p = g.project;
    final color = domainColor(p.domainId, widget.domains) ?? kBText4;
    final today = _livedToday;
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
      if (_nextUpcomingOf(p) case final next? when g.entries.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 0, 8),
          child: Text(
              'Prochaine action ${upcomingLabel(next.start, _livedToday)} · '
              '${next.count} à venir',
              style: const TextStyle(fontSize: 12.5, color: kBText3)),
        )
      else if (g.entries.isEmpty)
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
              onMenu: () => _edit(shown[i].action, project: p, task: shown[i].task),
              onOpen: () => _openEntry(_UrgentEntry(shown[i].action, project: p, task: shown[i].task))),
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

  /// « À venir · n » : actions des tâches pas encore commencées, repliées, par
  /// date de début. Cochables et éditables (prendre de l'avance reste possible).
  Widget _upcomingCard(
      List<({Project project, ProjectTask task, TaskAction action})> upcoming, DateTime today) {
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _showUpcoming = !_showUpcoming),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: _label('À VENIR · ${upcoming.length} · PAS ENCORE COMMENCÉES', color: kBText4)),
              Icon(_showUpcoming ? Icons.expand_less : Icons.expand_more, size: 18, color: kBText3),
            ]),
          ),
        ),
        if (_showUpcoming) ...[
          const SizedBox(height: 6),
          for (final u in upcoming)
            _actionRow(u.action,
                height: 38,
                subtitle: '${upcomingLabel(u.task.startDate, today)} · ${u.project.title} › ${u.task.title}',
                onToggle: () => _toggleProjectAction(u.project, u.action),
                onMenu: () => _edit(u.action, project: u.project, task: u.task),
                onOpen: () => _openEntry(_UrgentEntry(u.action, project: u.project, task: u.task))),
        ],
      ]),
    );
  }

  Widget _actionRow(TaskAction a,
      {required double height,
      bool primary = false,
      String? subtitle,
      required VoidCallback onToggle,
      required VoidCallback onMenu,
      VoidCallback? onOpen}) {
    final selected = _selectedId == a.id;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Container(
      height: height,
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: selected
            ? kBActive
            : primary
                ? const Color(0x08FFFFFF)
                : Colors.transparent,
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
            if (a.focusDate != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Jour visé : quand tu veux l\'avoir sous la main (ni créneau, ni retard)',
                child: _badge('☀ ${focusLabel(a.focusDate!, _livedToday)}',
                    isStaleFocus(a, _livedToday) ? kBAttention : kBPrimary),
              ),
            ],
            if (a.dueDate != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Échéance propre de l\'action (prime sur la tâche)',
                child: _badge('⚑ ${actionDueLabel(a.dueDate!, _livedToday)}',
                    a.dueDate!.isBefore(_livedToday)
                        ? kBAttention
                        : kBText3),
              ),
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
    ),
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


/// Une action dans la vue par urgence : de projet (projet + tâche) ou simple
/// (activité porteuse).
class _UrgentEntry {
  final TaskAction action;
  final Project? project;
  final ProjectTask? task;
  final Activity? activity;
  const _UrgentEntry(this.action, {this.project, this.task, this.activity});
}
