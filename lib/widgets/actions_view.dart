import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/project_moment.dart' show rankProjectMoments;
import 'package:productivitwo_v1/widgets/mode_sheet.dart' show modeChipFor;
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/widgets/capture_triage_sheet.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show nextInterventionOf;
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/time_spent.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/moment_card.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show StepDots;
import 'package:productivitwo_v1/widgets/status_row.dart';
import 'package:productivitwo_v1/widgets/steps_section.dart';
import 'package:productivitwo_v1/widgets/next_actions_section.dart'
    show showCreateActionOrProjectSheet;
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onglet « Actions » (refonte 2026-10, handoff `docs/specs/actions-mobile-2026-10`) :
/// le canal « pull » GTD du mobile. Jamais vide : toutes les actions ouvertes,
/// par urgence (Maintenant · Aujourd'hui · En retard · Cette semaine · par
/// projet · actions simples) ou par projet. Filtres optionnels « J'ai… »,
/// « Je suis @… » (partagé avec Maintenant via nowContexts) et Domaine.
/// Tap = feuille d'action (étapes, chrono, caser, fait) ; glisser à droite =
/// fait, à gauche = caser demain ; appui long = fiche projet. Capture rapide
/// en tête → boîte d'entrée. Logique pure partagée avec le web
/// (`utils/actions_logic.dart`).
class ActionsView extends StatefulWidget {
  final AppLogic logic;
  final void Function(Activity activity, Project project, ProjectTask task)?
      onStartTimer;

  const ActionsView({super.key, required this.logic, this.onStartTimer});

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

/// Une action affichable, avec son porteur.
class _Entry {
  final TaskAction action;
  final Project? project; // null = action propre d'une activité
  final ProjectTask? task;
  final Activity? activity; // porteur (action propre) ou activité liée

  _Entry({required this.action, this.project, this.task, this.activity});

  /// Activité effective : porteur (action propre) > lien propre de l'action
  /// > lien hérité du projet.
  String? get chronoActivityId =>
      activity?.id ?? action.linkedActivityId ?? project?.linkedActivityId;

  /// Porteur affiché dans la ligne de détail.
  String get holder => project?.title ?? activity?.name ?? '';
}

class _ActionsViewState extends State<ActionsView> {
  final _sync = FirestoreSync();

  // Section « Terminées » repliée par défaut (consultation ponctuelle).
  bool _showDone = false;
  bool _showUpcoming = false;
  bool _showResting = false;
  // Section « En pause » repliée par défaut (même logique : consultation
  // ponctuelle, réactivation en un tap).
  bool _showPaused = false;
  // Filtres repliés sous la carte du moment (« une carte, une fiche », lot 2).
  bool _filtersOpen = false;
  bool _filtersAutoOpened = false;

  AppState get _state => widget.logic.state;

  // Filtre « Domaine de vie » (au-dessus de JE SUIS…) : multi, vide = tous.
  // Persisté localement (SharedPreferences), comme les filtres de l'app web.
  static const _kDomainPrefKey = 'actions_domain_filter';
  Set<String> _domainFilter = {};

