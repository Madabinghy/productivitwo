import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/web/badges_web.dart';
import 'package:productivitwo_v1/web/objectives_web.dart';
import 'package:productivitwo_v1/widgets/elan_stats_card.dart';
import 'package:productivitwo_v1/widgets/elan_rows.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/web/mode_web.dart' show webModeChip;
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';
import 'package:productivitwo_v1/utils/block_work.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show linkMirrorsToSessions;
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/sessions_card.dart';
import 'package:productivitwo_v1/web/assistant_history_sheet.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/web/document_viewer_dialog.dart';
import 'package:productivitwo_v1/web/focus_band.dart';
import 'package:productivitwo_v1/web/schedule_block_dialog.dart';
import 'package:productivitwo_v1/web/tomorrow_schedule_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/today_facts.dart';
import 'package:productivitwo_v1/utils/badge_today.dart' show TodayFacts;
import 'package:productivitwo_v1/utils/badges_logic.dart' show BadgeDeck;
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/dashboard_tiles.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart' show computeObjectiveProgress;
import 'package:productivitwo_v1/widgets/stakes_section.dart';
import 'package:productivitwo_v1/widgets/dashboard_tiles.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart';

// Vue Aujourd'hui (refonte web, § 2 du handoff) : MAINTENANT (bloc en cours +
// chrono) · PROGRAMME DU JOUR (frise horaire à l'échelle) · CETTE SEMAINE
// (à traiter, engagements, échéances).

const _kCategoryColor = kBCategoryColor;
const _kCategoryLabel = {
  'project': 'Projets',
  'routine': 'Routines',
  'personal': 'Perso',
  'break': 'Pauses',
};

const _kDays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const _kMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

const _tabular = [FontFeature.tabularFigures()];

String _fmtHm(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _fmtClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String _ddmm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

class TodayView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<Activity> activities;
  final FirestoreSync sync;
  // Bande Focus : objectif du projet + documents (clé = projectId) ; optionnels.
  final List<StrategicObjective> objectives;
  final Map<String, List<Map<String, dynamic>>> documentsByProject;
  final void Function(Project project, {String? taskId}) onOpenProject;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenWeek;
  /// Tuile ACTIONS du tableau de bord : ouvre l'onglet Actions.
  final VoidCallback? onOpenActions;
  /// Heure de bascule de la journée vécue (`data/meta.dayStartMin`).
  final int dayStartMin;
  /// Mode du jour (Modes et coups lot 5), pour l'en-tête ; les chips se calculent sur les pointages.
  final DayMode mode;

  const TodayView({
    super.key,
    required this.projects,
    required this.domains,
    required this.activities,
    required this.sync,
    this.objectives = const [],
    this.documentsByProject = const {},
    required this.onOpenProject,
    required this.onOpenProjects,
    required this.onOpenWeek,
    this.onOpenActions,
    this.dayStartMin = kDefaultDayStartMin,
    this.mode = DayMode.normal,
  });

  @override
  State<TodayView> createState() => TodayViewState();
}

class TodayViewState extends State<TodayView> {
  StreamSubscription<DailySchedule?>? _scheduleSub;
  StreamSubscription<List<Session>>? _sessionsSub;
  StreamSubscription<List<HabitHit>>? _hitsSub;
  Timer? _ticker;

  List<ScheduleBlock> _blocks = [];
  // Tous les blocs vivants (sautés / déplacés compris) : rattachement après
  // coup et compteur « n déplacés · n sautés » (B12).
  List<ScheduleBlock> _allBlocks = [];
  String? _generatedBy;
  List<Session> _sessions = [];
  List<HabitHit> _hits = [];
  List<MoodMark> _moodMarks = [];
  List<ChainRun> _chainRuns = [];
  StreamSubscription<List<MoodMark>>? _moodSub;
  StreamSubscription<List<ChainRun>>? _chainSub;
  final Set<String> _elanSkipped = {};
  late final WebHuntStore _huntStore = WebHuntStore(widget.sync);
  late final WebDeckSource _deckSource = WebDeckSource(widget.sync);
  AppLogic? _logic; // pour valider la routine liée à un bloc (comme Focus)
  // Carte « Au programme » : blocs dépliés (null = défaut : le premier bloc à
  // contenu est ouvert) et liste complète ou non.
  Set<String>? _agendaOpen;
  bool _agendaAll = false;
  bool _routinesAll = false;
  final Set<String> _hit = {};
  bool _busy = false;
  // Mode « Modifier » de la frise : chaque bloc s'ouvre dans l'éditeur.
  bool _editing = false;
  // Frise « Aujourd'hui | Demain » : le programme du lendemain dans la même
  // frise (sans trait « maintenant », ni coche, ni chrono).
  bool _tomorrow = false;
  List<ScheduleBlock> _tomorrowBlocks = [];
  StreamSubscription<DailySchedule?>? _tomorrowSub;
  // Bloc ouvert sur place (contenu cochable), dans la frise ou la liste.
  String? _detailId;
  // Fermé par un clic hors de la carte : si ce clic tombait sur le bloc
  // lui-même, son tap ne doit pas le rouvrir aussitôt.
  String? _closedId;
  DateTime? _closedAt;
  // Zoom VERTICAL de la frise (1 = la journée tient dans la hauteur) :
  // Ctrl / ⌘ + molette ou pincement autour du curseur, boutons − / +.
  // Mémorisé dans le navigateur.
  double _zoom = 1;
  static const _kZoomMin = 1.0, _kZoomMax = 8.0, _kZoomKey = 'today_timeline_zoom';
  double _tlPpm = 1, _tlStartMin = 0;
  // Survol d'un créneau vide de la frise : fantôme « + HH:MM » (clic = bloc).
  int? _hoverMin;
  // Bloc survolé : bouton « + » pour poser un bloc en parallèle.
  String? _hoverBlockId;
  // Glisser un bloc (déplacer) ou tirer son bord bas (durée), au pas de 5 min.
  String? _dragId;
  double _dragDy = 0;
  bool _dragResize = false;
  static const _kDragSnap = 5;
  // Modules de la colonne de droite repliés (accordéon), mémorisés.
  // Allègement 2026-10 : Badges, Élan et Objectifs du jour repliés par défaut ;
  // le choix de la personne (SharedPreferences) prime dès qu'il existe.
  Set<String> _folded = {'badges', 'elan', 'objectives'};
  static const _kFoldedKey = 'today_side_folded';
  late String _today;
  // Frise : défilement automatique vers le trait « maintenant » dès qu'elle
  // est affichée — à l'arrivée sur l'onglet, au premier programme chargé, au
  // changement de jour, et quand elle réapparaît après la disposition active
  // (chrono ou pas : un chrono hors bloc laisse la frise visible). Le flag est
  // consommé au build suivant de la frise.
  final ScrollController _timelineCtrl = ScrollController();
  bool _scrollNowPending = false;
  bool _initialScrollDone = false;
  bool _timelineHidden = false;

  @override
  void initState() {
    super.initState();
    _today = livedProgramYmd(DateTime.now(), widget.dayStartMin);
    SharedPreferences.getInstance().then((prefs) {
      final z = prefs.getDouble(_kZoomKey);
      if (z != null && mounted) setState(() => _zoom = z.clamp(_kZoomMin, _kZoomMax));
      final f = prefs.getStringList(_kFoldedKey);
      if (f != null && mounted) setState(() => _folded = f.toSet());
    }).catchError((_) {});
    _subscribe();
    _loadLogic();
    _deckSource.addListener(_onDeck);
    _deckSource.fetch();
    // Horloge : chrono, ligne « maintenant » et changement de jour.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Journée vécue : le jour change à l'heure de bascule, pas à minuit.
      final t = livedProgramYmd(DateTime.now(), widget.dayStartMin);
      if (t != _today) {
        _today = t;
        _tomorrow = false;
        _tomorrowSub?.cancel();
        _tomorrowSub = null;
        _scheduleSub?.cancel();
        _scheduleSub = widget.sync.streamDailySchedule(_today).listen(_onSchedule);
        _scrollNowPending = true;
      }
      _checkBlockTransition();
      setState(() {});
    });
  }

  /// Recentre la frise sur l'heure courante (appelé par le shell quand
  /// l'onglet Aujourd'hui est activé).
  void scrollToNow() {
    if (!mounted) return;
    setState(() => _scrollNowPending = true);
  }

  /// Réveil au changement de bloc : un bloc vient de devenir courant alors que
  /// le chrono tourne sur autre chose → la carte passe « hors bloc » d'elle-même,
  /// et une barre propose le rattachement (une fois par couple session × bloc).
  final _blockWatcher = BlockTransitionWatcher();

  void _checkBlockTransition() {
    final open = _openSession;
    final b = _blockWatcher.tick(
      blocks: _blocks,
      nowMin: _nowMin,
      open: open,
      matches: _sessionOnBlock,
    );
    if (b == null || open == null) return;
    final attachable = _canAttach(b);
    final who = _activityName(open.activityId) ?? 'ton chrono';
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text('« ${b.title} » commence — $who, c\'est pour ce bloc ?'),
      duration: const Duration(seconds: 12),
      action: attachable
          ? SnackBarAction(label: 'Pour ce bloc', onPressed: () => _attachToBlock(open, b))
          : null,
    ));
  }

  void _subscribe() {
    _scheduleSub = widget.sync.streamDailySchedule(_today).listen(_onSchedule);
    _sessionsSub = widget.sync.streamSessions().listen((s) {
      if (mounted) setState(() => _sessions = s);
    });
    _moodSub = widget.sync.streamMoodMarks().listen((m) {
      if (mounted) setState(() => _moodMarks = m);
    });
    _chainSub = widget.sync.streamChainRuns().listen((r) {
      if (mounted) setState(() => _chainRuns = r);
    });
    _hitsSub = widget.sync.streamHabitHits().listen((h) {
      if (mounted) setState(() => _hits = h);
    });
  }

  void _onSchedule(DailySchedule? s) {
    if (!mounted) return;
    final all = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    // Miroirs agenda du jour d'une séance → reliés à la séance (en mémoire).
    final day = DateTime.tryParse(_today);
    if (day != null) linkMirrorsToSessions(all, widget.projects, day);
    // B12 : sautés / déplacés hors de la vue.
    final blocks = all.where((b) => b.status != 'skipped').toList();
    if (!_initialScrollDone && blocks.isNotEmpty) {
      _initialScrollDone = true;
      _scrollNowPending = true;
    }
    setState(() {
      _allBlocks = all;
      _blocks = blocks;
      _generatedBy = s?.generatedBy;
    });
  }

  Future<void> _loadLogic() async {
    final state = await widget.sync.pull();
    if (state == null || !mounted) return;
    final logic = AppLogic(state, () {});
    logic.sync = widget.sync;
    setState(() => _logic = logic);
  }

  @override
  void dispose() {
    _scheduleSub?.cancel();
    _sessionsSub?.cancel();
    _hitsSub?.cancel();
    _moodSub?.cancel();
    _chainSub?.cancel();
    _huntStore.dispose();
    _deckSource.removeListener(_onDeck);
    _deckSource.dispose();
    _tomorrowSub?.cancel();
    _ticker?.cancel();
    _timelineCtrl.dispose();
    super.dispose();
  }

  // ── Données dérivées ────────────────────────────────────────────────────────

  Session? get _openSession {
    Session? last;
    for (final s in _sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  /// Minute vécue : après minuit, on continue la veille (00:30 → 24 h 30) pour
  /// se comparer aux blocs du programme vécu (Sommeil 22:00 → 05:00 en cours).
  int get _nowMin => livedNowMin(DateTime.now(), widget.dayStartMin);

  /// Date (jour seul) de la journée vécue.
  DateTime get _livedToday => livedDate(DateTime.now(), widget.dayStartMin);

  ({ScheduleBlock block, bool current})? get _focusBlock =>
      focusBlock(_blocks, _nowMin);

  ScheduleBlock? _nextAfter(ScheduleBlock block) => nextBlockAfter(_blocks, block);

  /// Cible de la bande Focus : action en cours de chrono (null = carte
  /// MAINTENANT classique).
  FocusTarget? get _focusTarget {
    final f = _focusBlock;
    return resolveFocusTarget(
      open: _openSession,
      currentBlock: f != null && f.current ? f.block : null,
      projects: widget.projects,
    );
  }

  String? _activityName(String? id) => _activityOf(id)?.name;

  Activity? _activityOf(String? id) {
    if (id == null) return null;
    for (final a in widget.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  Project? _project(String? id) {
    if (id == null) return null;
    for (final p in widget.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  String get _tomorrowKey => ymdOf(_livedToday.add(const Duration(days: 1)));

  /// Jour affiché par la frise et blocs correspondants.
  String get _cardDate => _tomorrow ? _tomorrowKey : _today;
  List<ScheduleBlock> get _cardBlocks => _tomorrow ? _tomorrowBlocks : _blocks;

  void _setTomorrow(bool v) {
    if (v == _tomorrow) return;
    _tomorrowSub?.cancel();
    _tomorrowSub = null;
    setState(() {
      _tomorrow = v;
      _detailId = null;
      _editing = false;
      if (!v) _scrollNowPending = true;
    });
    if (!v) return;
    final key = _tomorrowKey;
    _tomorrowSub = widget.sync.streamDailySchedule(key).listen((s) {
      if (!mounted) return;
      final blocks = (s?.blocks.where((b) => b.status != 'deleted' && b.status != 'skipped').toList() ??
          [])
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final day = DateTime.tryParse(key);
      if (day != null) linkMirrorsToSessions(blocks, widget.projects, day);
      setState(() => _tomorrowBlocks = blocks);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _timelineCtrl.hasClients) _timelineCtrl.jumpTo(0);
    });
  }

  Future<void> _askClaudeTomorrow() async {
    final ok = await launchUrl(
        claudeNewUri(planDayPrompt(date: _tomorrowKey, blocks: _tomorrowBlocks)),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir Claude')));
    }
  }

  /// Tâche (et son projet) visée par un bloc, cherchée par id dans tous les
  /// projets (bloc posé depuis la vue fusionnée d'un dossier).
  ({Project project, ProjectTask task})? _taskOf(ScheduleBlock b) {
    final tid = b.taskId;
    if (tid == null || tid.isEmpty) return null;
    final own = _project(b.projectId);
    for (final p in [if (own != null) own, ...widget.projects]) {
      for (final t in p.tasks) {
        if (t.id == tid) return (project: p, task: t);
      }
    }
    return null;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _startChrono(ScheduleBlock b) async {
    final actId = b.activityId ?? _project(b.projectId)?.linkedActivityId;
    if (actId == null) return;
    final now = DateTime.now();
    for (final s in _sessions.where((s) => s.endAt == null)) {
      s.endAt = now;
      await widget.sync.saveSession(s);
    }
    final session = Session(
      activityId: actId,
      startAt: now,
      taskId: b.taskId,
      actionId: b.actionId,
    );
    setState(() => _sessions = [..._sessions, session]);
    await widget.sync.saveSession(session);
  }

  /// Chrono sur une activité sans bloc (module Objectifs du jour).
  Future<void> _startActivityChrono(String activityId) async {
    final now = DateTime.now();
    for (final s in _sessions.where((s) => s.endAt == null)) {
      s.endAt = now;
      await widget.sync.saveSession(s);
    }
    final session = Session(activityId: activityId, startAt: now);
    setState(() => _sessions = [..._sessions, session]);
    await widget.sync.saveSession(session);
  }

  Future<void> _stopChrono() async {
    final s = _openSession;
    if (s == null) return;
    s.endAt = DateTime.now();
    setState(() {});
    await widget.sync.saveSession(s);
  }

  /// `sessionMatchesBlock` avec les activités liées résolues (projet, routine).
  bool _sessionOnBlock(Session s, ScheduleBlock b) => sessionMatchesBlock(s, b,
      projectLinkedActivityId: _project(b.projectId)?.linkedActivityId,
      activityLinkedActivityId: _activityOf(b.activityId)?.linkedActivityId);

  /// Chrono en cours SUR la source du bloc en cours : la vue passe en
  /// disposition active (MAINTENANT prend la largeur, programme en liste).
  /// Null = disposition de repos. Les blocs de tâche sont servis avant par la
  /// bande Focus (`_focusTarget`).
  ({ScheduleBlock block, Session open})? get _liveBlock {
    final open = _openSession;
    final f = _focusBlock;
    if (open == null || f == null || !f.current) return null;
    return _sessionOnBlock(open, f.block) ? (block: f.block, open: open) : null;
  }

  bool _canAttach(ScheduleBlock b) => canAttachSessionToBlock(b,
      blockActivity: _activityOf(b.activityId), project: _project(b.projectId));

  /// « Pour ce bloc » : le chrono en cours (lancé sur autre chose, ou avant
  /// l'heure du bloc) est ré-attribué au bloc. Le chrono fait foi : la session
  /// garde son activité ; un bloc sans tâche sur une autre activité (ou libre :
  /// agenda Google, perso) prend celle du chrono — même règle que le mobile.
  Future<void> _attachToBlock(Session s, ScheduleBlock b) async {
    final r = attachSessionToBlock(s, b,
        blockActivity: _activityOf(b.activityId), project: _project(b.projectId));
    if (r == AttachResult.none) return;
    setState(() {});
    await widget.sync.saveSession(s);
    if (r == AttachResult.sessionAndBlock) {
      await widget.sync.upsertScheduleBlock(_today, b);
    }
  }

  Future<void> _toggleDone(ScheduleBlock b) async {
    if (_busy) return;
    _busy = true;
    try {
      final newStatus = b.status == 'done' ? 'pending' : 'done';
      setState(() {
        b.status = newStatus;
        if (newStatus == 'pending') b.noAutoWin = true;
      });
      // Geste manuel : décocher ici interdit au mobile de recocher ce bloc.
      await widget.sync.updateBlockStatus(_today, b.id, newStatus, manual: true);
      if (newStatus == 'done') _completeLinkedRoutine(b);
    } finally {
      _busy = false;
    }
  }

  /// Coche un item de la checklist de l'action visée par le bloc en cours.
  /// Dernier item coché = action faite (règle CLAUDE.md) ; on le signale.
  Future<void> _toggleBlockChecklist(
      Project p, TaskAction a, ChecklistItem c, bool done) async {
    final changed = setChecklistItem(a, c.id, done);
    setState(() {});
    await widget.sync.patchActionOf(p, a);
    if (!changed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _addBlockChecklist(Project p, TaskAction a, String title) async {
    if (addChecklistItem(a, title) == null) return;
    setState(() {});
    await widget.sync.patchActionOf(p, a);
  }

  Future<void> _toggleTaskAction(Project p, TaskAction a, bool done) async {
    setState(() {
      a.done = done;
      a.doneAt = done ? DateTime.now() : null;
    });
    await widget.sync.patchActionOf(p, a);
  }

  /// « ✓ Action faite » de la bande Focus : l'action est faite, le chrono
  /// s'arrête, le bloc d'origine passe à fait. « Annuler » rouvre l'action.
  Future<void> _finishFocus(FocusTarget t) async {
    final wasDone = t.action.done;
    if (!wasDone) await _toggleTaskAction(t.project, t.action, true);
    final b = t.block;
    if (b != null) {
      await _finishBlock(b);
    } else {
      await _stopChrono();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text('Action faite : ${t.action.title}'),
      duration: const Duration(seconds: 5),
      action: wasDone
          ? null
          : SnackBarAction(
              label: 'Annuler', onPressed: () => _toggleTaskAction(t.project, t.action, false)),
    ));
  }

  /// Cible et chrono exposés au shell (pastille de la barre + tiroir Focus).
  FocusTarget? get focusTarget => _focusTarget;
  Session? get openSession => _openSession;

  /// Tiroir Focus (depuis n'importe quel onglet) : même contenu que la
  /// bande, en colonne. Construit ici pour partager toutes les actions.
  Widget focusDrawer(FocusTarget t, {required VoidCallback onClose}) =>
      _focusBand(t, compact: true, onClose: onClose);

  Widget _focusBand(FocusTarget t, {bool compact = false, VoidCallback? onClose}) {
    StrategicObjective? obj;
    for (final o in widget.objectives) {
      if (o.id == t.project.strategicObjectiveId) obj = o;
    }
    return FocusBand(
      target: t,
      open: _openSession!,
      blocks: _blocks,
      objective: obj,
      documents: focusDocuments(widget.documentsByProject[t.project.id] ?? const [], t.task.id),
      sync: widget.sync,
      onOpenProject: widget.onOpenProject,
      onToggleChecklist: (a, c, v) => _toggleBlockChecklist(t.project, a, c, v),
      onAddChecklist: (a, title) => _addBlockChecklist(t.project, a, title),
      onToggleAction: (a, v) => _toggleTaskAction(t.project, a, v),
      onPause: _stopChrono,
      onDone: () => _finishFocus(t),
      compact: compact,
      onClose: onClose,
    );
  }

  Future<void> _editBlock(ScheduleBlock b) async {
    final date = _cardDate;
    final updated = await showScheduleBlockDialog(context, block: b);
    if (updated == null || !mounted) return;
    // Soft-delete : retiré de la frise tout de suite, le flux confirmera.
    final cancelled = isCancelledBlock(updated);
    setState(() {
      if (updated.status == 'deleted' || cancelled) _blocks.remove(updated);
    });
    await widget.sync.upsertScheduleBlock(date, updated);
    if (cancelled && mounted) {
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text('« ${updated.title} » annulé — il sort du programme'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => widget.sync.setBlockCancelled(date, updated.id, false),
        ),
      ));
    }
  }

  /// Nouveau bloc : à [at] (clic dans la frise), sinon au prochain quart
  /// d'heure après la fin du dernier bloc (demain : à partir de 8 h).
  Future<void> _addBlock({int? at, int duration = 30}) async {
    final date = _cardDate;
    var start = at;
    if (start == null) {
      final n = DateTime.now();
      start = _tomorrow ? 8 * 60 : n.hour * 60 + n.minute;
      for (final b in _cardBlocks) {
        start = math.max(start!, blockEndMin(b));
      }
      start = math.min(((start! + 14) ~/ 15) * 15, 23 * 60 + 45);
    }
    final created = await showScheduleBlockDialog(
      context,
      isNew: true,
      block: ScheduleBlock(
        startTime:
            '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}',
        durationMin: duration,
        title: '',
      ),
    );
    if (created == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(date, created);
  }

  Future<void> _finishBlock(ScheduleBlock b) async {
    final open = _openSession;
    if (open != null) await _stopChrono();
    if (b.status != 'done') await _toggleDone(b);
  }

  /// Même règle que `WebDailyScheduleCard` : 1 incrément de la routine liée,
  /// capé à la cible, une seule fois par bloc.
  void _completeLinkedRoutine(ScheduleBlock block) {
    final logic = _logic;
    final id = block.activityId;
    if (logic == null || id == null || _hit.contains(block.id)) return;
    Activity? act;
    for (final a in logic.state.activities) {
      if (a.id == id) {
        act = a;
        break;
      }
    }
    if (act == null || !act.isHabit) return;
    final today = _livedToday;
    _hit.add(block.id);
    final tgt = logic.activeHabitTarget(act);
    if (tgt > 0 && livedHitCount(logic.state.habitHits, id, DateTime.now(), widget.dayStartMin) >= tgt) return;
    logic.incHabit(id, 1, today);
    final key = yyyymmdd(today);
    HabitProgress? hp;
    for (final h in logic.state.habitProgress) {
      if (h.activityId == id && h.yyyymmdd == key) hp = h;
    }
    if (hp != null) widget.sync.saveHabitProgress(hp);
    if (logic.state.habitHits.isNotEmpty) {
      widget.sync.saveHabitHit(logic.state.habitHits.last);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Routine validée : ${act.name}'),
        duration: const Duration(milliseconds: 1400),
      ));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBBg,
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 18),
          if (MediaQuery.sizeOf(context).width >= 1064) ...[
            _dashboard(row: true),
            const SizedBox(height: 18),
          ],
          Expanded(
            child: LayoutBuilder(builder: (ctx, box) {
              // Chrono sur une action → la carte MAINTENANT se déploie en
              // bande Focus pleine largeur (étapes + contexte).
              final focus = _focusTarget;
              if (box.maxWidth < 1000) {
                // Écran étroit : les trois temps s'empilent.
                return ListView(children: [
                  if (MediaQuery.sizeOf(context).width < 1064) _dashboard(row: false),
                  ..._dayBoard(),
                  if (focus != null) _focusBand(focus) else _nowCard(),
                  ..._stakesList(),
                  const SizedBox(height: 18),
                  _agendaCard(),
                  const SizedBox(height: 18),
                  SizedBox(height: 640, child: _timelineCard()),
                  const SizedBox(height: 18),
                  _sideColumn(),
                ]);
              }
              if (focus != null) {
                return ListView(children: [
                  _focusBand(focus),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 640,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _timelineCard()),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 340,
                          child: SingleChildScrollView(
                              child: _sideColumn(withAgenda: true)),
                        ),
                      ],
                    ),
                  ),
                ]);
              }
              // Chrono SUR le bloc en cours (bloc d'activité) → disposition
              // active : MAINTENANT prend la largeur, le programme se replie
              // en liste de 340 px (handoff « Maintenant en mode actif », A).
              // Sous 1280 px la colonne large ferait moins de 490 px : on
              // garde la disposition de repos.
              final live = box.maxWidth >= 1280 ? _liveBlock : null;
              if (live != null) {
                // La frise est remplacée par la liste compacte : quand elle
                // reviendra, elle se recentrera.
                _timelineHidden = true;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _nowCardWide(live.block, live.open)),
                    const SizedBox(width: 24),
                    SizedBox(width: 340, child: _scheduleListCard()),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(child: _sideColumn()),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // MAINTENANT puis le contenu concret des blocs à venir.
                  SizedBox(
                    width: 340,
                    child: ListView(children: [
                      ..._dayBoard(),
                      _nowCard(),
                      ..._stakesList(),
                      const SizedBox(height: 18),
                      _agendaCard(),
                    ]),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _timelineCard()),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 340,
                    child: SingleChildScrollView(child: _sideColumn()),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Aujourd'hui en enjeux (web, 2026-10-30) ─────────────────────────────────
  void _onDeck() {
    if (mounted) setState(() {});
  }

  BadgeDeck _deck() => _deckSource.deck(
        activities: widget.activities,
        hits: _hits,
        projects: widget.projects,
        objectives: widget.objectives,
        sessions: _sessions,
        moodMarks: _moodMarks,
        chainRuns: _chainRuns,
        dayStartMin: widget.dayStartMin,
        emberSpends: _huntStore.emberSpends,
      );

  String _stakesKey = '';
  StakeBoard _stakes = StakeBoard.empty;
  TodayFacts? _facts;

  /// Faits du jour + tableau des enjeux, recalculés au plus une fois par
  /// minute ou quand une donnée change (le ticker redessine chaque seconde).
  StakeBoard _board() {
    final now = DateTime.now();
    final deck = _deck();
    final key = '${now.hour}:${now.minute}|${_hits.length}|${_sessions.length}|${_moodMarks.length}|${identityHashCode(_allBlocks)}|'
        '${identityHashCode(widget.projects)}|${identityHashCode(widget.activities)}|${identityHashCode(widget.objectives)}|'
        '${identityHashCode(deck)}|${_huntStore.hunts.length}';
    if (key == _stakesKey && _facts != null) return _stakes;
    _stakesKey = key;
    final ymd = ymdOf(_livedToday);
    final facts = _facts = composeTodayFacts(
      ymd: ymd,
      now: now,
      dayStartMin: widget.dayStartMin,
      activities: widget.activities,
      hits: _hits,
      sessions: _sessions,
      moodMarks: _moodMarks,
      objectives: widget.objectives,
      projects: widget.projects,
      schedule: DailySchedule(date: _today, blocks: _allBlocks),
    );
    return _stakes = buildStakeBoard(
      deck: deck,
      facts: facts,
      hunts: _huntStore.hunts,
      projects: widget.projects,
      activities: widget.activities.where((a) => !a.deleted).toList(),
      dayStartMin: widget.dayStartMin,
    );
  }

  bool get _evening => isEvening(_nowMin);

  /// Tableau du jour (ou bilan du soir après 19 h), en tête de la colonne
  /// MAINTENANT.
  List<Widget> _dayBoard() {
    final board = _board();
    if (_evening) {
      final now = DateTime.now();
      final ledger = buildEveningLedger(
        board: board,
        deck: _deck(),
        projects: widget.projects,
        activities: widget.activities,
        sessions: _sessions,
        objectiveDays: _facts?.objectiveDays ?? const [],
        dayStart: livedDayStart(now, widget.dayStartMin),
        now: now,
        perfectToday: _facts != null && isPerfectSoFar(_facts!),
        emberStock: _deck().embers.available,
      );
      if (ledger.isEmpty) return const [];
      return [EveningLedgerCard(ledger: ledger), const SizedBox(height: 18)];
    }
    if (board.isEmpty) return const [];
    return [StakeScoreboard(board: board, elapsed: dayElapsed(_nowMin)), const SizedBox(height: 18)];
  }

  List<Widget> _stakesList() {
    final board = _board();
    if (board.isEmpty || (_evening && board.inPlay == 0)) return const [];
    return [
      const SizedBox(height: 4),
      StakesList(board: board, onRun: _runStake, onOpenBadges: _openBadgesInPlay, evening: _evening),
    ];
  }

  /// Fait le geste d'un enjeu : +1, chrono d'activité, bloc, chrono sur l'action.
  void _runStake(Stake s) {
    final g = s.gesture;
    switch (g.kind) {
      case StakeGestureKind.routine:
        if (g.activity != null) _incRoutine(g.activity!);
      case StakeGestureKind.activity:
        if (g.activity != null) _startActivityChrono(g.activity!.id);
      case StakeGestureKind.block:
        if (g.block != null) _startChrono(g.block!);
      case StakeGestureKind.action:
        _startActionChrono(g);
    }
  }

  Future<void> _startActionChrono(StakeGesture g) async {
    final a = g.action;
    if (a == null) return;
    final actId = a.linkedActivityId ?? g.project?.linkedActivityId ?? g.owner?.id;
    if (actId == null) {
      if (g.project != null) widget.onOpenProject(g.project!, taskId: g.task?.id);
      return;
    }
    final now = DateTime.now();
    for (final s in _sessions.where((s) => s.endAt == null)) {
      s.endAt = now;
      await widget.sync.saveSession(s);
    }
    final session = Session(activityId: actId, startAt: now, taskId: g.task?.id, actionId: a.id);
    setState(() => _sessions = [..._sessions, session]);
    await widget.sync.saveSession(session);
  }

  void _openBadgesInPlay() {
    final data = badgesInPlay(_board(), _deck());
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 560,
          height: 680,
          child: BadgesInPlayScreen(
            data: data,
            onRun: _runStake,
            embers: _deck().embers,
            names: {for (final a in widget.activities) a.id: a.name},
          ),
        ),
      ),
    );
  }

  void _unfold(String key) {
    if (_isFolded(key)) _toggleFold(key);
  }

  /// « TON TABLEAU DE BORD » : une tuile par vue, tap = la vue complète.
  Widget _dashboard({required bool row}) {
    final board = _board();
    final facts = _facts;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final routines = facts?.routines ?? const [];
    final reached = routines.where((r) => r.reached).length;
    final active = widget.activities.where((a) => !a.deleted).toList();
    final objectives = widget.objectives.where((o) => o.status == 'active').toList();
    return DashboardTiles(
      row: row,
      program: programTile(_blocks, _nowMin) ??
          const ProgramTile(value: 'Rien de prévu', sub: 'ajoute un bloc dans la frise', strip: []),
      routines: routinesTile(
        done: reached,
        total: routines.length,
        toDoNow: [for (final r in routines) if (!r.reached) r.activity.name],
        momentLabel: 'aujourd’hui',
        seriesRunning: _deck().seriesRunning,
      ),
      objectives: objectivesTile([
        for (final o in objectives) (o.title, computeObjectiveProgress(o, widget.activities, _sessions, _hits, now).weekPercent),
      ]),
      badges: badgesTile(_deck(), board),
      perfect: perfectDayTile(facts, _deck().embers),
      actions: actionsTile(projects: widget.projects, activities: active, today: today),
      projects: projectsTile(widget.projects, today, sessions: _sessions),
      onProgram: scrollToNow,
      onRoutines: () => _unfold('routines'),
      onObjectives: () => _unfold('objectives'),
      onBadges: _openBadgesInPlay,
      onPerfect: _openBadgesInPlay,
      onActions: widget.onOpenActions,
      onProjects: widget.onOpenProjects,
    );
  }

  // En-tête : date + résumé, bandeau ORION à droite.
  Widget _header() {
    final now = _livedToday;
    final title = '${_kDays[now.weekday - 1]} ${now.day} ${_kMonths[now.month - 1]}';
    final done = _blocks.where((b) => b.status == 'done').length;
    final remaining = remainingPlannedMin(_blocks, _nowMin);
    final summary = _blocks.isEmpty
        ? 'Aucun programme pour aujourd\'hui'
        : '$done bloc${done > 1 ? 's' : ''} fait${done > 1 ? 's' : ''} sur ${_blocks.length}'
            '${remaining > 0 ? ' · ${_fmtHm(remaining)} planifiées restantes' : ''}'
            '${_generatedBy == 'auto' ? ' · planifiée automatiquement' : ''}'
            '${widget.mode == DayMode.normal ? '' : ' · mode ${kModeLabels[widget.mode]}'}';
    return Row(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
        const SizedBox(height: 3),
        Text(summary,
            style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
      ]),
      const SizedBox(width: 20),
      Tooltip(
        message: 'Voir et préparer le programme de demain',
        child: _pillButton('Demain →', height: 34, onTap: _openTomorrow),
      ),
      const SizedBox(width: 24),
      Expanded(child: Align(alignment: Alignment.centerRight, child: _orionBanner())),
    ]);
  }

  void _openTomorrow() => showTomorrowScheduleDialog(context, widget.sync,
      projects: widget.projects, activities: widget.activities, dayStartMin: widget.dayStartMin);

  Widget _orionBanner() {
    return ValueListenableBuilder<List<AssistantMessageData>>(
      valueListenable: assistantMessagesNotifier,
      builder: (context, msgs, _) {
        if (msgs.isEmpty) return const SizedBox.shrink();
        final m = msgs.first;
        final action = m.action;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Container(
            height: 48,
            padding: const EdgeInsets.only(left: 16, right: 7),
            decoration: BoxDecoration(
              color: kBSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kBPrimary.withOpacity(.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_awesome, size: 15, color: kBPrimary),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(
                        text: 'ORION',
                        style: TextStyle(fontWeight: FontWeight.w600, color: kBText)),
                    TextSpan(text: ' · ${m.text.replaceAll('\n', ' ')}'),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: kBText2),
                ),
              ),
              const SizedBox(width: 10),
              if (action != null && assistantActionHandler != null) ...[
                _pillButton(action.label ?? 'Voir', primary: true, height: 34,
                    onTap: () => assistantActionHandler?.call(action)),
                const SizedBox(width: 6),
              ],
              _pillButton(msgs.length > 1 ? '+${msgs.length - 1}' : 'Historique',
                  height: 34, onTap: () => AssistantHistorySheet.show(context)),
            ]),
          ),
        );
      },
    );
  }

  // ── MAINTENANT ──────────────────────────────────────────────────────────────

  Widget _nowCard() {
    final focus = _focusBlock;
    final open = _openSession;
    final children = <Widget>[
      _label('MAINTENANT', dot: true),
      const SizedBox(height: 18),
    ];

    if (focus == null && open == null) {
      children.addAll([
        const SizedBox(height: 40),
        const Icon(Icons.wb_twilight_outlined, size: 34, color: kBText4),
        const SizedBox(height: 12),
        Text(
          _blocks.isEmpty
              ? 'Pas de programme aujourd\'hui.\nDemande à Claude de planifier ta journée.'
              : 'Plus rien au programme.\nBelle journée.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: kBText3, height: 1.5),
        ),
      ]);
    } else {
      final b = focus?.block;
      final isCurrent = focus?.current ?? false;
      // Le chrono tourne-t-il sur la SOURCE du bloc en cours ? Sinon la carte
      // montre ce qu'on fait ET ce qui était prévu, sans jamais cocher le bloc
      // par accident (même règle que la carte mobile).
      final onBlock = open != null && b != null && isCurrent && _sessionOnBlock(open, b);
      final aside = open != null && b != null && isCurrent && !onBlock;
      // Bloc qui commence dans les 15 min : un chrono lancé avant l'heure
      // peut déjà lui être rattaché.
      final soon = b != null &&
          !isCurrent &&
          blockStartMin(b) > _nowMin &&
          blockStartMin(b) - _nowMin <= kBlockAttachLookaheadMin;
      final attachable = open != null &&
          b != null &&
          !onBlock &&
          (isCurrent || soon) &&
          _canAttach(b);
      // Le chrono en cours prime ; sinon le temps écoulé dans le créneau.
      final Duration elapsed;
      final int totalMin;
      if (open != null) {
        elapsed = DateTime.now().difference(open.startAt);
        totalMin = onBlock ? b.durationMin : math.max(elapsed.inMinutes, 1);
      } else if (b != null && isCurrent) {
        final n = DateTime.now();
        final start = _livedToday.add(Duration(minutes: blockStartMin(b)));
        elapsed = n.difference(start);
        totalMin = b.durationMin;
      } else {
        elapsed = Duration.zero;
        totalMin = b?.durationMin ?? 1;
      }
      final progress = (elapsed.inSeconds / (totalMin * 60)).clamp(0.0, 1.0);
      final catColor = _kCategoryColor[b?.category] ?? kBPrimaryDark;
      final origin = b?.projectId != null
          ? _project(b!.projectId)?.title
          : _activityName(b?.activityId);
      final canChrono =
          b != null && (b.activityId ?? _project(b.projectId)?.linkedActivityId) != null;
      final next = b != null ? _nextAfter(b) : null;

      children.addAll([
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _RingPainter(progress, running: open != null),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    isCurrent || open != null ? _fmtClock(elapsed) : b!.startTime,
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: kBText,
                        letterSpacing: -1,
                        fontFeatures: _tabular),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    open != null
                        ? (aside ? 'chrono en cours · hors bloc' : 'chrono en cours')
                        : isCurrent
                            ? 'sur ${_fmtHm(totalMin)} · chrono arrêté'
                            : 'prochain bloc',
                    style: const TextStyle(fontSize: 12, color: kBText3),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (aside) ...[
          Text(_activityName(open.activityId) ?? 'Chrono libre',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 6),
          Text(
            'Prévu : ${b.title} · jusqu\'à ${_clockOf(blockEndMin(b))}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: kBText3),
          ),
        ] else if (b != null) ...[
          if (origin != null)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: catColor, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(origin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: kBText2)),
              ),
            ]),
          const SizedBox(height: 6),
          Text(b.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 6),
          Text(
            isCurrent
                ? 'jusqu\'à ${_clockOf(blockStartMin(b) + b.durationMin)}'
                    '${next != null ? ' · ensuite ${next.title}' : ''}'
                : 'à ${_clockOf(blockStartMin(b))} · ${_fmtHm(b.durationMin)}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: kBText3),
          ),
          ..._nowChecklist(b),
        ] else
          Text(_activityName(open?.activityId) ?? 'Chrono libre',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: kBText)),
        if (_elanRow(b, open) case final row?) row,
        const SizedBox(height: 18),
        Row(children: [
          if (open != null) ...[
            Expanded(
              child: _pillButton(
                  onBlock
                      ? 'Terminer le bloc'
                      : aside
                          ? 'Arrêter'
                          : 'Arrêter le chrono',
                  primary: true,
                  onTap: () => onBlock ? _finishBlock(b) : _stopChrono()),
            ),
            if (onBlock) ...[
              const SizedBox(width: 10),
              _pillButton('Pause', onTap: _stopChrono),
            ],
            if (attachable) ...[
              const SizedBox(width: 10),
              _pillButton('Pour ce bloc', onTap: () => _attachToBlock(open, b)),
            ],
            if (aside) ...[
              const SizedBox(width: 10),
              _pillButton('Fait', onTap: () => _toggleDone(b)),
            ],
          ] else if (b != null) ...[
            if (canChrono) ...[
              Expanded(
                child: _pillButton(isCurrent ? 'Lancer le chrono' : 'Commencer maintenant',
                    primary: true, onTap: () => _startChrono(b)),
              ),
              const SizedBox(width: 10),
              _pillButton('Fait', onTap: () => _toggleDone(b)),
            ] else
              Expanded(
                child: _pillButton('Marquer comme fait',
                    primary: isCurrent, onTap: () => _toggleDone(b)),
              ),
          ],
        ]),
      ]);
    }

    children.addAll([
      const Spacer(),
      _dayGlance(),
    ]);

    return _card(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: LayoutBuilder(builder: (ctx, box) {
        // Hauteur bornée (colonne) → Spacer ; sinon (empilé) → colonne simple.
        if (box.maxHeight.isFinite) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final w in children)
              if (w is Spacer) const SizedBox(height: 22) else w,
          ],
        );
      }),
    );
  }

  String _clockOf(int min) =>
      '${(min ~/ 60) % 24} h ${(min % 60).toString().padLeft(2, '0')}';

  // ── MAINTENANT en mode actif (disposition A) ────────────────────────────────

  /// Carte large : anneau + temps restant, titre, boutons ; puis déroulé du
  /// bloc (checklist de l'action visée) et contexte (temps du jour, semaine,
  /// dernière fois, documents) ; « Ensuite » ; la journée en un coup d'œil.
  Widget _nowCardWide(ScheduleBlock b, Session open) {
    final now = DateTime.now();
    final elapsed = now.difference(open.startAt);
    final endMin = blockEndMin(b);
    final remaining = math.max(0, endMin - _nowMin);
    final progress = (elapsed.inSeconds / (b.durationMin * 60)).clamp(0.0, 1.0);
    final catColor = _kCategoryColor[b.category] ?? kBPrimaryDark;
    final project = _project(b.projectId);
    final act = _activityOf(open.activityId);
    final origin = [
      if (project != null) project.title,
      if (act != null && act.name != project?.title) act.name,
    ].join(' · ');
    final next = _nextAfter(b);
    final steps = _blockSteps(b);

    return _card(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: LayoutBuilder(builder: (ctx, box) {
        // Carte serrée (< 600 px) : anneau et titre plus petits.
        final tight = box.maxWidth < 600;
        final ring = tight ? 200.0 : 240.0;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _label('MAINTENANT', dot: true),
          const SizedBox(width: 10),
          _chip('sur le bloc'),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          SizedBox(
            width: ring,
            height: ring,
            child: CustomPaint(
              painter: _RingPainter(progress, running: true),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_fmtClock(elapsed),
                      style: TextStyle(
                          fontSize: tight ? 42 : 52,
                          fontWeight: FontWeight.w700,
                          color: kBText,
                          letterSpacing: -1,
                          height: 1,
                          fontFeatures: _tabular)),
                  const SizedBox(height: 8),
                  Text('sur ${_fmtHm(b.durationMin)} · reste ${_fmtHm(remaining)}',
                      style: const TextStyle(
                          fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (origin.isNotEmpty)
                  Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: catColor, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(origin,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: kBText2)),
                    ),
                  ]),
                const SizedBox(height: 8),
                Text(b.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: tight ? 22 : 26,
                        fontWeight: FontWeight.w600,
                        color: kBText,
                        letterSpacing: -.3,
                        height: 1.15)),
                const SizedBox(height: 8),
                Text(
                  '${_clockOf(blockStartMin(b))} → ${_clockOf(endMin)}'
                  '${next != null ? ' · ensuite ${next.title} à ${_clockOf(blockStartMin(next))}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: kBText3),
                ),
                const SizedBox(height: 16),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _pillButton('Terminer le bloc', primary: true, onTap: () => _finishBlock(b)),
                  const SizedBox(width: 10),
                  _pillButton('Pause', onTap: _stopChrono),
                ]),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 22),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (steps != null) ...[
                  Expanded(flex: 13, child: _stepsPanel(steps)),
                  const SizedBox(width: 18),
                ],
                Expanded(flex: 10, child: _contextPanel(b, open)),
              ]),
              if (next != null) ...[
                const SizedBox(height: 18),
                _nextStrip(next),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 18),
        _dayGlance(),
        ]);
      }),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: kBPrimary.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: kBPrimary)),
      );

  Widget _panel({required String label, Widget? trailing, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: kBActive,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(child: _label(label)),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  /// Étapes du bloc : l'action visée (sous-action de tâche d'un projet, ou
  /// action propre d'une activité) et la sauvegarde qui va avec.
  ({TaskAction action, Future<void> Function() save})? _blockSteps(ScheduleBlock b) {
    final p = _project(b.projectId);
    if (p != null) {
      final r = resolveBlockAction(p, b);
      if (r != null) {
        return (action: r.action, save: () => widget.sync.patchActionOf(p, r.action));
      }
    }
    final act = _activityOf(b.activityId);
    if (act != null && b.actionId != null) {
      for (final own in act.ownActions) {
        if (own.id == b.actionId) {
          return (action: own, save: () => widget.sync.updateOwnActions(act.id, act.ownActions));
        }
      }
    }
    return null;
  }

  Widget _stepsPanel(({TaskAction action, Future<void> Function() save}) steps) {
    final a = steps.action;
    return _panel(label: 'DÉROULÉ DU BLOC', trailing: checklistBadge(a), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: a.done ? kBPrimaryDark : kBText3),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: a.done ? kBText3 : kBText,
                  decoration: a.done ? TextDecoration.lineThrough : null,
                  decorationColor: kBText3)),
        ),
      ]),
      const SizedBox(height: 10),
      if (a.checklist.isNotEmpty)
        ChecklistEditor(
          items: a.checklist,
          dense: true,
          onToggle: (c, v) => _toggleStep(steps, c, v),
          onAdd: (title) => _addStep(steps, title),
        )
      else
        const Text('Pas d\'étapes pour ce bloc.',
            style: TextStyle(fontSize: 12.5, color: kBText3)),
    ]);
  }

  Future<void> _toggleStep(
      ({TaskAction action, Future<void> Function() save}) steps, ChecklistItem c, bool v) async {
    final a = steps.action;
    final changed = setChecklistItem(a, c.id, v);
    setState(() {});
    await steps.save();
    if (!changed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _addStep(
      ({TaskAction action, Future<void> Function() save}) steps, String title) async {
    if (addChecklistItem(steps.action, title) == null) return;
    setState(() {});
    await steps.save();
  }

  Widget _contextPanel(ScheduleBlock b, Session open) {
    final act = _activityOf(open.activityId);
    final day0 = _livedToday;
    final day1 = day0.add(const Duration(days: 1));
    final monday = day0.subtract(Duration(days: day0.weekday - 1));
    final todayMin = _minutesOn(open.activityId, day0, day1);
    final weekMin = _minutesOn(open.activityId, monday, day1);
    final goal = act != null && act.goalMin > 1 ? act.goalMin : null;
    final last = _lastSessionBefore(b, open);
    final project = _project(b.projectId);
    final docs = project == null
        ? const <Map<String, dynamic>>[]
        : focusDocuments(widget.documentsByProject[project.id] ?? const [], b.taskId ?? '');
    final name = act?.name ?? 'Chrono';

    return _panel(label: 'CONTEXTE', children: [
      _kvRow('$name aujourd\'hui',
          goal != null ? '${_fmtHm(todayMin)} / ${_fmtHm(goal)}' : _fmtHm(todayMin)),
      if (goal != null) ...[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
                value: (todayMin / goal).clamp(0.0, 1.0),
                backgroundColor: kBRaised,
                color: kBPrimaryDark),
          ),
        ),
      ],
      const SizedBox(height: 10),
      _kvRow('Cette semaine', _fmtHm(weekMin)),
      const SizedBox(height: 10),
      _kvRow(
          'Dernière fois',
          last == null
              ? 'première fois'
              : '${_dayLabel(last.startAt)} · ${_fmtHm(last.duration.inMinutes)}'),
      if (docs.isNotEmpty) ...[
        const SizedBox(height: 14),
        _label('DOCUMENTS'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in docs) _docChip(d, docs, project!.title),
        ]),
      ],
    ]);
  }

  Widget _kvRow(String k, String v) => Row(children: [
        Expanded(
          child: Text(k,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: kBText3)),
        ),
        const SizedBox(width: 12),
        Text(v,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kBText,
                fontFeatures: _tabular)),
      ]);

  Widget _docChip(Map<String, dynamic> d, List<Map<String, dynamic>> all, String projectTitle) {
    final title = (d['title'] as String?) ?? 'Document';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => DocumentViewerDialog(
          projectTitle: projectTitle,
          documents: [d, ...all.where((x) => x != d)],
          sync: widget.sync,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: kBRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kBLine),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.description_outlined, size: 14, color: kBText3),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: kBText2)),
          ),
        ]),
      ),
    );
  }

  Widget _nextStrip(ScheduleBlock next) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBLine),
        ),
        child: Row(children: [
          const Text('Ensuite', style: TextStyle(fontSize: 13, color: kBText3)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(next.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: kBText)),
          ),
          const SizedBox(width: 12),
          Text('${_clockOf(blockStartMin(next))} · ${_fmtHm(next.durationMin)}',
              style: const TextStyle(
                  fontSize: 13, color: kBText3, fontFeatures: _tabular)),
        ]),
      );

  /// Minutes loguées sur une activité dans [start, end), session ouverte comprise.
  int _minutesOn(String activityId, DateTime start, DateTime end) {
    final now = DateTime.now();
    var sum = Duration.zero;
    for (final s in _sessions) {
      if (s.activityId != activityId) continue;
      final e = s.endAt ?? now;
      if (s.startAt.isBefore(end) && e.isAfter(start)) {
        final st = s.startAt.isBefore(start) ? start : s.startAt;
        final en = e.isAfter(end) ? end : e;
        if (en.isAfter(st)) sum += en.difference(st);
      }
    }
    return sum.inMinutes;
  }

  /// Dernière session TERMINÉE sur la même source que le bloc (sa tâche, sinon
  /// l'activité du chrono), hors la session en cours.
  Session? _lastSessionBefore(ScheduleBlock b, Session open) {
    Session? best;
    for (final s in _sessions) {
      if (s.endAt == null || s.id == open.id) continue;
      final match = b.taskId != null ? s.taskId == b.taskId : s.activityId == open.activityId;
      if (!match) continue;
      if (best == null || s.startAt.isAfter(best.startAt)) best = s;
    }
    return best;
  }

  String _dayLabel(DateTime d) {
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    final today = _livedToday;
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'aujourd\'hui';
    if (diff == 1) return 'hier';
    if (diff < 7) return days[d.weekday - 1];
    return _ddmm(d);
  }

  // ── PROGRAMME DU JOUR : liste compacte (disposition active) ─────────────────

  /// Liste centrée sur maintenant : la matinée repliée en une ligne, les trois
  /// derniers blocs passés, le bloc en cours avec sa progression, la suite.
  Widget _scheduleListCard() {
    final cur = currentBlockAt(_blocks, _nowMin);
    final pivot = cur != null ? blockStartMin(cur) : _nowMin;
    final before = <ScheduleBlock>[];
    final after = <ScheduleBlock>[];
    for (final b in _blocks) {
      if (cur != null && b.id == cur.id) continue;
      (blockStartMin(b) < pivot ? before : after).add(b);
    }
    final shown = before.length > 3 ? before.sublist(before.length - 3) : before;
    final folded = before.take(before.length - shown.length).toList();
    final foldedDone = folded.where((b) => b.status == 'done').length;
    final foldedMin = folded.fold<int>(0, (s, b) => s + b.durationMin);

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label('PROGRAMME DU JOUR')),
          if (asideLabel(asideBlocks(_allBlocks)) != null) ...[
            _asideLink(),
            const SizedBox(width: 14),
          ],
          if (_editing) ...[
            _textLink('+ Ajouter un bloc', _addBlock),
            const SizedBox(width: 14),
          ],
          _textLink('Demain', _openTomorrow),
          const SizedBox(width: 14),
          _textLink(_editing ? 'Terminé' : 'Modifier',
              () => setState(() => _editing = !_editing)),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: _blocks.isEmpty
              ? const Center(
                  child: Text('Aucun programme.',
                      style: TextStyle(fontSize: 13, color: kBText3)))
              : ListView(children: [
                  if (folded.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                      child: Text(
                        '$foldedDone bloc${foldedDone > 1 ? 's' : ''} fait${foldedDone > 1 ? 's' : ''}'
                        ' sur ${folded.length} plus tôt · ${_fmtHm(foldedMin)}',
                        style: const TextStyle(
                            fontSize: 12, color: kBText4, fontFeatures: _tabular),
                      ),
                    ),
                  for (final b in shown) _listRow(b, current: false),
                  if (cur != null) _listRow(cur, current: true),
                  for (final b in after) _listRow(b, current: false),
                ]),
        ),
      ]),
    );
  }

  Widget _listRow(ScheduleBlock b, {required bool current}) {
    final color = _kCategoryColor[b.category] ?? const Color(0xFF8E9AAF);
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    final project = _project(b.projectId);
    final trailing = current
        ? 'reste ${_fmtHm(math.max(0, blockEndMin(b) - _nowMin))}'
        : skipped
            ? 'passé'
            : fmtMin(b.durationMin);
    final frac = current ? ((_nowMin - blockStartMin(b)) / b.durationMin).clamp(0.0, 1.0) : 0.0;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current ? kBActive : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: current ? BorderSide(color: kBPrimary.withOpacity(.45)) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _blockTap(b, project),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SizedBox(
                  width: 44,
                  child: Text(b.startTime,
                      style: const TextStyle(
                          fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _toggleDone(b),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16, color: done ? kBPrimaryDark : color.withOpacity(.8)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                              color: done || skipped ? kBText3 : kBText,
                              decoration: done || skipped ? TextDecoration.lineThrough : null,
                              decorationColor: kBText3)),
                    ),
                    if (done)
                      if (webModeChip(_moodMarks, b.doneAt, widget.dayStartMin) case final chip?) chip,
                  ]),
                ),
                const SizedBox(width: 8),
                Text(trailing,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                        color: current ? kBPrimary : kBText3,
                        fontFeatures: _tabular)),
              ]),
              if (current) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                        value: frac, backgroundColor: kBRaised, color: kBPrimary),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    if (_detailId != b.id) return row;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row,
      Padding(padding: const EdgeInsets.only(bottom: 8), child: _detailCard(b)),
    ]);
  }

  Widget _dayGlance() {
    final entries = minutesByCategory(_blocks);
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBLine))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('LA JOURNÉE EN UN COUP D\'ŒIL'),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const Text('Rien de planifié.', style: TextStyle(fontSize: 12.5, color: kBText3))
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: entries[i].min,
                    child: Container(color: _kCategoryColor[entries[i].category]),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final e in entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: _kCategoryColor[e.category],
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 6),
                Text('${_kCategoryLabel[e.category]} · ${_fmtHm(e.min)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: kBText2, fontFeatures: _tabular)),
              ]),
          ]),
        ],
      ]),
    );
  }

  // ── PROGRAMME DU JOUR : frise horaire ───────────────────────────────────────

  /// Zoome la frise de [factor] en gardant la minute sous [anchorY] (position
  /// dans la zone visible ; null = milieu) au même endroit.
  void _zoomBy(double factor, {double? anchorY}) {
    final next = (_zoom * factor).clamp(_kZoomMin, _kZoomMax);
    if (next == _zoom) return;
    final ctrl = _timelineCtrl;
    if (ctrl.hasClients) {
      final ay = anchorY ?? ctrl.position.viewportDimension / 2;
      final minute = (ctrl.offset + ay - 4) / _tlPpm + _tlStartMin;
      final newPpm = _tlPpm * next / _zoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !ctrl.hasClients) return;
        final target = (minute - _tlStartMin) * newPpm + 4 - ay;
        ctrl.jumpTo(target.clamp(0.0, ctrl.position.maxScrollExtent));
      });
    }
    setState(() => _zoom = next);
    SharedPreferences.getInstance().then((p) => p.setDouble(_kZoomKey, next)).catchError((_) => false);
  }

  void _onTimelineSignal(PointerSignalEvent e) {
    if (e is PointerScaleEvent) {
      _zoomBy(e.scale, anchorY: e.localPosition.dy);
      return;
    }
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final dy = (ev as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      _zoomBy(dy < 0 ? 1.15 : 1 / 1.15, anchorY: ev.localPosition.dy);
    });
  }

  Widget _zoomControls() {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          color: kBText2,
          disabledColor: kBText4,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_rounded, 'Dézoomer (Ctrl / ⌘ + molette)',
          _zoom > _kZoomMin ? () => _zoomBy(1 / 1.4) : null),
      if (_zoom > _kZoomMin)
        Tooltip(
          message: 'Revenir à la journée entière',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _zoomBy(_kZoomMin / _zoom),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('×${_zoom.toStringAsFixed(_zoom < 10 ? 1 : 0)}',
                  style: const TextStyle(fontSize: 11.5, color: kBText3, fontFeatures: _tabular)),
            ),
          ),
        ),
      btn(Icons.add_rounded, 'Zoomer (Ctrl / ⌘ + molette)',
          _zoom < _kZoomMax ? () => _zoomBy(1.4) : null),
    ]);
  }

  // ── Glisser-déposer dans la frise ──────────────────────────────────────────
  // Un miroir Google Agenda se déplace dans l'agenda, pas ici.
  bool _canDrag(ScheduleBlock b) => b.gcalEventId == null && _detailId == null;

  int _dragDelta(double ppm) => ((_dragDy / ppm) / _kDragSnap).round() * _kDragSnap;

  int _dragStart(ScheduleBlock b, double ppm) {
    final base = blockStartMin(b);
    if (_dragId != b.id || _dragResize) return base;
    return (base + _dragDelta(ppm)).clamp(0, 24 * 60 - b.durationMin).toInt();
  }

  int _dragDuration(ScheduleBlock b, double ppm) {
    if (_dragId != b.id || !_dragResize) return b.durationMin;
    return (b.durationMin + _dragDelta(ppm)).clamp(_kDragSnap, 24 * 60 - blockStartMin(b)).toInt();
  }

  void _dragBegin(ScheduleBlock b, {required bool resize}) => setState(() {
        _dragId = b.id;
        _dragDy = 0;
        _dragResize = resize;
        _hoverMin = null;
      });

  Future<void> _dragCommit(ScheduleBlock b, double ppm) async {
    final start = _dragStart(b, ppm), dur = _dragDuration(b, ppm);
    final resize = _dragResize;
    setState(() => _dragId = null);
    final oldStart = b.startTime, oldDur = b.durationMin;
    if (start == blockStartMin(b) && dur == oldDur) return;
    final date = _cardDate;
    setState(() {
      b.startTime = '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}';
      b.durationMin = dur;
    });
    await widget.sync.upsertScheduleBlock(date, b);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text(resize
            ? '« ${b.title} » : ${fmtMin(dur)}, fin ${_clockOf(start + dur)}'
            : '« ${b.title} » déplacé à ${_clockOf(start)}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            setState(() {
              b.startTime = oldStart;
              b.durationMin = oldDur;
            });
            await widget.sync.upsertScheduleBlock(date, b);
          },
        ),
      ));
  }

  /// « + » au survol d'un bloc : nouveau bloc à la même heure et de même
  /// durée, posé côte à côte (`overlapColumns`).
  Widget _parallelAddButton(ScheduleBlock b) => Tooltip(
        message: 'Ajouter un bloc en parallèle',
        child: Material(
          color: kBPrimary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _addBlock(at: blockStartMin(b), duration: b.durationMin),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.add_rounded, size: 16, color: kBBg),
            ),
          ),
        ),
      );

  Widget _daySwitch() {
    Widget seg(String label, bool on, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: on ? kBActive : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? kBPrimary.withOpacity(.45) : Colors.transparent),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    color: on ? kBText : kBText3)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: kBLine),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('AUJOURD\'HUI', !_tomorrow, () => _setTomorrow(false)),
        seg('DEMAIN', _tomorrow, () => _setTomorrow(true)),
      ]),
    );
  }

  Widget _timelineCard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _daySwitch(),
          const SizedBox(width: 10),
          _zoomControls(),
          const Spacer(),
          if (!_tomorrow && asideLabel(asideBlocks(_allBlocks)) != null) ...[
            _asideLink(),
            const SizedBox(width: 14),
          ],
          if (_editing) ...[
            _textLink('+ Ajouter un bloc', _addBlock),
            const SizedBox(width: 14),
          ],
          if (_tomorrow) ...[
            _textLink('Préparer avec Claude', _askClaudeTomorrow),
            const SizedBox(width: 14),
          ],
          _textLink(_editing ? 'Terminé' : 'Modifier',
              () => setState(() => _editing = !_editing)),
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: _cardBlocks.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _tomorrow
                          ? 'Rien de prévu demain — ajoute des blocs ou prépare la journée avec Claude.'
                          : 'Aucun programme — demande à Claude de planifier ta journée.',
                      style: const TextStyle(fontSize: 13, color: kBText3),
                    ),
                    const SizedBox(height: 12),
                    _pillButton('Ajouter un bloc', onTap: _addBlock),
                  ]),
                )
              : LayoutBuilder(builder: (ctx, box) => _timeline(box.maxHeight, box.maxWidth)),
        ),
      ]),
    );
  }

  Widget _timeline(double height, double width) {
    final blocks = _cardBlocks;
    final ref = _tomorrow
        ? (blocks.isEmpty ? 8 * 60 : blockStartMin(blocks.first))
        : _nowMin;
    final (:startH, :endH) = timelineHours(blocks, ref);
    final range = (endH - startH) * 60;
    // Échelle : remplit la hauteur dispo, mais jamais sous 0,75 px/min (un
    // bloc de 30 min doit rester lisible) — au-delà, la frise défile.
    // Zoom vertical : multiplie l'échelle (jamais en dessous de la journée
    // entière).
    final ppm = timelinePxPerMin(height - 8, range) * _zoom;
    final total = range * ppm + 8;
    _tlPpm = ppm;
    _tlStartMin = startH * 60.0;

    double y(int min) => (min - startH * 60) * ppm + 4;
    // Assez zoomé : repères à la demi-heure (et au quart d'heure).
    final step = ppm * 15 >= 28 ? 15 : (ppm * 30 >= 36 ? 30 : 60);

    final now = _nowMin;
    final showNow = !_tomorrow && now >= startH * 60 && now <= endH * 60;

    final lanes = overlapColumns(blocks);
    final laneW = math.max(0.0, width - 56);
    // Créneau (quart d'heure) sous le pointeur, pour ajouter un bloc au clic.
    int slotAt(double dy) =>
        ((((dy - 4) / ppm + startH * 60) ~/ 15) * 15).clamp(startH * 60, endH * 60 - 15).toInt();
    final hover = _detailId == null ? _hoverMin : null;
    final stack = SizedBox(
      height: total,
      child: Stack(clipBehavior: Clip.none, children: [
        // Fond cliquable : un clic sur un créneau vide crée un bloc à cette
        // heure (sauf juste après avoir refermé un bloc ouvert).
        Positioned.fill(
          left: 56,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (e) {
              final m = slotAt(e.localPosition.dy);
              if (m != _hoverMin) setState(() => _hoverMin = m);
            },
            onExit: (_) {
              if (_hoverMin != null) setState(() => _hoverMin = null);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (e) {
                final closed = _closedAt != null &&
                    DateTime.now().difference(_closedAt!) < const Duration(milliseconds: 800);
                if (closed || _detailId != null) return;
                _addBlock(at: slotAt(e.localPosition.dy));
              },
            ),
          ),
        ),
        if (hover != null)
          Positioned(
            left: 56,
            right: 0,
            top: y(hover) + 1,
            height: math.max(30 * ppm - 3, 20),
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: kBPrimary.withOpacity(.06),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: kBPrimary.withOpacity(.35)),
                ),
                child: Text('+ ${_clockOf(hover)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: kBPrimary,
                        fontFeatures: _tabular)),
              ),
            ),
          ),
        for (var h = startH; h <= endH; h++) ...[
          Positioned(
            left: 0,
            top: y(h * 60) - 7,
            child: Text('${h.toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                    fontSize: 11.5, color: kBText4, fontFeatures: _tabular)),
          ),
          Positioned(
            left: 56,
            right: 0,
            top: y(h * 60),
            child: Container(height: 1, color: const Color(0x0DFFFFFF)),
          ),
          if (step < 60 && h < endH)
            for (var m = step; m < 60; m += step) ...[
              Positioned(
                left: 8,
                top: y(h * 60 + m) - 6,
                child: Text(':${m.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 10, color: kBText4, fontFeatures: _tabular)),
              ),
              Positioned(
                left: 56,
                right: 0,
                top: y(h * 60 + m),
                child: Container(height: 1, color: const Color(0x07FFFFFF)),
              ),
            ],
        ],
        // Blocs qui se chevauchent : côte à côte.
        for (final b in blocks) ...[
          Positioned(
            left: 56 + laneW * (lanes[b.id]?.col ?? 0) / (lanes[b.id]?.cols ?? 1),
            width: laneW / (lanes[b.id]?.cols ?? 1) - ((lanes[b.id]?.cols ?? 1) > 1 ? 4 : 0),
            top: y(_dragStart(b, ppm)) + 1,
            // Un bloc qui passe minuit s'arrête au bord de la frise (pile non
            // rognée : il déborderait sous ce qui suit).
            height: math.max(
                math.min(_dragDuration(b, ppm), 24 * 60 - _dragStart(b, ppm)) * ppm - 3, 20),
            child: MouseRegion(
              cursor: _canDrag(b) ? SystemMouseCursors.grab : MouseCursor.defer,
              onEnter: (_) => setState(() => _hoverBlockId = b.id),
              onExit: (_) {
                if (_hoverBlockId == b.id) setState(() => _hoverBlockId = null);
              },
              child: Stack(fit: StackFit.expand, children: [
                GestureDetector(
                  onVerticalDragStart: _canDrag(b) ? (_) => _dragBegin(b, resize: false) : null,
                  onVerticalDragUpdate: _canDrag(b) ? (d) => setState(() => _dragDy += d.delta.dy) : null,
                  onVerticalDragEnd: _canDrag(b) ? (_) => _dragCommit(b, ppm) : null,
                  onVerticalDragCancel: _canDrag(b) ? () => setState(() => _dragId = null) : null,
                  child: _timelineBlock(b, _dragDuration(b, ppm) * ppm - 3),
                ),
                // Bord bas : tirer pour changer la durée.
                if (_canDrag(b))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 7,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeRow,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => _dragBegin(b, resize: true),
                        onVerticalDragUpdate: (d) => setState(() => _dragDy += d.delta.dy),
                        onVerticalDragEnd: (_) => _dragCommit(b, ppm),
                        onVerticalDragCancel: () => setState(() => _dragId = null),
                      ),
                    ),
                  ),
                if (_dragId == null && _hoverBlockId == b.id && !_editing && _detailId == null)
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: b.durationMin * ppm > 60 ? Alignment.topRight : Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(top: b.durationMin * ppm > 60 ? 6 : 0),
                        child: _parallelAddButton(b),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          // Pendant le glisser : heures d'arrivée au-dessus du bloc.
          if (_dragId == b.id)
            Positioned(
              left: 56 + laneW * (lanes[b.id]?.col ?? 0) / (lanes[b.id]?.cols ?? 1),
              top: math.max(0.0, y(_dragStart(b, ppm)) - 20),
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: kBPrimary, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      '${_clockOf(_dragStart(b, ppm))} → ${_clockOf(_dragStart(b, ppm) + _dragDuration(b, ppm))}'
                      ' · ${fmtMin(_dragDuration(b, ppm))}',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: kBBg, fontFeatures: _tabular)),
                ),
              ),
            ),
        ],
        if (showNow)
          Positioned(
            left: 48,
            right: 0,
            top: y(now) - 4.5,
            child: IgnorePointer(
              child: Row(children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        const BoxDecoration(color: kBAlert, shape: BoxShape.circle)),
                Expanded(child: Container(height: 1.5, color: kBAlert)),
              ]),
            ),
          ),
        // Bloc ouvert sur place : son contenu par-dessus la frise.
        for (final b in blocks.where((b) => b.id == _detailId))
          Positioned(
            left: 56,
            right: 0,
            top: math.max(0.0, math.min(y(blockStartMin(b)), total - 440)),
            child: _detailCard(b),
          ),
      ]),
    );
    if (_timelineHidden) {
      _timelineHidden = false;
      _scrollNowPending = true;
    }
    if (_scrollNowPending) {
      _scrollNowPending = false;
      if (showNow) {
        final nowY = y(now);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_timelineCtrl.hasClients) return;
          final pos = _timelineCtrl.position;
          final target =
              (nowY - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent);
          _timelineCtrl.animateTo(target,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
        });
      }
    }
    return Listener(
      onPointerSignal: _onTimelineSignal,
      child: SingleChildScrollView(controller: _timelineCtrl, child: stack),
    );
  }

  /// Action visée par le bloc en cours + sa checklist cochable (micro-actions
  /// pour avancer pendant le créneau). Vide si le bloc ne vise aucune action.
  List<Widget> _nowChecklist(ScheduleBlock b) {
    final p = _project(b.projectId);
    final r = resolveBlockAction(p, b);
    if (p == null || r == null) return const [];
    final a = r.action;
    final badge = checklistBadge(a);
    return [
      const SizedBox(height: 14),
      Container(
        constraints: const BoxConstraints(maxHeight: 190),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14, color: a.done ? kBPrimaryDark : kBText3),
            const SizedBox(width: 6),
            Expanded(
              child: Text(a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: a.done ? kBText3 : kBText2,
                      decoration: a.done ? TextDecoration.lineThrough : null,
                      decorationColor: kBText3)),
            ),
            if (badge != null) ...[const SizedBox(width: 8), badge],
          ]),
          if (a.checklist.isNotEmpty) ...[
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: ChecklistEditor(
                  items: a.checklist,
                  dense: true,
                  onToggle: (c, v) => _toggleBlockChecklist(p, a, c, v),
                ),
              ),
            ),
          ],
        ]),
      ),
    ];
  }

  Widget _timelineBlock(ScheduleBlock b, double h) {
    final color = _kCategoryColor[b.category] ?? const Color(0xFF8E9AAF);
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    final now = _nowMin;
    final current = !_tomorrow &&
        !done &&
        !skipped &&
        blockStartMin(b) <= now &&
        now < blockStartMin(b) + b.durationMin;
    final compact = h < 40;
    final project = _project(b.projectId);

    final check = InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _tomorrow ? null : () => _toggleDone(b),
      child: Tooltip(
        message: _tomorrow ? 'Demain' : (done ? 'Annuler' : 'Marquer comme fait'),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: compact ? 15 : 17,
            color: done ? kBPrimaryDark : color.withOpacity(.8),
          ),
        ),
      ),
    );

    final titleStyle = TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
      color: done || skipped ? kBText3 : kBText,
      decoration: done || skipped ? TextDecoration.lineThrough : null,
      decorationColor: kBText3,
    );
    final target = project == null ? null : resolveBlockAction(project, b)?.action;
    final progress = target != null && target.checklist.isNotEmpty && !done
        ? ' · ${target.checklistDone}/${target.checklistTotal}'
        : '';
    final modeChip = done && !compact ? webModeChip(_moodMarks, b.doneAt, widget.dayStartMin) : null;
    final trailing = Row(mainAxisSize: MainAxisSize.min, children: [
      if (modeChip != null) modeChip,
      Text(
        (current ? 'en cours' : fmtMin(b.durationMin)) + progress,
        style: TextStyle(
          fontSize: 12,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
          color: current ? kBPrimary : kBText3,
          fontFeatures: _tabular,
        ),
      ),
    ]);

    return Material(
      color: current ? kBActive : color.withOpacity(done ? .07 : .13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 7 : 9),
        side: current
            ? BorderSide(color: kBPrimary.withOpacity(.45))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Bloc à contenu → ouvert sur place (étapes cochables) ; projet sans
        // contenu → la fiche projet ; autre bloc (ou mode « Modifier ») → éditeur.
        onTap: _blockTap(b, project),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 0 : 8),
          child: compact
              ? Row(children: [
                  check,
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(b.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle)),
                  trailing,
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  check,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.title,
                            maxLines: h > 70 ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle),
                        if (h > 56)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '${b.startTime} → ${_clockOf(blockStartMin(b) + b.durationMin)}'
                              '${project != null ? ' · ${project.title}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: kBText3, fontFeatures: _tabular),
                            ),
                          ),
                        // Le concret du bloc : prochaine étape / action visée.
                        if (h > 84 && !done && !skipped && _blockHint(b, forTomorrow: _tomorrow) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _blockHint(b, forTomorrow: _tomorrow)!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: kBText2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ]),
        ),
      ),
    );
  }

  // ── BLOC OUVERT SUR PLACE ──────────────────────────────────────────────────
  // Clic sur un bloc de la frise (ou de la liste) : ce qu'il donne à faire
  // s'affiche dans le programme, cochable, sans passer par la fiche projet.

  bool _hasDetail(ScheduleBlock b) =>
      _taskOf(b) != null ||
      _blockSteps(b) != null ||
      _ownActionsFor(b).isNotEmpty ||
      (!_tomorrow && _routineOf(b) != null);

  VoidCallback _blockTap(ScheduleBlock b, Project? project) {
    if (_editing) return () => _editBlock(b);
    if (_hasDetail(b)) {
      return () {
        final justClosed = _closedId == b.id &&
            _closedAt != null &&
            DateTime.now().difference(_closedAt!) < const Duration(milliseconds: 800);
        _closedId = null;
        if (justClosed) return;
        setState(() => _detailId = _detailId == b.id ? null : b.id);
      };
    }
    if (project != null) return () => widget.onOpenProject(project, taskId: b.taskId);
    return () => _editBlock(b);
  }

  Widget _detailCard(ScheduleBlock b) {
    final pt = _taskOf(b);
    final project = pt?.project ?? _project(b.projectId);
    // Clic ailleurs = fermer (la croix reste).
    return TapRegion(
      onTapOutside: (_) {
        if (_detailId != b.id) return;
        _closedId = b.id;
        _closedAt = DateTime.now();
        setState(() => _detailId = null);
      },
      child: _detailCardBody(b, pt, project),
    );
  }

  Widget _detailCardBody(
      ScheduleBlock b, ({Project project, ProjectTask task})? pt, Project? project) {
    return Material(
      color: kBRaised,
      elevation: 10,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: kBPrimary.withOpacity(.35)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text('${b.startTime} → ${_clockOf(blockEndMin(b))}',
                  style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(b.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kBText)),
              ),
              IconButton(
                tooltip: 'Fermer',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: kBText3,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _detailId = null),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (pt != null) ...[
                  Text('${pt.project.title} › ${pt.task.title}',
                      style: const TextStyle(fontSize: 12, color: kBText3)),
                  const SizedBox(height: 10),
                  ..._taskWork(pt.project, pt.task, b),
                ] else
                  _agendaContent(b),
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 6, children: [
                  if (project != null)
                    _textLink('Ouvrir le projet', () {
                      setState(() => _detailId = null);
                      widget.onOpenProject(project, taskId: b.taskId);
                    }),
                  _textLink('Modifier le bloc', () => _editBlock(b)),
                  if (!_tomorrow)
                    _textLink(b.status == 'done' ? 'Rouvrir le bloc' : 'Bloc terminé',
                        () => _toggleDone(b)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Action visée en avant (étapes cochables, ajout), autres actions ouvertes
  /// avec leurs étapes, nombre de faites — même découpage que l'écran bloc
  /// mobile (`blockWork`).
  List<Widget> _taskWork(Project p, ProjectTask t, ScheduleBlock b) {
    final w = blockWork(t, b.actionId);
    return [
      if (w.focus == null)
        const Text('Aucune action ouverte sur cette tâche.',
            style: TextStyle(fontSize: 12.5, color: kBText3))
      else
        _workAction(p, w.focus!, primary: true),
      for (final a in w.open) ...[const SizedBox(height: 10), _workAction(p, a)],
      if (w.done.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('${w.done.length} déjà faite${w.done.length > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 12, color: kBText4)),
      ],
    ];
  }

  Widget _workAction(Project p, TaskAction a, {bool primary = false}) {
    final steps = (action: a, save: () => widget.sync.patchActionOf(p, a));
    final badge = checklistBadge(a);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () async {
          setState(() => setActionDone(a, !a.done));
          await steps.save();
        },
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16, color: a.done ? kBPrimaryDark : (primary ? kBText2 : kBText3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a.title,
                style: TextStyle(
                    fontSize: primary ? 13.5 : 13,
                    fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
                    color: a.done ? kBText3 : (primary ? kBText : kBText2),
                    decoration: a.done ? TextDecoration.lineThrough : null,
                    decorationColor: kBText3)),
          ),
          if (a.estimatedMin != null) ...[
            const SizedBox(width: 8),
            Text(fmtMin(a.estimatedMin!), style: const TextStyle(fontSize: 11.5, color: kBText4)),
          ],
          if (badge != null) ...[const SizedBox(width: 8), badge],
        ]),
      ),
      if (a.checklist.isNotEmpty || primary)
        Padding(
          padding: const EdgeInsets.only(left: 18, top: 4),
          child: ChecklistEditor(
            items: a.checklist,
            dense: true,
            onToggle: (c, v) => _toggleStep(steps, c, v),
            onAdd: primary ? (title) => _addStep(steps, title) : null,
          ),
        ),
    ]);
  }

  // ── AU PROGRAMME · CONCRÈTEMENT ─────────────────────────────────────────────
  // Le contenu de chaque bloc à venir, faisable sur place : étapes de l'action
  // visée (cochables), actions possibles d'une activité, compteur de routine,
  // ou « définir la prochaine action » d'un projet.

  /// Actions propres ouvertes d'une activité-temps portée par le bloc (bloc
  /// d'activité sans action ciblée).
  List<TaskAction> _ownActionsFor(ScheduleBlock b) {
    if (b.actionId != null || b.projectId != null) return const [];
    final act = _activityOf(b.activityId);
    if (act == null || act.isHabit) return const [];
    return act.ownActions.where((a) => !a.done).toList();
  }

  Activity? _routineOf(ScheduleBlock b) {
    final act = _activityOf(b.activityId);
    return act != null && act.isHabit ? act : null;
  }

  /// Une ligne « concrète » pour un bloc (frise et carte repliée), ou null.
  String? _blockHint(ScheduleBlock b, {bool forTomorrow = false}) {
    final steps = _blockSteps(b);
    if (steps != null) {
      final a = steps.action;
      final next = nextChecklistItem(a);
      final count = a.checklist.isEmpty ? '' : ' · ${a.checklistDone}/${a.checklistTotal}';
      return next != null && !a.done ? '→ ${next.title}$count' : '→ ${a.title}$count';
    }
    final own = _ownActionsFor(b);
    if (own.isNotEmpty) {
      return own.length == 1
          ? '→ ${own.first.title}'
          : '${own.length} actions possibles · ${own.first.title}…';
    }
    final routine = _routineOf(b);
    if (routine != null) {
      if (forTomorrow) return null;
      final r = routinesForToday([routine], _hits, DateTime.now(), dayStartMin: widget.dayStartMin).firstOrNull;
      return r == null ? null : 'Routine · ${r.progressLabel}';
    }
    if (_project(b.projectId) != null) return 'Aucune action définie';
    return null;
  }

  bool _hasContent(ScheduleBlock b) =>
      _blockSteps(b) != null ||
      _ownActionsFor(b).isNotEmpty ||
      _routineOf(b) != null ||
      _project(b.projectId) != null;

  Widget _agendaCard() {
    final now = _nowMin;
    final upcoming = _blocks
        .where((b) => b.status == 'pending' && blockStartMin(b) + b.durationMin > now)
        .toList();
    final open = _agendaOpen ??
        {for (final b in upcoming.where(_hasContent).take(1)) b.id};
    const cap = 6;
    final shown = _agendaAll ? upcoming : upcoming.take(cap).toList();
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('AU PROGRAMME · CONCRÈTEMENT'),
        const SizedBox(height: 10),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _blocks.isEmpty ? 'Pas de programme aujourd\'hui.' : 'Plus rien de prévu aujourd\'hui.',
              style: const TextStyle(fontSize: 13, color: kBText3),
            ),
          )
        else
          for (final b in shown) _agendaItem(b, open: open.contains(b.id), openSet: open),
        if (upcoming.length > cap)
          Align(
            alignment: Alignment.centerLeft,
            child: _textLink(
                _agendaAll ? 'Réduire' : 'Voir les ${upcoming.length - cap} autres blocs',
                () => setState(() => _agendaAll = !_agendaAll)),
          ),
      ]),
    );
  }

  Widget _agendaItem(ScheduleBlock b, {required bool open, required Set<String> openSet}) {
    final color = _kCategoryColor[b.category] ?? const Color(0xFF8E9AAF);
    final now = _nowMin;
    final current = blockStartMin(b) <= now && now < blockStartMin(b) + b.durationMin;
    final hasContent = _hasContent(b);
    final hint = _blockHint(b);
    final session = _openSession;
    final chronoOnIt = session != null && _sessionOnBlock(session, b);
    final canChrono =
        (b.activityId ?? _project(b.projectId)?.linkedActivityId) != null && !chronoOnIt;
    void toggleOpen() => setState(() {
          final next = Set<String>.of(openSet);
          next.contains(b.id) ? next.remove(b.id) : next.add(b.id);
          _agendaOpen = next;
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: current ? kBActive : color.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: current ? kBPrimary.withOpacity(.4) : kBLine),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: hasContent ? toggleOpen : () => _editBlock(b),
          borderRadius: BorderRadius.circular(8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _toggleDone(b),
              child: Tooltip(
                message: 'Marquer le bloc comme fait',
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.radio_button_unchecked, size: 17, color: color.withOpacity(.85)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(b.startTime,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: current ? kBPrimary : kBText3,
                            fontFeatures: _tabular)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                              color: kBText)),
                    ),
                  ]),
                  if (!open && hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: kBText3)),
                    ),
                ]),
              ),
            ),
            if (canChrono)
              IconButton(
                tooltip: 'Lancer le chrono sur ce bloc',
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                color: kBPrimary,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => _startChrono(b),
              ),
            if (hasContent)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2),
                child: Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: kBText4),
              ),
          ]),
        ),
        if (open && hasContent)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 6, 4, 4),
            child: _agendaContent(b),
          ),
      ]),
    );
  }

  Widget _agendaContent(ScheduleBlock b) {
    final steps = _blockSteps(b);
    if (steps != null) {
      final a = steps.action;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            setState(() => setActionDone(a, !a.done));
            await steps.save();
          },
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16, color: a.done ? kBPrimaryDark : kBText3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(a.title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: a.done ? kBText3 : kBText,
                      decoration: a.done ? TextDecoration.lineThrough : null,
                      decorationColor: kBText3)),
            ),
            if (checklistBadge(a) != null) checklistBadge(a)!,
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ChecklistEditor(
            items: a.checklist,
            dense: true,
            onToggle: (c, v) => _toggleStep(steps, c, v),
            onAdd: (title) => _addStep(steps, title),
          ),
        ),
      ]);
    }
    final own = _ownActionsFor(b);
    if (own.isNotEmpty) {
      final act = _activityOf(b.activityId)!;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Possible dans ce bloc',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kBText4, letterSpacing: .4)),
        const SizedBox(height: 4),
        for (final a in own.take(5))
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              setState(() => setActionDone(a, true));
              await widget.sync.updateOwnActions(act.id, act.ownActions);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
                content: Text('Action faite : ${a.title}'),
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Annuler',
                  onPressed: () async {
                    setState(() => setActionDone(a, false));
                    await widget.sync.updateOwnActions(act.id, act.ownActions);
                  },
                ),
              ));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.radio_button_unchecked, size: 15, color: kBText3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: kBText)),
                ),
                if (a.checklist.isNotEmpty) checklistBadge(a)!,
              ]),
            ),
          ),
        if (own.length > 5)
          Text('+ ${own.length - 5} autres', style: const TextStyle(fontSize: 12, color: kBText4)),
      ]);
    }
    final routine = _routineOf(b);
    if (routine != null) {
      final r = routinesForToday([routine], _hits, DateTime.now(), dayStartMin: widget.dayStartMin).firstOrNull;
      return Row(children: [
        Expanded(
          child: Text(r?.progressLabel ?? routine.name,
              style: const TextStyle(fontSize: 13, color: kBText2, fontFeatures: _tabular)),
        ),
        _pillButton('+1', height: 32, onTap: () => _incRoutine(routine)),
      ]);
    }
    final project = _project(b.projectId);
    if (project != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _textLink('Définir la prochaine action',
            () => widget.onOpenProject(project, taskId: b.taskId)),
      );
    }
    return const SizedBox.shrink();
  }

  // ── ROUTINES DU JOUR ────────────────────────────────────────────────────────

  /// +1 sur une routine, persisté comme `_completeLinkedRoutine` ; annulable.
  void _incRoutine(Activity act) {
    final logic = _logic;
    if (logic == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chargement en cours, réessaie dans un instant.'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final today = _livedToday;
    void persist() {
      final key = yyyymmdd(today);
      for (final h in logic.state.habitProgress) {
        if (h.activityId == act.id && h.yyyymmdd == key) widget.sync.saveHabitProgress(h);
      }
    }
    logic.incHabit(act.id, 1, today);
    persist();
    if (logic.state.habitHits.isNotEmpty) widget.sync.saveHabitHit(logic.state.habitHits.last);
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text('+1 : ${act.name}'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          logic.incHabit(act.id, -1, today);
          persist();
        },
      ),
    ));
  }

  Widget _routinesCard() {
    final list = routinesForToday(widget.activities, _hits, DateTime.now(), dayStartMin: widget.dayStartMin);
    if (list.isEmpty) return const SizedBox.shrink();
    final reached = list.where((r) => r.reached).length;
    const cap = 5;
    final todo = list.where((r) => !r.reached).toList();
    final shown = _routinesAll ? list : todo.take(cap).toList();
    final hidden = list.length - shown.length;
    final folded = _isFolded('routines');
    return _card(
      padding: folded ? _kFoldedPadding : const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHeader('routines', Row(children: [
          Expanded(child: _label('ROUTINES DU JOUR')),
          Text('$reached / ${list.length} atteinte${reached > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
        ])),
        if (!folded) ...[
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Toutes les routines sont atteintes. Bravo.',
                style: TextStyle(fontSize: 13, color: kBText3)),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: domainColor(r.activity.domainId, widget.domains) ?? kBPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.activity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: r.reached ? kBText3 : kBText,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(r.progressLabel,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: r.reached ? kBPrimaryDark : kBText3,
                          fontFeatures: _tabular)),
                ]),
              ),
              if (r.reached)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle, size: 16, color: kBPrimaryDark),
                ),
              _pillButton('+1', height: 32, onTap: () => _incRoutine(r.activity)),
            ]),
          ),
        if (hidden > 0 || _routinesAll)
          Align(
            alignment: Alignment.centerLeft,
            child: _textLink(_routinesAll ? 'Réduire' : 'Voir toutes ($hidden de plus)',
                () => setState(() => _routinesAll = !_routinesAll)),
          ),
        ],
      ]),
    );
  }

  /// Colonne de droite : (contenu des blocs) + routines + semaine.
  bool _isFolded(String key) => _folded.contains(key);

  void _toggleFold(String key) {
    setState(() => _folded.contains(key) ? _folded.remove(key) : _folded.add(key));
    final list = _folded.toList();
    SharedPreferences.getInstance().then((p) => p.setStringList(_kFoldedKey, list)).catchError((_) => false);
  }

  /// En-tête d'un module repliable : toute la ligne replie / déplie (les
  /// liens qu'elle contient gardent leur action), chevron à droite.
  Widget _foldHeader(String key, Widget header) {
    final folded = _isFolded(key);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _toggleFold(key),
      child: Row(children: [
        Expanded(child: header),
        const SizedBox(width: 6),
        Tooltip(
          message: folded ? 'Déplier' : 'Replier',
          child: Icon(folded ? Icons.expand_more : Icons.expand_less, size: 18, color: kBText4),
        ),
      ]),
    );
  }

  static const _kFoldedPadding = EdgeInsets.fromLTRB(20, 14, 20, 14);

  Widget _sideColumn({bool withAgenda = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (withAgenda) ...[_agendaCard(), const SizedBox(height: 18)],
        _routinesCard(),
        const SizedBox(height: 18),
        WebBadgesCard(
          sync: widget.sync,
          activities: widget.activities,
          projects: widget.projects,
          objectives: widget.objectives,
          hits: _hits,
          sessions: _sessions,
          moodMarks: _moodMarks,
          chainRuns: _chainRuns,
          dayStartMin: widget.dayStartMin,
          folded: _isFolded('badges'),
          onToggleFold: () => _toggleFold('badges'),
          huntStore: _huntStore,
          todayBlocks: _allBlocks,
          source: _deckSource,
        ),
        const SizedBox(height: 18),
        WebObjectivesCard(
          objectives: widget.objectives,
          activities: widget.activities,
          sessions: _sessions,
          hits: _hits,
          blocks: _allBlocks,
          projects: widget.projects,
          dayStartMin: widget.dayStartMin,
          runningActivityId: _openSession?.activityId,
          folded: _isFolded('objectives'),
          onToggleFold: () => _toggleFold('objectives'),
          todayCount: (a) => _hits.where((h) => h.habitId == a.id && ymdOf(livedDate(h.ts, widget.dayStartMin)) == ymdOf(_livedToday)).length,
          onRoutinePlus: _incRoutine,
          onStartActivity: _startActivityChrono,
          onLaunchBlock: _startChrono,
          onOpenProject: widget.onOpenProject,
        ),
        const SizedBox(height: 18),
        if (_moodMarks.any((m) => m.kind == kMoodElan)) ...[
          _elanCard(),
          const SizedBox(height: 18),
        ],
        // Chronos du jour : voir, corriger, supprimer, rattacher à un bloc
        // après coup — l'équivalent de la feuille « Dernières 24 h » du mobile.
        SessionsCard(
          date: _today,
          sessions: _sessions,
          blocks: _allBlocks,
          activities: widget.activities,
          projects: widget.projects,
          domains: widget.domains,
          sync: widget.sync,
          onChanged: () {
            if (mounted) setState(() {});
          },
          folded: _isFolded('chronos'),
          onToggleFold: () => _toggleFold('chronos'),
        ),
        const SizedBox(height: 18),
        _weekColumn(),
      ]);

  /// « ÉLAN & DISCIPLINE » : les deux cartes de Stats mobile, sur les flux du web.
  Widget _elanCard() {
    final folded = _isFolded('elan');
    return _card(
      padding: folded ? _kFoldedPadding : const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHeader('elan', _label('ÉLAN & DISCIPLINE')),
        if (!folded)
          Theme(
            data: Theme.of(context).copyWith(cardTheme: const CardThemeData(color: kBBg, elevation: 0, margin: EdgeInsets.symmetric(vertical: 8))),
            child: ElanStatsCards(
              sync: widget.sync,
              marks: _moodMarks,
              hits: _hits,
              activities: widget.activities,
              dayStartMin: widget.dayStartMin,
            ),
          ),
      ]),
    );
  }

  /// « Ton élan, là ? » dans MAINTENANT (web) : une fois par créneau du jour
  /// vécu, quand un bloc est devant et qu'aucun chrono ne tourne.
  Widget? _elanRow(ScheduleBlock? b, Session? open) {
    if (b == null || open != null) return null;
    final now = DateTime.now();
    final ymd = livedProgramYmd(now, widget.dayStartMin);
    final bucket = elanBucket(livedNowMin(now, widget.dayStartMin));
    if (!elanPromptDue(_moodMarks, ymd, bucket, _elanSkipped)) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ElanRow(
        value: 0,
        context: 'avant ${b.title}',
        onPick: (v) {
          final m = MoodMark(at: now, ymd: ymd, kind: kMoodElan, value: v, moment: bucket, blockId: b.id, activityId: b.activityId, projectId: b.projectId, taskId: b.taskId, actionId: b.actionId);
          setState(() => _moodMarks = [..._moodMarks, m]);
          widget.sync.saveMoodMark(m);
        },
        onSkip: () => setState(() => _elanSkipped.add('$ymd:$bucket')),
        text: kBText,
        text2: kBText2,
        text3: kBText3,
        surface: kBRaised,
        raised: kBActive,
      ),
    );
  }

  // ── CETTE SEMAINE ───────────────────────────────────────────────────────────

  Widget _weekColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _overdueCard(),
      const SizedBox(height: 18),
      _engagementsCard(),
      const SizedBox(height: 18),
      _deadlinesCard(),
    ]);
  }

  Widget _overdueCard() {
    final today = _livedToday;
    final pairs = <({ProjectTask task, Project project})>[];
    for (final p in widget.projects) {
      if (p.status == 'archived' || p.paused) continue;
      for (final t in p.tasks) {
        if (t.endDate != null &&
            t.endDate!.isBefore(today) &&
            t.status != 'done' &&
            t.status != 'skipped') {
          pairs.add((task: t, project: p));
        }
      }
    }
    pairs.sort((a, b) => a.task.endDate!.compareTo(b.task.endDate!));
    final shown = pairs.take(5).toList();

    final folded = _isFolded('overdue');
    return _card(
      padding: folded ? _kFoldedPadding : const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHeader('overdue', Row(children: [
          Expanded(
            child: _label(pairs.isEmpty ? 'À TRAITER' : 'À TRAITER · ${pairs.length}',
                color: pairs.isEmpty ? kBText3 : kBAlert),
          ),
          if (pairs.isNotEmpty) _textLink('Replanifier', widget.onOpenWeek),
        ])),
        if (!folded) ...[
        const SizedBox(height: 12),
        if (pairs.isEmpty)
          const Text('Rien en retard.', style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final e in shown)
            _rowLink(
              title: e.task.title,
              subtitle: e.project.title,
              trailing: _ddmm(e.task.endDate!),
              trailingColor: kBAlert,
              onTap: () => widget.onOpenProject(e.project, taskId: e.task.id),
            ),
        if (pairs.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+ ${pairs.length - shown.length} autres',
                style: const TextStyle(fontSize: 12, color: kBText3)),
          ),
        ],
      ]),
    );
  }

  Widget _engagementsCard() {
    final stats = rollingWeekEngagements(activities: widget.activities, hits: _hits, onlyIds: engagedRoutineIds(widget.objectives));
    final byDomain = <String, ({int done, int target})>{};
    for (final e in stats) {
      final cur = byDomain[e.domainId] ?? (done: 0, target: 0);
      byDomain[e.domainId] =
          (done: cur.done + math.min(e.done, e.target), target: cur.target + e.target);
    }
    final domains = widget.domains.where((d) => !d.deleted && byDomain.containsKey(d.id));

    final folded = _isFolded('week');
    return _card(
      padding: folded ? _kFoldedPadding : const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHeader('week', _label('CETTE SEMAINE · 7 JOURS')),
        if (!folded) ...[
        const SizedBox(height: 12),
        if (domains.isEmpty)
          const Text('Aucun engagement hebdo pour l\'instant.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final d in domains)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 84,
                  child: Text(d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: kBText)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _bar(
                    byDomain[d.id]!.target == 0
                        ? 0
                        : byDomain[d.id]!.done / byDomain[d.id]!.target,
                    domainColor(d.id, widget.domains) ?? kBPrimary,
                    height: 6,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 52,
                  child: Text('${byDomain[d.id]!.done} / ${byDomain[d.id]!.target}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 12.5, color: kBText2, fontFeatures: _tabular)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _deadlinesCard() {
    final today = _livedToday;
    final upcoming = widget.projects
        .where((p) =>
            p.status == 'active' &&
            !p.paused &&
            p.endDate != null &&
            !p.endDate!.isBefore(today))
        .toList()
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    final shown = upcoming.take(3).toList();

    final folded = _isFolded('deadlines');
    return _card(
      padding: folded ? _kFoldedPadding : const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHeader('deadlines', Row(children: [
          Expanded(child: _label('PROCHAINES ÉCHÉANCES')),
          _textLink('Projets', widget.onOpenProjects),
        ])),
        if (!folded) ...[
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Text('Aucune échéance de projet.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final p in shown) _projectRow(p, today),
        ],
      ]),
    );
  }

  Widget _projectRow(Project p, DateTime today) {
    final total = p.tasks.where((t) => t.status != 'skipped').length;
    final done = p.tasks.where((t) => t.status == 'done').length;
    final soon = p.endDate!.difference(today).inDays <= 7;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => widget.onOpenProject(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: kBText)),
            ),
            Text(_ddmm(p.endDate!),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: soon ? FontWeight.w600 : FontWeight.w400,
                    color: soon ? kBAttention : kBText2,
                    fontFeatures: _tabular)),
          ]),
          const SizedBox(height: 6),
          _bar(total == 0 ? 0 : done / total, kBPrimary, height: 4),
          const SizedBox(height: 6),
          Text('$done / $total tâches',
              style: const TextStyle(fontSize: 11.5, color: kBText3, fontFeatures: _tabular)),
        ]),
      ),
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

  Widget _label(String text, {bool dot = false, Color color = kBText3}) =>
      Row(children: [
        if (dot) ...[
          Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: kBPrimary, shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        Text(text,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: color)),
      ]);

  Widget _bar(double v, Color color, {double height = 6}) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: height,
          child: Stack(children: [
            Container(color: kBRaised),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ]),
        ),
      );

  Widget _rowLink({
    required String title,
    required String subtitle,
    required String trailing,
    required Color trailingColor,
    required VoidCallback onTap,
  }) =>
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: kBText)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: kBText3)),
              ]),
            ),
            const SizedBox(width: 10),
            Text(trailing,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: trailingColor,
                    fontFeatures: _tabular)),
          ]),
        ),
      );

  /// B12 — « 2 déplacés · 1 sauté » : lien discret dans l'en-tête, clic =
  /// liste repliée (heure prévue, titre, destination ou cause).
  Widget _asideLink() {
    final a = asideBlocks(_allBlocks);
    return _textLink(asideLabel(a)!, () {
      final items = [...a.moved, ...a.cancelled, ...a.skipped]
        ..sort((x, y) => x.startTime.compareTo(y.startTime));
      showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: kBRaised,
          title: const Text('Hors du programme', style: TextStyle(color: kBText, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final b in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                        b.movedTo != null || b.skipReason == 'reporte'
                            ? Icons.redo_rounded
                            : isCancelledBlock(b)
                                ? Icons.event_busy_rounded
                                : Icons.skip_next_rounded,
                        size: 16, color: kBText3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${b.startTime} · ${b.title}',
                            style: const TextStyle(fontSize: 13.5, color: kBText)),
                        Text(asideDetail(b), style: const TextStyle(fontSize: 12, color: kBText3)),
                      ]),
                    ),
                    if (isCancelledBlock(b))
                      TextButton(
                        onPressed: () {
                          Navigator.pop(d);
                          widget.sync.setBlockCancelled(_today, b.id, false);
                        },
                        child: const Text('Rétablir'),
                      ),
                  ]),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer'))],
        ),
      );
    });
  }

  Widget _textLink(String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
        ),
      );

  Widget _pillButton(String label,
      {bool primary = false, double height = 46, required VoidCallback onTap}) {
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: primary ? kBPrimary : const Color(0x12FFFFFF),
          foregroundColor: primary ? kBBg : kBText,
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: height < 40 ? 14 : 20),
          textStyle: TextStyle(
              fontSize: height < 40 ? 13 : 14,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w600),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool running;
  _RingPainter(this.progress, {required this.running});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2;
    final track = Paint()
      ..color = kBRaised
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..color = running ? kBPrimary : kBPrimary.withOpacity(.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2,
        2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.running != running;
}