  Future<void> _loadDomainFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kDomainPrefKey) ?? const [];
    if (mounted && ids.isNotEmpty) setState(() => _domainFilter = ids.toSet());
  }

  Future<void> _toggleDomain(String id) async {
    setState(() {
      _domainFilter.contains(id) ? _domainFilter.remove(id) : _domainFilter.add(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kDomainPrefKey, _domainFilter.toList());
  }

  /// Domaine d'une entrée : celui du projet, sinon celui de l'activité.
  String? _domainOf(_Entry e) => e.project?.domainId ?? e.activity?.domainId;

  // Filtre « Pour… » (client = projet racine, dossier compris) : mono, null =
  // tous. Même clé de lecture que le web (`rootProjectOf`).
  static const _kClientPrefKey = 'actions_client_filter';
  String? _clientFilter;

  Future<void> _loadClientFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kClientPrefKey);
    if (mounted && id != null) setState(() => _clientFilter = id);
  }

  Future<void> _setClient(String? id) async {
    setState(() => _clientFilter = id);
    final prefs = await SharedPreferences.getInstance();
    id == null ? await prefs.remove(_kClientPrefKey) : await prefs.setString(_kClientPrefKey, id);
  }

  List<Project> get _allProjects => widget.logic.currentProjects;

  String _rootIdOf(Project p) => rootProjectOf(p, _allProjects).id;

  /// Client choisi = ses projets seulement ; « Perso » = les actions simples.
  bool _inClient(Project? p) => inClient(_clientFilter, p, _allProjects);

  // « J'ai… » : 15 min · 1 h · plus (null = tout). Persisté.
  static const _kTimePrefKey = 'actions_time_filter';
  TimeBucket? _time;
  // Regroupement : par urgence (défaut) ou par projet. Persisté.
  static const _kByProjectPrefKey = 'actions_by_project';
  bool _byProject = false;
  // Programme du jour : points « planifiée aujourd'hui » + section Maintenant.
  StreamSubscription<DailySchedule?>? _schedSub;
  List<ScheduleBlock> _todayBlocks = const [];
  /// « Une liste, un seul bloc ouvert » : l'action du moment est l'item ouvert
  /// par défaut ; calculée au début de chaque build.
  final _open = OpenItem();
  final _scroll = ScrollController();
  ActionMoment? _moment;
  // Captures en attente (boîte d'entrée) : ligne « n captures à trier ».
  List<CaptureItem> _pendingCaptures = const [];
  StreamSubscription<List<CaptureItem>>? _captureSub;
  final _captureCtrl = TextEditingController();
  final _captureFocus = FocusNode();
  // Recherche (loupe de l'en-tête) : filtre en direct, les sections restent.
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String get _query => _searchCtrl.text.trim();

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final t = prefs.getString(_kTimePrefKey);
    setState(() {
      _time = TimeBucket.values.where((b) => b.name == t).firstOrNull;
      _byProject = prefs.getBool(_kByProjectPrefKey) ?? false;
    });
  }

  Future<void> _setTime(TimeBucket? b) async {
    setState(() => _time = b);
    final prefs = await SharedPreferences.getInstance();
    if (b == null) {
      await prefs.remove(_kTimePrefKey);
    } else {
      await prefs.setString(_kTimePrefKey, b.name);
    }
  }

  Future<void> _setByProject(bool v) async {
    setState(() => _byProject = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kByProjectPrefKey, v);
  }

  void _subscribeCaptures() {
    _captureSub?.cancel();
    _captureSub = _sync.streamCaptures().listen((items) {
      if (!mounted) return;
      setState(() => _pendingCaptures = items.where((i) => i.status == 'pending').toList());
    });
  }

  void _subscribeToday() {
    _schedSub?.cancel();
    _schedSub = _sync.streamDailySchedule(widget.logic.livedTodayYmd).listen((sch) {
      if (!mounted) return;
      setState(() => _todayBlocks =
          sch?.blocks.where((b) => b.status != 'deleted').toList() ?? const []);
    });
  }

  // À l'écoute d'AppLogic : un contexte ajouté depuis une fiche/dialog doit
  // apparaître SANS changer d'onglet (constaté sur build — la vue n'était
  // rafraîchie que par les rebuilds du parent).
  @override
  void initState() {
    super.initState();
    widget.logic.addListener(_onLogicChange);
    _loadDomainFilter();
    _loadClientFilter();
    _loadPrefs();
    _subscribeToday();
    _subscribeCaptures();
  }

  @override
  void dispose() {
    _scroll.dispose();
    widget.logic.removeListener(_onLogicChange);
    _schedSub?.cancel();
    _captureSub?.cancel();
    _captureCtrl.dispose();
    _captureFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onLogicChange() {
    if (mounted) setState(() {});
  }

  // ── Dérivation : actions ouvertes (logique partagée avec le web) ──────────

  /// Toutes les actions ouvertes des projets actifs non en pause (prochaine
  /// action du projet en tête, puis ordre Gantt) et des activités.
  List<_Entry> _openEntries() {
    final out = <_Entry>[];
    for (final g in projectActionGroups(widget.logic.currentProjects, filter: (_) => true)) {
      for (final e in g.entries) {
        out.add(_Entry(action: e.action, project: g.project, task: e.task));
      }
    }
    for (final g in ownActionGroups(_state.activeActivities, filter: (_) => true)) {
      for (final a in g.actions) {
        out.add(_Entry(action: a, activity: g.activity));
      }
    }
    return out;
  }

  /// Projets actifs sans aucune action ouverte → « Définir la prochaine action ».
  List<Project> _projectsNeedingNext() => [
        for (final g in projectActionGroups(widget.logic.currentProjects, filter: (_) => true))
          if (g.entries.isEmpty && !isFolderProject(g.project, _allProjects)) g.project,
      ];

  /// Ids des actions portées par un bloc du programme d'aujourd'hui.
  Set<String> get _todayActionIds =>
      {for (final b in _todayBlocks) if (b.actionId != null) b.actionId!};

  /// Minutes réellement passées par action (chrono ciblé), recalculées au build.
  Map<String, int> _spent = const {};

  /// Chrono en cours (session ouverte), sinon null.
  Session? get _running => _state.sessions.where((s) => s.endAt == null).firstOrNull;

  /// Entrée correspondant à une action ciblée par un bloc (projet ou activité).
  _Entry? _entryForBlock(ScheduleBlock b, List<_Entry> all) {
    if (b.actionId != null) {
      final direct = all.where((e) => e.action.id == b.actionId).firstOrNull;
      if (direct != null) return direct;
    }
    final p = widget.logic.currentProjects.firstWhereOrNull((x) => x.id == b.projectId);
    final r = resolveBlockAction(p, b);
    if (r == null) return null;
    return all.where((e) => e.action.id == r.action.id).firstOrNull;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime today0OrNow() => _day(DateTime.now());
  static const _newColor = Color(0xFF6FA8FF);

  /// Échéance de l'entrée (tâche porteuse), à minuit ; null pour une action simple.
  /// Échéance effective : celle de l'action si posée, sinon celle de la tâche.
  DateTime? _dueOf(_Entry e) => effectiveDueDate(e.action, e.task);

  /// Actions VALIDÉES (projets — tous statuts — + actions simples), les plus
  /// récentes d'abord : retrouver ce qui a été fait, et décocher au besoin.
  List<_Entry> _doneEntries() {
    final out = <_Entry>[];
    for (final p in widget.logic.currentProjects) {
      for (final t in p.tasks) {
        for (final a in t.actions.where((a) => a.done)) {
          out.add(_Entry(action: a, project: p, task: t));
        }
      }
    }
    for (final act in _state.activeActivities) {
      for (final a in act.ownActions.where((a) => a.done)) {
        out.add(_Entry(action: a, activity: act));
      }
    }
    out.sort((x, y) => (y.action.doneAt ?? y.action.createdAt)
        .compareTo(x.action.doneAt ?? x.action.createdAt));
    return out;
  }

  String _doneLabel(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'aujourd\'hui';
    if (diff == 1) return 'hier';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> _toggleDone(_Entry e, bool done) async {
    e.action.done = done;
    e.action.doneAt = done ? DateTime.now() : null;
    // Décocher depuis « Terminées » : une tâche close (toutes actions faites)
    // doit se rouvrir, sinon l'action restaurée resterait invisible en attente.
    if (!done && e.task != null && e.task!.status != 'pending') {
      e.task!.status = 'pending';
    }
    // Optimiste : pas d'await sur l'ack serveur (hors-ligne il n'arrive
    // jamais — la coche restait sans effet jusqu'au prochain rebuild).
    if (e.project != null) {
      unawaited(_sync.saveProjectTasks(e.project!.id, e.project!.tasks));
    } else if (e.activity != null) {
      unawaited(_sync.updateOwnActions(e.activity!.id, e.activity!.ownActions));
    }
    widget.logic.onChange();
    if (mounted) setState(() {});
    // Égrainage GTD : la dernière action du projet vient d'être cochée —
    // c'est LE moment de définir la suivante (le réflexe se forge à la
    // complétion, pas à la planification).
    final p = e.project;
    if (done && p != null && mounted) {
      final hasPending = p.tasks
          .where((t) =>
              !t.isMilestone && t.status != 'done' && t.status != 'skipped')
          .any((t) => t.actions.any((a) => !a.done));
      if (!hasPending) await _quickAddAction(p, followUp: true);
    }
  }

  // ── Ajout direct d'action au projet (la couche tâches est ignorée) ────────

  /// Tâche-réceptacle des actions ajoutées au fil de l'eau : id stable,
  /// invisible dans la liste (seules les actions s'affichent), visible dans
  /// la fiche projet/Gantt comme n'importe quelle tâche.
  static const _flowTaskId = kFlowTaskId;

  ProjectTask _flowTask(Project p) => flowTaskOf(p);

  /// Dialog rapide titre + contextes → action directement dans le projet.
  /// CHAÎNABLE : « Ajouter » enregistre, vide le champ et garde le dialog
  /// ouvert (contextes conservés) pour saisir plusieurs prochaines actions
  /// d'affilée ; « Terminer » ferme.
  /// [followUp] = égrainage après complétion (« Et la prochaine ? »).
  Future<void> _quickAddAction(Project p, {bool followUp = false}) async {
    final ctrl = TextEditingController();
    var pickedContexts = <String>[];
    var added = 0;
    // Rattachement à une tâche EXISTANTE du projet (sinon « Au fil de l'eau »).
    // Les jalons et tâches closes sont exclus (leurs actions n'apparaissent
    // pas dans l'onglet Actions — l'action serait invisible).
    final openTasks = p.tasks
        .where((t) =>
            t.id != _flowTaskId &&
            !t.isMilestone &&
            t.status != 'done' &&
            t.status != 'skipped')
        .toList();
    String? pickedTaskId; // null = « Au fil de l'eau »
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> add() async {
          final v = ctrl.text.trim();
          if (v.isEmpty) return;
          final t = pickedTaskId == null
              ? _flowTask(p)
              : p.tasks.firstWhere((x) => x.id == pickedTaskId);
          t.actions.add(TaskAction(
            title: v,
            context: pickedContexts.isEmpty ? null : pickedContexts.first,
            contexts: List.of(pickedContexts),
            estimatedMin: defaultEstimateFor(v, contexts: pickedContexts),
          ));
          setLocal(() {
            added++;
            ctrl.clear();
          });
          // Optimiste : pas d'await sur l'ack serveur (hors-ligne il
          // n'arrive jamais — l'ajout chaînable resterait bloqué).
          unawaited(_sync.saveProjectTasks(p.id, p.tasks));
          widget.logic.onChange();
          if (mounted) setState(() {});
        }

        return AlertDialog(
          // Beaucoup de contextes : sans scroll, les chips passaient SOUS
          // les boutons Annuler/Ajouter (constaté sur build).
          scrollable: true,
          title: Text(followUp
              ? 'Et la prochaine action ?'
              : 'Prochaine action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurface
                          .withOpacity(.55))),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'La prochaine action concrète…'),
                onSubmitted: (_) => add(),
              ),
              // Rattachement AVANT les contextes : sous les 8+ chips, le
              // sélecteur passait sous la ligne de flottaison du dialog
              // scrollable (clavier ouvert) — invisible sans scroller.
              if (openTasks.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  value: pickedTaskId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rattacher à une tâche',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Au fil de l\'eau'),
                    ),
                    for (final t in openTasks)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setLocal(() => pickedTaskId = v),
                ),
              ],
              const SizedBox(height: 12),
              ContextPicker(
                values: pickedContexts,
                sync: _sync,
                onValuesChanged: (list) => pickedContexts = list,
              ),
              if (added > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      added == 1
                          ? '1 action ajoutée — enchaîne ou termine.'
                          : '$added actions ajoutées — enchaîne ou termine.',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(.5))),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(added > 0
                    ? 'Terminer'
                    : (followUp ? 'Plus tard' : 'Annuler'))),
            FilledButton(
              onPressed: add,
              child: const Text('Ajouter'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
  }

  void _openProject(Project p, {String? targetTaskId}) {
    showProjectSheet(
      context,
      project: p,
      domains: _state.activeDomains,
      activities: _state.activities,
      targetTaskId: targetTaskId,
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _launch(_Entry e) {
    final actId = e.chronoActivityId;
    if (actId == null) return;
    widget.logic.start(actId,
        taskId: e.task?.id, actionId: e.action.id);
    if (mounted) setState(() {});
  }

  Future<void> _persistEntry(_Entry e) async {
    // Optimiste, comme _toggleDone : l'UI reflète tout de suite.
    if (e.project != null) {
      unawaited(_sync.saveProjectTasks(e.project!.id, e.project!.tasks));
    } else if (e.activity != null) {
      unawaited(_sync.updateOwnActions(e.activity!.id, e.activity!.ownActions));
    }
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  Future<void> _togglePause(Project p) async {
    p.paused = !p.paused;
    unawaited(_sync.saveProject(p));
    widget.logic.onChange();
    if (mounted) setState(() {});
    // Petite icône, aucun feedback : des projets se retrouvaient en pause
    // sans qu'on sache pourquoi (taps accidentels) → snackbar + Annuler.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(p.paused
          ? '⏸ « ${p.title} » mis en pause'
          : '▶ « ${p.title} » repris'),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          p.paused = !p.paused;
          unawaited(_sync.saveProject(p));
          widget.logic.onChange();
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  // ── « Process » GTD : tap sur une action → multi-contextes ─────────────────

  Future<void> _processAction(_Entry e) async {
    final available = await _sync.fetchAvailableContexts();
    if (!mounted) return;
    final selected = Set<String>.of(e.action.allContexts);
    // Un contexte orphelin (custom supprimé) reste sélectionnable ici.
    final all = [
      ...available,
      ...selected.where((c) => !available.contains(c)),
    ];
    // Lien chrono (actions de projet) : activité propre de l'action, sinon
    // héritée du projet. Les activités du même domaine passent en premier.
    final isProjectAction = e.project != null;
    var linkedId = e.action.linkedActivityId;
    final timeActivities = _state.activeActivities
        .where((a) => a.type == 'time')
        .toList()
      ..sort((a, b) {
        final ad = a.domainId == e.project?.domainId ? 0 : 1;
        final bd = b.domainId == e.project?.domainId ? 0 : 1;
        return ad != bd ? ad - bd : a.name.compareTo(b.name);
      });
    final inherited = e.project?.linkedActivityId == null
        ? null
        : _state.activities
            .firstWhereOrNull((a) => a.id == e.project!.linkedActivityId);
    final saved = await showModalBottomSheet<String>(
      context: context,
      // Scrollable : contextes + activités peuvent dépasser un écran — sans
      // ça le bouton Enregistrer devient inaccessible (constaté sur build).
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Où / avec quoi cette action est-elle réalisable ?',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withOpacity(.55))),
              const SizedBox(height: 14),
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
              if (isProjectAction && timeActivities.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('CHRONO SUR L\'ACTIVITÉ',
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
                    for (final a in timeActivities.take(8))
                      ChoiceChip(
                        selected: linkedId == a.id,
                        onSelected: (_) => setLocal(() =>
                            linkedId = linkedId == a.id ? null : a.id),
                        showCheckmark: false,
                        label: Text(a.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (linkedId == null && inherited != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Hérite du projet : ${inherited.name}',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withOpacity(.45))),
                  ),
              ],
              const SizedBox(height: 16),
              Row(children: [
                // Supprimer l'action (CRUD complet — confirmé après le pop).
                IconButton(
                  tooltip: 'Supprimer l\'action',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                ),
                if (e.project != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openProject(e.project!, targetTaskId: e.task?.id);
                    },
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Fiche tâche'),
                  ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _scheduleAction(e);
                  },
                  icon: const Icon(Icons.event_outlined, size: 15),
                  label: const Text('Programmer'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Enregistrer'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (saved == 'save') {
      e.action.setContexts(selected.toList());
      if (isProjectAction) e.action.linkedActivityId = linkedId;
      await _persistEntry(e);
    } else if (saved == 'delete') {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Supprimer « ${e.action.title} » ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer')),
          ],
        ),
      );
      if (ok != true) return;
      if (e.task != null) {
        e.task!.actions.remove(e.action);
      } else if (e.activity != null) {
        e.activity!.ownActions.remove(e.action);
      }
      await _persistEntry(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Action supprimée'),
            duration: Duration(seconds: 2)));
      }
    }
  }

  /// Renomme un contexte custom : meta + propagation aux actions chargées qui
  /// le portent (tâches de projets + actions propres). Retourne le nouveau nom.
  Future<String?> _renameContext(String from) async {
    final ctrl = TextEditingController(text: from);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le contexte'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex : @atelier'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Renommer')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return null;
    final to = result.startsWith('@') ? result : '@$result';
    if (to == from) return null;

    await _sync.renameCustomContext(from, to);
    for (final p in widget.logic.currentProjects) {
      var changed = false;
      for (final t in p.tasks) {
        for (final a in t.actions) {
          if (a.allContexts.contains(from)) {
            a.setContexts(
                [for (final c in a.allContexts) c == from ? to : c]);
            changed = true;
          }
        }
      }
      if (changed) await _sync.saveProjectTasks(p.id, p.tasks);
    }
    for (final act in _state.activities) {
      var changed = false;
      for (final a in act.ownActions) {
        if (a.allContexts.contains(from)) {
          a.setContexts([for (final c in a.allContexts) c == from ? to : c]);
          changed = true;
        }
      }
      if (changed) await _sync.updateOwnActions(act.id, act.ownActions);
    }
    final ni = _state.nowContexts.indexOf(from);
    if (ni >= 0) _state.nowContexts[ni] = to;
    widget.logic.onChange();
    return to;
  }

  // ── Programmer une action dans le programme du jour ────────────────────────
  // Demande user : date + heure + durée POUR LE PROGRAMME (pas le Gantt) —
  // l'action devient un bloc lié (lançable ▶, cochable).

  String _ymdOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _scheduleAction(_Entry e, {DateTime? presetDay}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    const wd = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    String dayLabel(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff == 0) return 'aujourd\'hui';
      if (diff == 1) return 'demain';
      return '${wd[d.weekday - 1]} ${d.day}';
    }

    var pickedDay = _ymdOf(presetDay ?? today);
    var time = presetDay != null && presetDay.isAfter(today)
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.now();
    var duration = e.action.estimatedMin ?? 30;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs2 = Theme.of(ctx).colorScheme;
          String hhmm() =>
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          Text sectionLabel(String t) => Text(t,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: cs2.onSurface.withOpacity(.45)));
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programmer',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(e.action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs2.onSurface.withOpacity(.55))),
                const SizedBox(height: 14),
                sectionLabel('QUEL JOUR ?'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in days)
                      ChoiceChip(
                        selected: pickedDay == _ymdOf(d),
                        onSelected: (_) =>
                            setLocal(() => pickedDay = _ymdOf(d)),
                        showCheckmark: false,
                        label: Text(dayLabel(d)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: cs2.onSurface.withOpacity(.55)),
                  const SizedBox(width: 6),
                  Text('À ${hhmm()}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (t != null) setLocal(() => time = t);
                    },
                    child: const Text('Modifier'),
                  ),
                ]),
                sectionLabel('DURÉE'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in const [15, 30, 45, 60, 90])
                      ChoiceChip(
                        selected: duration == d,
                        onSelected: (_) =>
                            setLocal(() => duration = d),
                        showCheckmark: false,
                        label: Text('$d min'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.event_available_rounded,
                        size: 16),
                    label: const Text('Programmer'),
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (saved != true) return;
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    unawaited(_sync.addScheduleBlock(
        pickedDay,
        ScheduleBlock(
          startTime: hhmm,
          durationMin: duration,
          title: e.action.title,
          category: e.project != null ? 'project' : 'personal',
          projectId: e.project?.id,
          taskId: e.task?.id,
          activityId: e.chronoActivityId,
          actionId: e.action.id,
        )));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('📅 Programmé — $pickedDay à $hhmm ($duration min)'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Bouton @ : « je suis » + CRUD des contextes ─────────────────────────────

  Future<void> _showContextManager() async {
    final available = await _sync.fetchAvailableContexts();
    if (!mounted) return;
    final customs =
        available.where((c) => !kDefaultGtdContexts.contains(c)).toList();
    final addCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs2 = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contextes',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text('JE SUIS…',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs2.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in [...kDefaultGtdContexts, ...customs])
                      FilterChip(
                        // Multi : on peut être @maison ET @ordinateur.
                        selected: _state.nowContexts.contains(c),
                        onSelected: (v) {
                          v
                              ? _state.nowContexts.add(c)
                              : _state.nowContexts.remove(c);
                          widget.logic.onChange();
                          setLocal(() {});
                          if (mounted) setState(() {});
                        },
                        label: Text(c),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('MES CONTEXTES PERSONNALISÉS',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs2.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                if (customs.isEmpty)
                  Text('Aucun — ajoute le tien ci-dessous.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs2.onSurface.withOpacity(.5)))
                else ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in customs)
                        InputChip(
                          label: Text(c),
                          visualDensity: VisualDensity.compact,
                          // Tap = renommer (propagé aux actions qui le portent)
                          onPressed: () async {
                            final to = await _renameContext(c);
                            if (to == null) return;
                            setLocal(() {
                              final i = customs.indexOf(c);
                              if (i >= 0) customs[i] = to;
                            });
                            if (mounted) setState(() {});
                          },
                          onDeleted: () async {
                            await _sync.removeCustomContext(c);
                            if (_state.nowContexts.remove(c)) {
                              widget.logic.onChange();
                            }
                            setLocal(() => customs.remove(c));
                            if (mounted) setState(() {});
                          },
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Tap pour renommer · ✕ pour supprimer',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cs2.onSurface.withOpacity(.4))),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: addCtrl,
                      decoration: const InputDecoration(
                          hintText: 'Ex : @atelier',
                          isDense: true,
                          border: OutlineInputBorder()),
                      onSubmitted: (_) {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final v = addCtrl.text.trim();
                      if (v.isEmpty) return;
                      final normalized = v.startsWith('@') ? v : '@$v';
                      await _sync.addCustomContext(normalized);
                      addCtrl.clear();
                      setLocal(() {
                        if (!customs.contains(normalized)) {
                          customs.add(normalized);
                        }
                      });
                    },
                    child: const Text('Ajouter'),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
    addCtrl.dispose();
    if (mounted) setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _spent = spentByAction(_state.sessions);
    final all = _openEntries();
    final needingNext = _projectsNeedingNext();

    // Filtres OPTIONNELS (plus de verrou par contexte : la liste n'est jamais
    // vide par défaut — retour user 2026-10).
    final contexts = {
      for (final e in all) ...e.action.allContexts,
    }.toList()
      ..sort();
    final active = _state.nowContexts.where(contexts.contains).toSet();
    final domainIds = <String>{
      for (final e in all)
        if (_domainOf(e) != null) _domainOf(e)!,
      for (final p in needingNext)
        if (p.domainId != null) p.domainId!,
    };
    final domains = _state.activeDomains.where((d) => domainIds.contains(d.id)).toList();
    final activeDomains = _domainFilter.where(domainIds.contains).toSet();
    bool inDomain(String? domainId) =>
        activeDomains.isEmpty || activeDomains.contains(domainId);
    final roots = clientRoots(_allProjects);
    if (_clientFilter != null &&
        _clientFilter != kPersoClientId &&
        !roots.any((r) => r.id == _clientFilter)) {
      // Client disparu (archivé, fusionné) : le filtre tombe tout seul.
      _clientFilter = null;
    }
    bool passesFilters(_Entry e) =>
        inDomain(_domainOf(e)) &&
        _inClient(e.project) &&
        passesContexts(e.action, active) &&
        passesTime(e.action, _time);
    bool matches(_Entry e) =>
        matchesQuery(_query, [e.action.title, e.task?.title, e.project?.title, e.activity?.name]);
    bool passes(_Entry e) => passesFilters(e) && matches(e);
    final passing = all.where(passes).toList();
    // La recherche n'est pas un « filtre » : le compte des masquées ne la
    // compte pas (son état vide a son propre message).
    final hiddenByFilters = all.where((e) => !passesFilters(e)).length;
    // Tâche pas encore commencée → « À venir » (sauf action déjà au programme
    // du jour : on l'a décidé, elle reste devant).
    final today0 = _day(DateTime.now());
    final plannedIds = _todayActionIds;
    bool upcoming(_Entry e) =>
        e.task != null && isUpcomingTask(e.task!, today0) && !plannedIds.contains(e.action.id);
    // Domaine en veille (Modes et coups) : hors de la carte du moment et des
    // sections, dans une section « EN VEILLE » repliée (sauf action déjà au programme).
    bool resting(_Entry e) => widget.logic.isDomainResting(_domainOf(e)) && !plannedIds.contains(e.action.id);
    final shown = passing.where((e) => !upcoming(e) && !resting(e)).toList();
    final restingEntries = passing.where((e) => !upcoming(e) && resting(e)).toList();
    final upcomingEntries = passing.where(upcoming).toList()
      ..sort((a, b) => _day(a.task!.startDate).compareTo(_day(b.task!.startDate)));
    final needNextShown = needingNext
        .where((p) => inDomain(p.domainId) && _inClient(p) && matchesQuery(_query, [p.title]))
        .toList();
    // « J'ai 15 min » et rien ne passe : la plus proche du créneau parmi celles
    // que seul le temps écarte.
    final nearest = _time == null
        ? null
        : nearestOutsideBucket(
            all
                .where((e) =>
                    inDomain(_domainOf(e)) &&
                    _inClient(e.project) &&
                    passesContexts(e.action, active) &&
                    matches(e) &&
                    !upcoming(e))
                .map((e) => e.action),
            _time!);
    final wider = switch (_time) {
      TimeBucket.quarter => TimeBucket.hour,
      TimeBucket.hour => TimeBucket.more,
      _ => null,
    };

    _moment = _pickMoment(shown, all);

    return SafeArea(
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          // ── En-tête + création ─────────────────────────────────────────────
          Row(children: [
            Text('Actions',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(width: 10),
            if (all.isNotEmpty)
              Text('${shown.length}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(.35))),
            // Facteur réel / estimé (médiane des actions faites chronométrées).
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Rechercher',
              icon: Icon(Icons.search,
                  color: _searchOpen || _query.isNotEmpty ? cs.primary : cs.onSurface.withOpacity(.6), size: 22),
              onPressed: _searchOpen ? _closeSearch : _openSearch,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _byProject ? 'Grouper par urgence' : 'Grouper par projet',
              icon: Icon(_byProject ? Icons.schedule_outlined : Icons.folder_outlined,
                  color: cs.onSurface.withOpacity(.6), size: 22),
              onPressed: () => _setByProject(!_byProject),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Contextes : je suis… + gestion',
              icon: Icon(Icons.alternate_email, color: cs.primary, size: 24),
              onPressed: _showContextManager,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Créer une action ou un projet',
              icon: Icon(Icons.add_circle, color: cs.primary, size: 26),
              onPressed: () => showCreateActionOrProjectSheet(
                context,
                logic: widget.logic,
                sync: _sync,
                onCreated: () {
                  if (mounted) setState(() {});
                },
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (_searchOpen) ...[_searchField(cs), const SizedBox(height: 8)],
          _captureField(cs),
          if (_pendingCaptures.isNotEmpty) ...[const SizedBox(height: 6), _triageRow(cs)],
          const SizedBox(height: 6),
          _filtersToggle(cs, active, activeDomains, hiddenByFilters),
          if (_filtersOpen) ...[
            const SizedBox(height: 4),
            _filtersBar(cs, contexts, active, domains, activeDomains, roots, hiddenByFilters),
          ],
          const SizedBox(height: 6),

          // ── @courses actif → la liste de courses du menu, cochable ────────
          if (active.contains('@courses')) _CoursesSection(sync: _sync),

          if (all.isEmpty && needNextShown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Aucune action en attente.\nCapture une idée ci-dessus ou crée une action avec +.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            )
          else if (shown.isEmpty && needNextShown.isEmpty && upcomingEntries.isEmpty && _query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Column(children: [
                  Text('Aucune action pour « $_query ».',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.45))),
                  TextButton(onPressed: _closeSearch, child: const Text('Effacer la recherche')),
                ]),
              ),
            )
          else if (shown.isEmpty && needNextShown.isEmpty && upcomingEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Center(
                child: Text('Rien à faire maintenant ici — la suite est dans « À venir ».',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.45))),
              ),
            )
          else if (shown.isEmpty && needNextShown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Column(children: [
                  Text(
                      _time == null
                          ? 'Rien ne passe les filtres ($hiddenByFilters masquée${hiddenByFilters > 1 ? 's' : ''}).'
                          : 'Rien de ${timeBucketLabel(_time!)} ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(.45))),
                  if (nearest != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                          '${_time == TimeBucket.more ? 'La plus longue' : 'La plus courte'} fait '
                          '${fmtMin(nearest.min)} : « ${nearest.action.title} ».',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.6))),
                    ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (wider != null && nearest != null && passesTime(nearest.action, wider))
                      TextButton(
                        onPressed: () => _setTime(wider),
                        child: Text('J\'ai ${timeBucketLabel(wider)}'),
                      ),
                    TextButton(
                      onPressed: () {
                        _state.nowContexts.clear();
                        widget.logic.onChange();
                        _setTime(null);
                      },
                      child: const Text('Tout afficher'),
                    ),
                  ]),
                ]),
              ),
            )
          else if (_byProject)
            ..._byProjectSections(cs, shown, needNextShown)
          else
            ..._byUrgencySections(cs, shown, all, needNextShown),

          ..._upcomingSection(cs, upcomingEntries, today0),
          ..._restingSection(cs, restingEntries),
          ..._pausedSection(cs),
          ..._doneSection(cs),
        ],
      ),
    );
  }

  // ── Recherche ──────────────────────────────────────────────────────────────

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() => _searchOpen = false);
  }

  Widget _searchField(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.35)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(Icons.search, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Rechercher une action, une tâche, un projet…',
              hintStyle: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(.4)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        IconButton(
          tooltip: 'Fermer la recherche',
          icon: Icon(Icons.close, size: 18, color: cs.onSurface.withOpacity(.6)),
          visualDensity: VisualDensity.compact,
          onPressed: _closeSearch,
        ),
      ]),
    );
  }

  // ── Captures à trier → actions ─────────────────────────────────────────────

  /// « 3 captures à trier → » : ouvre le tri une par une (projet › tâche ou
  /// activité), ferme la boucle GTD dans l'onglet.
  Widget _triageRow(ColorScheme cs) {
    final n = _pendingCaptures.length;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showCaptureTriageSheet(context,
          logic: widget.logic, sync: _sync, items: _pendingCaptures, onChanged: () {
        if (mounted) setState(() {});
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(children: [
          Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$n capture${n > 1 ? 's' : ''} à trier en action${n > 1 ? 's' : ''}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.75))),
          ),
          Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withOpacity(.45)),
        ]),
      ),
    );
  }

  // ── Capture rapide → boîte d'entrée ────────────────────────────────────────

  Widget _captureField(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(Icons.inbox_outlined, size: 18, color: cs.onSurface.withOpacity(.45)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _captureCtrl,
            focusNode: _captureFocus,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Capturer une idée, un truc à faire…',
              hintStyle: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(.4)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onSubmitted: (_) => _capture(),
          ),
        ),
        IconButton(
          tooltip: 'Dans la boîte d\'entrée',
          icon: Icon(Icons.send_rounded, size: 18, color: cs.primary),
          visualDensity: VisualDensity.compact,
          onPressed: _capture,
        ),
      ]),
    );
  }

  Future<void> _capture() async {
    final text = _captureCtrl.text.trim();
    if (text.isEmpty) return;
    _captureCtrl.clear();
    unawaited(_sync.saveCaptureItem(CaptureItem(text: text, createdAt: DateTime.now())));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text('Dans la boîte d\'entrée : $text'),
    ));
  }

  // ── Filtres : J'ai… · Je suis… · Domaine ───────────────────────────────────

  Widget _filtersBar(ColorScheme cs, List<String> contexts, Set<String> active,
      List<Domain> domains, Set<String> activeDomains, List<Project> roots, int hidden) {
    Widget chip(String label, bool on, VoidCallback onTap, {Color? color}) => ChoiceChip(
          selected: on,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? (color ?? cs.primary) : cs.onSurface.withOpacity(.65),
          ),
          selectedColor: (color ?? cs.primary).withOpacity(.14),
          backgroundColor: cs.surfaceContainerHighest.withOpacity(.35),
          side: BorderSide(color: on ? (color ?? cs.primary).withOpacity(.5) : Colors.transparent),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: cs.onSurface.withOpacity(.45))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          label("J'AI"),
          for (final (b, t) in [
            (TimeBucket.quarter, '15 min'),
            (TimeBucket.hour, '1 h'),
            (TimeBucket.more, 'Plus'),
          ]) ...[
            chip(t, _time == b, () => _setTime(_time == b ? null : b)),
            const SizedBox(width: 6),
          ],
          // Facteur réel / estimé (médiane des actions faites chronométrées),
          // à côté des créneaux qu'il sert à corriger ; la ligne défile, donc
          // le libellé complet tient toujours (l'en-tête, lui, débordait).
          if (estimateFactorLabel(estimateFactor(widget.logic.currentProjects, _spent))
              case final fl?) ...[
            const SizedBox(width: 2),
            Tooltip(
              message: 'Médiane du temps réel sur le temps estimé, actions faites avec chrono ciblé. '
                  'Sert à corriger vos estimations.',
              child: Text(fl,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.45))),
            ),
            const SizedBox(width: 6),
          ],
          if (contexts.isNotEmpty) ...[
            const SizedBox(width: 10),
            label('JE SUIS'),
            for (final c in contexts) ...[
              chip(c, active.contains(c), () {
                active.contains(c)
                    ? _state.nowContexts.remove(c)
                    : _state.nowContexts.add(c);
                widget.logic.onChange();
                setState(() {});
              }),
              const SizedBox(width: 6),
            ],
          ],
        ]),
      ),
      if (domains.length > 1) ...[
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            label('DOMAINE'),
            for (final d in domains) ...[
              chip(d.name, activeDomains.contains(d.id), () => _toggleDomain(d.id),
                  color: domainColor(d.id, _state.activeDomains)),
              const SizedBox(width: 6),
            ],
          ]),
        ),
      ],
      if (roots.length > 1) ...[
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            label('POUR'),
            for (final r in roots) ...[
              chip(r.title, _clientFilter == r.id,
                  () => _setClient(_clientFilter == r.id ? null : r.id),
                  color: domainColor(r.domainId, _state.activeDomains)),
              const SizedBox(width: 6),
            ],
            chip(kPersoClientLabel, _clientFilter == kPersoClientId,
                () => _setClient(_clientFilter == kPersoClientId ? null : kPersoClientId)),
          ]),
        ),
      ],
      if (hidden > 0 &&
          (active.isNotEmpty || _time != null || activeDomains.isNotEmpty || _clientFilter != null))
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$hidden action${hidden > 1 ? 's' : ''} masquée${hidden > 1 ? 's' : ''} par les filtres.',
            style: TextStyle(
                fontSize: 11.5, fontStyle: FontStyle.italic, color: cs.onSurface.withOpacity(.5)),
          ),
        ),
    ]);
  }

  /// « À venir · n » : actions des tâches qui n'ont pas encore commencé,
  /// repliées, par date de début. Toujours cochables et lançables (prendre de
  /// l'avance reste possible).
  List<Widget> _upcomingSection(ColorScheme cs, List<_Entry> upcoming, DateTime today) {
    if (upcoming.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      InkWell(
        onTap: () => setState(() => _showUpcoming = !_showUpcoming),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.upcoming_outlined, size: 16, color: cs.tertiary),
            const SizedBox(width: 6),
            Text('À VENIR · ${upcoming.length}',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.tertiary)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('pas encore commencées',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.4))),
            ),
            Icon(_showUpcoming ? Icons.expand_less : Icons.expand_more,
                size: 18, color: cs.onSurface.withOpacity(.45)),
          ]),
        ),
      ),
      if (_showUpcoming)
        for (final e in upcoming)
          _entryTile(cs, e, showHolder: true, startLabel: upcomingLabel(e.task!.startDate, today)),
    ];
  }

  /// Domaines en veille (Modes et coups) : les actions restent là, repliées.
  List<Widget> _restingSection(ColorScheme cs, List<_Entry> resting) {
    if (resting.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      InkWell(
        onTap: () => setState(() => _showResting = !_showResting),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.bedtime_outlined, size: 16, color: cs.onSurface.withOpacity(.5)),
            const SizedBox(width: 6),
            Text('EN VEILLE · ${resting.length}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withOpacity(.5))),
            const SizedBox(width: 6),
            Expanded(
              child: Text('domaines mis en veille', style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.4))),
            ),
            Icon(_showResting ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.onSurface.withOpacity(.45)),
          ]),
        ),
      ),
      if (_showResting)
        for (final e in resting) _entryTile(cs, e, showHolder: true),
    ];
  }

  // ── Sections par urgence ────────────────────────────────────────────────────

  List<Widget> _byUrgencySections(
      ColorScheme cs, List<_Entry> shown, List<_Entry> all, List<Project> needNext) {
    final today = _day(DateTime.now());
    final weekEnd = today.add(const Duration(days: 7));
    final nowMin = widget.logic.livedNowMinNow;
    final todayIds = _todayActionIds;
    final used = <String>{};
    final out = <Widget>[];

    // Maintenant : chrono en cours → ses actions ; sinon le bloc en cours ou
    // le prochain bloc du programme.
    final running = _running;
    final nowEntries = <_Entry>[];
    String nowLabel = 'MAINTENANT';
    if (running != null) {
      final ids = {
        for (final x in possibleNow(
            widget.logic.currentProjects, _state.activeActivities, running.activityId,
            filter: (_) => true))
          x.action.id
      };
      nowEntries.addAll(shown.where((e) => ids.contains(e.action.id)));
      final act = _state.activities.firstWhereOrNull((a) => a.id == running.activityId);
      nowLabel = 'POSSIBLE MAINTENANT${act != null ? ' · ${act.name.toUpperCase()}' : ''}';
    } else {
      final fb = focusBlock(_todayBlocks, nowMin);
      if (fb != null) {
        final e = _entryForBlock(fb.block, shown);
        if (e != null) {
          nowEntries.add(e);
          nowLabel = fb.current
              ? 'BLOC EN COURS · ${fb.block.startTime}'
              : 'PROCHAIN BLOC · ${fb.block.startTime}';
        }
      }
    }
    if (nowEntries.isNotEmpty) {
      out.add(_sectionLabel(cs, nowLabel, Icons.bolt_outlined, color: cs.primary));
      for (final e in _byEst(nowEntries)) {
        used.add(e.action.id);
        out.add(_entryTile(cs, e, showHolder: true, planned: todayIds.contains(e.action.id)));
      }
      out.add(const SizedBox(height: 8));
    }

    List<_Entry> take(bool Function(_Entry) test) {
      final list = shown.where((e) => !used.contains(e.action.id) && test(e)).toList();
      for (final e in list) {
        used.add(e.action.id);
      }
      return list;
    }

    final todayList = take((e) => todayIds.contains(e.action.id));
    // Arrivées aujourd'hui : actions dont la tâche démarre ce jour (devenues
    // faisables depuis hier, « À venir » hier encore).
    final arrived = take((e) => e.task != null && startsToday(e.task!, today));
    if (todayList.isNotEmpty) {
      out.add(_sectionLabel(cs, "AUJOURD'HUI · AU PROGRAMME", Icons.today_outlined));
      for (final e in _byEst(todayList)) {
        out.add(_entryTile(cs, e, showHolder: true, planned: true));
      }
      out.add(const SizedBox(height: 8));
    }

    if (arrived.isNotEmpty) {
      out.add(_sectionLabel(cs, "ARRIVÉES AUJOURD'HUI", Icons.fiber_new_outlined, color: _newColor));
      for (final e in _byEst(arrived)) {
        out.add(_entryTile(cs, e, showHolder: true));
      }
      out.add(const SizedBox(height: 8));
    }

    final late = take((e) => _dueOf(e) != null && _dueOf(e)!.isBefore(today))
      ..sort((a, b) => _dueOf(a)!.compareTo(_dueOf(b)!));
    if (late.isNotEmpty) {
      out.add(_sectionLabel(cs, 'EN RETARD', Icons.warning_amber_rounded, color: cs.error));
      for (final e in _byEst(late)) {
        out.add(_entryTile(cs, e, showHolder: true));
      }
      out.add(const SizedBox(height: 8));
    }

    final week = take((e) => _dueOf(e) != null && !_dueOf(e)!.isAfter(weekEnd))
      ..sort((a, b) => _dueOf(a)!.compareTo(_dueOf(b)!));
    if (week.isNotEmpty) {
      out.add(_sectionLabel(cs, 'CETTE SEMAINE', Icons.date_range_outlined));
      for (final e in _byEst(week)) {
        out.add(_entryTile(cs, e, showHolder: true));
      }
      out.add(const SizedBox(height: 8));
    }

    // Le reste, par projet (ordre d'échéance des projets), puis actions simples.
    final rest = shown.where((e) => !used.contains(e.action.id)).toList();
    final restProjects = <String, List<_Entry>>{};
    final restOwn = <String, List<_Entry>>{};
    for (final e in rest) {
      if (e.project != null) {
        restProjects.putIfAbsent(e.project!.id, () => []).add(e);
      } else if (e.activity != null) {
        restOwn.putIfAbsent(e.activity!.id, () => []).add(e);
      }
    }
    if (restProjects.isNotEmpty || needNext.isNotEmpty) {
      out.add(_sectionLabel(cs, 'PLUS TARD · PAR PROJET', Icons.folder_outlined));
      for (final g in _projectGroups()) {
        final entries = restProjects[g.project.id];
        final needs = needNext.any((p) => p.id == g.project.id);
        if ((entries == null || entries.isEmpty) && !needs) continue;
        out.add(_projectHeader(cs, g.project));
        for (final e in _byEst(entries ?? const <_Entry>[])) {
          out.add(_entryTile(cs, e, planned: todayIds.contains(e.action.id)));
        }
        if (needs) out.add(_defineTile(cs, g.project));
        out.add(const SizedBox(height: 6));
      }
    }
    if (restOwn.isNotEmpty) {
      out.add(_sectionLabel(cs, 'ACTIONS SIMPLES', Icons.flash_on_outlined, color: cs.tertiary));
      for (final act in _state.activeActivities) {
        final entries = restOwn[act.id];
        if (entries == null) continue;
        out.add(_activityLabel(cs, act));
        for (final e in _byEst(entries)) {
          out.add(_entryTile(cs, e, planned: todayIds.contains(e.action.id)));
        }
      }
    }
    return out;
  }

  // ── Sections par projet (ancien mode, sans verrou) ──────────────────────────

  /// Groupes par projet ; avec le filtre « J'ai … », les projets dont la
  /// séance est la plus proche passent en tête (brief 2.4).
  List<ProjectActions> _projectGroups() {
    final today = DateTime.now();
    return projectActionGroups(
      widget.logic.currentProjects,
      filter: (_) => true,
      sort: _time != null ? ActionsSort.milestone : ActionsSort.dueDate,
      urgencyOf: (p) => nextInterventionOf(p, today)?.date,
    );
  }

  /// « J'ai … » actif : chaque section se lit de la plus courte à la plus
  /// longue (les non estimées en fin) ; sinon l'ordre de la section.
  List<_Entry> _byEst(List<_Entry> l) =>
      _time == null ? l : sortedByEstimate(l, (e) => e.action.estimatedMin);

  List<Widget> _byProjectSections(ColorScheme cs, List<_Entry> shown, List<Project> needNext) {
    final todayIds = _todayActionIds;
    final out = <Widget>[];
    for (final g in _projectGroups()) {
      final entries = _byEst(shown.where((e) => e.project?.id == g.project.id).toList());
      final needs = needNext.any((p) => p.id == g.project.id);
      if (entries.isEmpty && !needs) continue;
      out.add(_projectHeader(cs, g.project));
      for (final e in entries) {
        out.add(_entryTile(cs, e, planned: todayIds.contains(e.action.id)));
      }
      if (needs) out.add(_defineTile(cs, g.project));
      out.add(const SizedBox(height: 10));
    }
    final own = shown.where((e) => e.project == null && e.activity != null).toList();
    if (own.isNotEmpty) {
      out.add(_sectionLabel(cs, 'ACTIONS SIMPLES', Icons.flash_on_outlined, color: cs.tertiary));
      for (final act in _state.activeActivities) {
        final entries = _byEst(own.where((e) => e.activity!.id == act.id).toList());
        if (entries.isEmpty) continue;
        out.add(_activityLabel(cs, act));
        for (final e in entries) {
          out.add(_entryTile(cs, e, planned: todayIds.contains(e.action.id)));
        }
      }
    }
    return out;
  }

  Widget _projectHeader(ColorScheme cs, Project p) => _groupHeader(
        cs,
        _rootIdOf(p) != p.id && _clientFilter == null
            ? '${rootProjectOf(p, _allProjects).title} › ${p.title}'
            : p.title,
        domainColor(p.domainId, _state.activeDomains) ?? cs.primary,
        onTap: () => _openProject(p),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Ajouter une action',
            icon: Icon(Icons.add, size: 18, color: cs.primary.withOpacity(.75)),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            onPressed: () => _quickAddAction(p),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Mettre en pause',
            icon: Icon(Icons.pause_circle_outline, size: 18, color: cs.onSurface.withOpacity(.4)),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            onPressed: () => _togglePause(p),
          ),
        ]),
      );

  Widget _activityLabel(ColorScheme cs, Activity act) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 2, bottom: 4),
        child: Text(act.name.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: cs.onSurface.withOpacity(.4))),
      );

  Widget _sectionLabel(ColorScheme cs, String text, IconData icon, {Color? color}) {
    final c = color ?? cs.onSurface.withOpacity(.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: c)),
        ),
      ]),
    );
  }

  // ── En pause / Terminées (accordéons) ───────────────────────────────────────

  List<Widget> _pausedSection(ColorScheme cs) {
    final paused = widget.logic.currentProjects
        .where((p) => p.status == 'active' && p.paused)
        .toList();
    if (paused.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 10),
      _accordionHeader(cs, Icons.pause_circle_outline, 'EN PAUSE (${paused.length})', _showPaused,
          () => setState(() => _showPaused = !_showPaused)),
      if (_showPaused)
        for (final p in paused)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(Icons.pause, size: 14, color: cs.onSurface.withOpacity(.35)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5))),
              ),
              IconButton(
                tooltip: 'Reprendre',
                icon: Icon(Icons.play_circle_outline, size: 20, color: cs.primary),
                visualDensity: VisualDensity.compact,
                onPressed: () => _togglePause(p),
              ),
            ]),
          ),
    ];
  }

  static const _kDoneShown = 50;

  List<Widget> _doneSection(ColorScheme cs) {
    final doneEntries = _doneEntries();
    if (doneEntries.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 10),
      _accordionHeader(cs, Icons.check_circle_outline, 'TERMINÉES (${doneEntries.length})',
          _showDone, () => setState(() => _showDone = !_showDone)),
      if (_showDone) ...[
        for (final e in doneEntries.take(_kDoneShown)) _doneTile(cs, e),
        if (doneEntries.length > _kDoneShown)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4),
            child: Text(
              '… et ${doneEntries.length - _kDoneShown} autre${doneEntries.length - _kDoneShown > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.4)),
            ),
          ),
      ],
    ];
  }

  Widget _accordionHeader(
          ColorScheme cs, IconData icon, String title, bool open, VoidCallback onTap) =>
      ListSectionTitle(title, onAction: onTap, expanded: open);

  Widget _groupHeader(ColorScheme cs, String title, Color color,
      {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withOpacity(.75))),
          ),
          if (trailing != null) trailing,
          if (onTap != null)
            Icon(Icons.chevron_right, size: 16, color: cs.onSurface.withOpacity(.3)),
        ]),
      ),
    );
  }

  /// Projet sans action en attente : invitation GTD à définir la suivante.
  Widget _defineTile(ColorScheme cs, Project p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _quickAddAction(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.edit_note, size: 18, color: cs.primary.withOpacity(.8)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Définir la prochaine action',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Tuile d'action : glisser → fait / caser demain, tap → feuille ──────────

  String _dueLabel(DateTime due, DateTime today) => actionDueLabel(due, today);

  /// Échéance PROPRE de l'action (2026-10) : demain · fin de semaine · une date
  /// · retirer (la date de la tâche fait foi à nouveau). Persistée comme le
  /// reste de la feuille (`_persistEntry`).
  Future<void> _pickDueDate(_Entry e) async {
    final a = e.action;
    final today = _day(DateTime.now());
    final taskDue = e.task?.endDate == null ? null : _day(e.task!.endDate!);
    final toSunday = 7 - today.weekday;
    final endOfWeek = today.add(Duration(days: toSunday == 0 ? 7 : toSunday));
    const clear = '__clear__';
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Échéance de l\'action', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                    taskDue == null
                        ? 'Sans échéance propre, l\'action n\'a pas de date.'
                        : 'Sans échéance propre, c\'est celle de la tâche : ${shortDateFr(taskDue)}.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Demain'),
              subtitle: Text(shortDateFr(today.add(const Duration(days: 1)))),
              onTap: () => Navigator.pop(ctx, today.add(const Duration(days: 1))),
            ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('Fin de semaine'),
              subtitle: Text('dimanche ${shortDateFr(endOfWeek)}'),
              onTap: () => Navigator.pop(ctx, endOfWeek),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Choisir une date…'),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: a.dueDate ?? taskDue ?? today,
                  firstDate: today.subtract(const Duration(days: 365)),
                  lastDate: today.add(const Duration(days: 365 * 3)),
                  locale: const Locale('fr'),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, d);
              },
            ),
            if (a.dueDate != null)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: cs.error),
                title: Text('Retirer l\'échéance propre', style: TextStyle(color: cs.error)),
                subtitle: Text(taskDue == null ? 'plus de date' : 'retour à celle de la tâche : ${shortDateFr(taskDue)}'),
                onTap: () => Navigator.pop(ctx, clear),
              ),
          ]),
        );
      },
    );
    if (picked == null) return;
    a.dueDate = picked == clear ? null : _day(picked as DateTime);
    await _persistEntry(e);
    if (mounted) setState(() {});
  }

  Widget _entryTile(ColorScheme cs, _Entry e,
      {bool showHolder = false, bool planned = false, String? startLabel}) {
    final isNew = e.task != null && startsToday(e.task!, today0OrNow());
    final today = _day(DateTime.now());
    final due = _dueOf(e);
    final late = due != null && due.isBefore(today);
    final a = e.action;
    final running = _running?.actionId == a.id;
    // « Projet › Tâche » puis le détail chiffré, sur une seule sous-ligne.
    final taskTitle = e.task != null && e.task!.id != _flowTaskId ? e.task!.title : null;
    final holderText = showHolder && e.holder.isNotEmpty ? e.holder : null;
    final spent = spentLabel(_spent[a.id] ?? 0, a.estimatedMin, fmtMin);
    final sub = <String>[
      if (holderText != null && taskTitle != null) '$holderText › $taskTitle' else if (holderText != null) holderText else if (taskTitle != null) taskTitle,
      if (startLabel != null) startLabel,
      if (due != null) (a.dueDate != null ? '⚑ ' : '') + _dueLabel(due, today),
      if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
      if (spent != null) spent.label,
      if (a.allContexts.isNotEmpty) (a.allContexts.toList()..sort()).join(' '),
    ].join(' · ');
    // Couleur d'état : en retard corail, échéance proche ambre, sinon vert.
    final daysTo = due == null ? null : due.difference(today).inDays;
    final pct = late ? 40 : (daysTo != null && daysTo <= 2 ? 70 : 100);
    final String? chip = running
        ? 'en cours'
        : isNew
            ? 'nouveau'
            : planned
                ? 'au programme'
                : late
                    ? _dueLabel(due, today)
                    : null;
    final chipColor = running ? cs.primary : (isNew ? _newColor : palierColor(pct));
    final steps = a.checklist.isNotEmpty ? (done: a.checklistDone, total: a.checklistTotal, expected: a.checklistDone) : null;

    return Dismissible(
      key: ValueKey('act_${a.id}'),
      // Droite = fait, gauche = caser demain. Les deux gestes agissent et
      // laissent la tuile en place : la liste se recompose d'elle-même.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18),
        decoration: BoxDecoration(
            color: Colors.green.withOpacity(.18), borderRadius: BorderRadius.circular(14)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Fait', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
        ]),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
            color: cs.primary.withOpacity(.14), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Caser demain', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
          const SizedBox(width: 8),
          Icon(Icons.event_outlined, color: cs.primary),
        ]),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _toggleDone(e, true);
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                duration: const Duration(seconds: 4),
                content: Text('Fait : ${a.title}'),
                action: SnackBarAction(label: 'Annuler', onPressed: () => _toggleDone(e, false)),
              ));
          }
        } else {
          await _scheduleAction(e, presetDay: today.add(const Duration(days: 1)));
        }
        return false;
      },
      // « Une liste, un seul bloc ouvert » : la ligne (repliée) et la carte
      // du moment (ouverte) sont le même item ; tap = ouvrir à sa place.
      child: MomentItem(
        key: _open.keyFor(a.id),
        open: _open.isOpen(a.id, _moment?.entry.action.id),
        collapsed: StatusRow(
          leading: InkWell(
            onTap: () => _toggleDone(e, true),
            borderRadius: BorderRadius.circular(8),
            child: const Icon(Icons.radio_button_unchecked),
          ),
          title: a.title,
          sub: sub.isEmpty ? null : sub,
          bar: steps,
          pct: pct,
          trailing: chip == null ? null : StateChip(chip, color: chipColor),
        ),
        expanded: _momentCardFor(cs, e, _moment?.entry.action.id == a.id ? _moment : null, planned: planned),
        onToggle: () => _open.settle(a.id, () => setState(() => _open.toggle(a.id, _moment?.entry.action.id)), scroll: _scroll),
        onLongPress: () => _openActionSheet(e),
      ),
    );
  }

  // ── Carte ACTION DU MOMENT (« une carte, une fiche », lot 2) ────────────────

  /// L'action que le moment désigne (`pickActionMoment`) : chrono en cours,
  /// bloc en cours, retard, programme du jour, prochain bloc, semaine, sinon
  /// la première. Anneau = étapes faites, geste = étape suivante / chrono / fait.
  ActionMoment? _pickMoment(List<_Entry> shown, List<_Entry> all) {
    final pool = shown.isNotEmpty ? shown : all;
    if (pool.isEmpty) return null;
    final today = _day(DateTime.now());
    final entries = <ActionEntry>[for (final e in pool) (action: e.action, project: e.project, task: e.task, activity: e.activity)];
    final mode = widget.logic.mode;
    String? focusProjectId;
    if (mode == DayMode.high) {
      for (final pm in rankProjectMoments(widget.logic.currentProjects, widget.logic.state.sessions, DateTime.now())) {
        if (pm.upcoming) continue;
        focusProjectId = pm.project.id;
        break;
      }
    }
    final m = pickActionMoment(
      entries,
      blocks: _todayBlocks,
      nowMin: widget.logic.livedNowMinNow,
      today: today,
      runningActionId: _running?.actionId,
      mode: mode,
      focusProjectId: focusProjectId,
      entryForBlock: (b) {
        final e = _entryForBlock(b, pool);
        return e == null ? null : (action: e.action, project: e.project, task: e.task, activity: e.activity);
      },
    );
    return m;
  }

  /// Bloc ouvert d'une action (= l'ancienne carte ACTION DU MOMENT) ; [m]
  /// non null quand c'est l'action que le moment désigne.
  Widget _momentCardFor(ColorScheme cs, _Entry e, ActionMoment? m, {bool planned = false}) {
    final today = _day(DateTime.now());
    final a = e.action;
    final due = _dueOf(e);
    final late = due != null && due.isBefore(today);
    final spentMin = _spent[a.id] ?? 0;
    final steps = a.checklist.isNotEmpty;
    final next = nextChecklistItem(a);
    final isRunningEntry = _running?.actionId == a.id;
    final pill = m == null
        ? (isRunningEntry
            ? 'chrono en cours'
            : late
                ? 'en retard · ${_dueLabel(due, today)}'
                : planned
                    ? 'au programme'
                    : due != null
                        ? 'éch. ${_dueLabel(due, today)}'
                        : 'à faire')
        : switch (m.kind) {
            ActionMomentKind.running => 'chrono en cours',
            ActionMomentKind.block => 'bloc en cours · ${m.block!.startTime}',
            ActionMomentKind.late => 'en retard · ${_dueLabel(due!, today)}',
            ActionMomentKind.today => 'au programme · ${m.block!.startTime}',
            ActionMomentKind.next => 'prochain bloc · ${m.block!.startTime}',
            ActionMomentKind.week => 'cette semaine',
            ActionMomentKind.rest => 'prochaine action',
            ActionMomentKind.short => 'la plus courte · malgré tout',
            ActionMomentKind.deep => 'à fond · la plus longue',
          };
    final accent = late ? kPalierCoral : cs.primary;
    final ctx = [
      if (e.holder.isNotEmpty) e.holder,
      if (e.task != null && e.task!.id != _flowTaskId) e.task!.title,
    ].join(' › ');
    // Grammaire de Projets (2026-10) : la sous-ligne ne garde que QUAND et
    // COMBIEN ; étapes en points, temps passé et contextes dans la légende.
    final sub = <String>[
      if (due != null) (a.dueDate != null ? '⚑ ' : 'éch. ') + _dueLabel(due, today),
      if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
    ].join(' · ');
    final legendRight = <String>[
      if (spentMin > 0) '⏱ ${fmtMin(spentMin)}',
      if (a.allContexts.isNotEmpty) (a.allContexts.toList()..sort()).join(' '),
    ].join(' · ');
    final double? ring;
    final String big, small;
    if (steps) {
      ring = a.checklistTotal == 0 ? 0 : a.checklistDone / a.checklistTotal;
      big = '${a.checklistDone} / ${a.checklistTotal}';
      small = 'ÉTAPES';
    } else if (a.estimatedMin != null && a.estimatedMin! > 0) {
      ring = spentMin / a.estimatedMin!;
      big = fmtMin(spentMin);
      small = 'SUR ≈ ${fmtMin(a.estimatedMin!)}';
    } else {
      ring = 0;
      big = fmtMin(spentMin);
      small = 'PASSÉES';
    }
    final running = isRunningEntry;
    final String primary;
    final IconData icon;
    final VoidCallback onPrimary;
    if (running) {
      primary = 'Arrêter le chrono';
      icon = Icons.stop_rounded;
      onPrimary = () => widget.logic.stopActive();
    } else if (next != null) {
      primary = 'Étape faite';
      icon = Icons.check_rounded;
      onPrimary = () async {
        final changed = setChecklistItem(a, next.id, true);
        await _persistEntry(e);
        if (changed && a.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text('Action faite : ${a.title}')));
        }
      };
    } else if (e.chronoActivityId != null) {
      primary = 'Chrono';
      icon = Icons.play_arrow_rounded;
      onPrimary = () => _launch(e);
    } else {
      primary = 'Fait';
      icon = Icons.check_rounded;
      onPrimary = () => _toggleDone(e, true);
    }
    return MomentCard(
      accent: accent,
      eyebrow: m != null ? 'ACTION DU MOMENT' : (late ? 'ACTION EN RETARD' : 'ACTION'),
      pill: pill,
      ring: ring,
      ringColor: late ? kPalierCoral : palierColor(steps ? 100 : (ring > 1 ? 40 : 100)),
      ringBig: big,
      ringSmall: small,
      context_: ctx.isEmpty ? null : ctx,
      contextIcon: e.project != null ? Icons.account_tree_outlined : Icons.bolt_outlined,
      title: a.title,
      sub: sub.isEmpty ? 'Sans échéance ni estimation' : sub,
      subColor: late ? kPalierCoral : null,
      visual: steps
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StepDots(done: a.checklistDone, total: a.checklistTotal, allDone: a.done, size: 12),
              MomentLegend(next == null ? 'Toutes les étapes sont faites' : 'Étape en cours : ${next.title}',
                  right: legendRight.isEmpty ? null : legendRight),
            ])
          : legendRight.isEmpty
              ? null
              : MomentLegend(legendRight),
      primaryLabel: primary,
      primaryIcon: icon,
      primaryOutlined: running,
      onPrimary: onPrimary,
      ficheLabel: 'Détail',
      onFiche: () => _openActionSheet(e),
      chainLabel: e.project != null ? 'Projet' : null,
      chainIcon: null,
      onChain: e.project == null ? null : () => _openProject(e.project!, targetTaskId: e.task?.id),
      moreActions: [
        if (!running && e.chronoActivityId != null && next != null)
          MomentAction('Chrono', icon: Icons.play_arrow_rounded, onTap: () => _launch(e)),
        if (!a.done && (next != null || e.chronoActivityId != null))
          MomentAction('Fait', icon: Icons.check_circle_outline, hint: 'sans passer par les étapes', onTap: () => _toggleDone(e, true)),
        MomentAction('Caser dans le programme', icon: Icons.event_rounded, onTap: () => _scheduleAction(e)),
      ],
    );
  }

  /// Ligne « Filtres » repliable : J'ai · Je suis · Domaine · Pour. Ouverte
  /// d'office quand un filtre est actif (on voit ce qui masque).
  Widget _filtersToggle(ColorScheme cs, Set<String> active, Set<String> activeDomains, int hidden) {
    final n = (_time == null ? 0 : 1) + active.length + activeDomains.length + (_clientFilter == null ? 0 : 1);
    if (n > 0 && !_filtersAutoOpened) {
      _filtersAutoOpened = true;
      _filtersOpen = true;
    }
    return InkWell(
      onTap: () => setState(() => _filtersOpen = !_filtersOpen),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(children: [
          Icon(Icons.tune_rounded, size: 14, color: n > 0 ? cs.primary : cs.onSurface.withOpacity(.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              n > 0
                  ? 'FILTRES · $n actif${n > 1 ? 's' : ''}${hidden > 0 ? ' · $hidden masquée${hidden > 1 ? 's' : ''}' : ''}'
                  : 'FILTRES · J\'AI · JE SUIS · DOMAINE · POUR',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: n > 0 ? cs.primary : cs.onSurface.withOpacity(.5)),
            ),
          ),
          Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.onSurface.withOpacity(.45)),
        ]),
      ),
    );
  }

  // ── Fiche d'action (« une carte, une fiche », lot 2) ────────────────────────

  /// En-tête + chip d'état, ÉTAPES, DÉTAIL (note), ÉCHÉANCE, gestes (chrono,
  /// caser, fait, contextes, projet, rattacher). Même ossature que la fiche
  /// objectif et la fiche projet (`widgets/fiche.dart`).
  Future<void> _openActionSheet(_Entry e) async {
    final a = e.action;
    await showFiche<void>(
      context,
      builder: (ctx, scroll) => StatefulBuilder(builder: (ctx, setLocal) {
        final cs = Theme.of(ctx).colorScheme;
        void refresh() {
          setLocal(() {});
          if (mounted) setState(() {});
        }
        Future<void> persist() => _persistEntry(e);
        final today = _day(DateTime.now());
        final due = _dueOf(e);
        final late = due != null && due.isBefore(today);
        final planned = _todayActionIds.contains(a.id);
        final running = _running?.actionId == a.id;
        final spent = spentLabel(_spent[a.id] ?? 0, a.estimatedMin, fmtMin);
        final holderLine = [
          if (e.project != null) e.project!.title,
          if (e.activity != null) e.activity!.name,
        ].join(' · ');
        final taskLine = e.task != null && e.task!.id != _flowTaskId ? e.task!.title : null;
        final kpi = <String>[
          if (holderLine.isNotEmpty && taskLine != null) '$holderLine › $taskLine' else if (holderLine.isNotEmpty) holderLine else if (taskLine != null) taskLine,
          if (a.allContexts.isNotEmpty) (a.allContexts.toList()..sort()).join(' '),
          if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
          if (spent != null) spent.label,
        ].join(' · ');
        final (chip, chipColor) = a.done
            ? ('faite', kPalierGreen)
            : running
                ? ('chrono en cours', cs.primary)
                : late
                    ? ('en retard', kPalierCoral)
                    : planned
                        ? ('au programme', cs.primary)
                        : due != null
                            ? (_dueLabel(due, today), palierColor(due.difference(today).inDays <= 2 ? 70 : 100))
                            : ('à faire', kPalierMuted);
        return ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          children: [
            FicheHeader(
              title: a.title,
              chip: chip,
              chipColor: chipColor,
              kpi: kpi.isEmpty ? null : kpi,
              leading: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _toggleDone(e, !a.done);
                },
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 26, color: a.done ? Colors.green : cs.onSurface.withOpacity(.4)),
                ),
              ),
            ),
            FicheTitle('ÉTAPES',
                trailing: a.checklist.isEmpty ? null : FicheDelta('${a.checklistDone} / ${a.checklistTotal}', color: kPalierGreen)),
            StepsSection(
              key: ValueKey('sheet_steps_${a.id}'),
              action: a,
              leftInset: 0,
              onToggle: (c, v) {
                final changed = setChecklistItem(a, c.id, v);
                refresh();
                persist();
                if (changed && a.done) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      duration: const Duration(seconds: 2),
                      content: Text('Action faite : ${a.title}')));
                }
              },
              onAdd: (t) {
                if (addChecklistItem(a, t) == null) return;
                refresh();
                persist();
              },
              onRemove: (c) {
                removeChecklistItem(a, c.id);
                refresh();
                persist();
              },
              onRename: (c, t) {
                if (!renameChecklistItem(a, c.id, t)) return;
                refresh();
                persist();
              },
            ),
            if (a.note != null) ...[
              const FicheTitle('DÉTAIL'),
              FicheNote(a.note!),
            ],
            FicheTitle('ÉCHÉANCE',
                trailing: due == null ? null : FicheDelta((a.dueDate != null ? '⚑ ' : '') + _dueLabel(due, today), color: late ? kPalierCoral : kPalierGreen)),
            FicheNote(due == null
                ? 'Sans échéance : celle de la tâche fait foi quand elle en a une.'
                : a.dueDate != null
                    ? 'Échéance propre à l\'action${e.task?.endDate != null ? ' · tâche : ${_dueLabel(_day(e.task!.endDate!), today)}' : ''}.'
                    : 'Échéance de la tâche « ${e.task?.title ?? ''} ».'),
            FicheActions(
              primaryLabel: running ? 'Arrêter le chrono' : (e.chronoActivityId != null ? 'Chrono' : 'Fait'),
              primaryIcon: running ? Icons.stop_rounded : (e.chronoActivityId != null ? Icons.play_arrow_rounded : Icons.check_rounded),
              onPrimary: () {
                Navigator.pop(ctx);
                if (running) {
                  widget.logic.stopActive();
                } else if (e.chronoActivityId != null) {
                  _launch(e);
                } else {
                  _toggleDone(e, true);
                }
              },
              secondary: [
                (label: 'Caser', onTap: () {
                  Navigator.pop(ctx);
                  _scheduleAction(e);
                }),
                (label: a.dueDate == null ? 'Échéance' : 'Échéance ⚑', onTap: () async {
                  await _pickDueDate(e);
                  refresh();
                }),
                (label: e.chronoActivityId == null ? 'Contextes & chrono' : 'Contextes', onTap: () {
                  Navigator.pop(ctx);
                  _processAction(e);
                }),
                if (e.project != null)
                  (label: 'Projet', onTap: () {
                    Navigator.pop(ctx);
                    _openProject(e.project!, targetTaskId: e.task?.id);
                  }),
                if (e.project == null && e.activity != null)
                  (label: 'Rattacher à un projet', onTap: () {
                    Navigator.pop(ctx);
                    _attachToProject(e);
                  }),
                if (e.chronoActivityId != null && !running)
                  (label: 'Fait', onTap: () {
                    Navigator.pop(ctx);
                    _toggleDone(e, true);
                  }),
              ],
            ),
          ],
        );
      }),
    );
  }

  /// Action simple → projet : choix du projet (actifs, hors dossiers sans
  /// tâche), puis de la tâche (ou « Au fil de l'eau »). L'action prend le
  /// « Pour » du projet et garde son activité pour le chrono.
  Future<void> _attachToProject(_Entry e) async {
    final a = e.activity;
    if (a == null) return;
    final all = _allProjects;
    final candidates = all
        .where((p) => p.status != 'archived' && p.status != 'done' && !isFolderProject(p, all))
        .toList()
      ..sort((x, y) => x.title.toLowerCase().compareTo(y.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun projet actif.')));
      return;
    }
    final p = await showModalBottomSheet<Project>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Rattacher « ${e.action.title} » à…',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in candidates)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: rootProjectOf(p, all).id != p.id
                      ? Text(rootProjectOf(p, all).title, maxLines: 1, overflow: TextOverflow.ellipsis)
                      : null,
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (p == null || !mounted) return;
    final openTasks = p.tasks
        .where((t) => t.status == 'pending' && t.id != _flowTaskId && !isUpcomingTask(t, _day(DateTime.now())))
        .toList();
    String? taskId;
    if (openTasks.isNotEmpty) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Dans quelle tâche de « ${p.title} » ?',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                ListTile(
                  leading: const Icon(Icons.water_outlined),
                  title: const Text('Au fil de l\'eau'),
                  subtitle: const Text('Sans tâche précise'),
                  onTap: () => Navigator.pop(ctx, ''),
                ),
                for (final t in openTasks)
                  ListTile(
                    leading: const Icon(Icons.task_alt_outlined),
                    title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, t.id),
                  ),
              ]),
            ),
          ]),
        ),
      );
      if (picked == null || !mounted) return;
      taskId = picked.isEmpty ? null : picked;
    }
    final target = await _sync.moveOwnActionToProject(
        activity: a, actionId: e.action.id, projectId: p.id, taskId: taskId);
    if (!mounted) return;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rattachement impossible — réessaie.')));
      return;
    }
    widget.logic.onChange();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${e.action.title} » → ${p.title} › ${target.title}'), duration: const Duration(seconds: 3)));
  }

  /// Action validée : titre barré + porteur + date, décochable pour la
  /// remettre en attente.
  Widget _doneTile(ColorScheme cs, _Entry e) {
    final parent = e.project?.title ?? e.activity?.name ?? '';
    final when = _doneLabel(e.action.doneAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Checkbox(
          value: true,
          shape: const CircleBorder(),
          onChanged: (v) => _toggleDone(e, v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Flexible(
                    child: Text(e.action.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.lineThrough,
                            color: cs.onSurface.withOpacity(.55))),
                  ),
                  if (modeChipFor(context, widget.logic, e.action.doneAt) != null) ...[
                    const SizedBox(width: 6),
                    modeChipFor(context, widget.logic, e.action.doneAt)!,
                  ],
                ]),
                if (parent.isNotEmpty || when.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        [
                          if (parent.isNotEmpty) parent,
                          if (when.isNotEmpty) when,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.4))),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}

/// Liste de courses du menu (artefact `weekly_menu`), cochable — affichée
/// dans l'onglet Actions quand le contexte @courses est actif. L'état coché
/// vit sur l'artefact (partagé avec la fiche menu de l'Accueil).
class _CoursesSection extends StatefulWidget {
  final FirestoreSync sync;
  const _CoursesSection({required this.sync});

  @override
  State<_CoursesSection> createState() => _CoursesSectionState();
}

class _CoursesSectionState extends State<_CoursesSection> {
  // Stream créé UNE FOIS (même leçon que ArtifactShortcuts : un stream neuf
  // par build = StreamBuilder qui repart de zéro à chaque rebuild du parent).
  late final Stream<List<Artifact>> _stream =
      widget.sync.streamArtifacts();
  // Partagé entre recréations du State (liste scrollée) — même leçon que
  // ObjectivesCard/ArtifactShortcuts : pas de repli transitoire au retour.
  static List<Artifact> _last = const [];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Artifact>>(
      stream: _stream,
      builder: (ctx, snap) {
        if (snap.hasData) _last = snap.data!;
        final menus = _last
            .where((a) =>
                !a.deleted &&
                a.kind == 'weekly_menu' &&
                a.shoppingList.isNotEmpty)
            .toList();
        if (menus.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in menus) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Row(children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 14, color: cs.onSurface.withOpacity(.45)),
                  const SizedBox(width: 6),
                  Text('COURSES — MENU',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                          color: cs.onSurface.withOpacity(.45))),
                  const Spacer(),
                  Text(
                      '${m.shoppingList.where((s) => !s.checked).length} restants',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(.4))),
                ]),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in m.shoppingList)
                    FilterChip(
                      selected: s.checked,
                      onSelected: (v) {
                        s.checked = v;
                        widget.sync.saveArtifact(m);
                      },
                      label: Text(
                          s.qty.isEmpty ? s.label : '${s.label} ${s.qty}',
                          style: TextStyle(
                              fontSize: 12,
                              decoration: s.checked
                                  ? TextDecoration.lineThrough
                                  : null)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
