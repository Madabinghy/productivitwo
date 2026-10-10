import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
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
import 'package:productivitwo_v1/web/theme_tokens.dart';

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
    _today = ymdOf(DateTime.now());
    _subscribe();
    _loadLogic();
    // Horloge : chrono, ligne « maintenant » et changement de jour.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final t = ymdOf(DateTime.now());
      if (t != _today) {
        _today = t;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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

  int get _nowMin {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

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
    await widget.sync.saveProjectTasks(p.id, p.tasks);
    if (!changed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _addBlockChecklist(Project p, TaskAction a, String title) async {
    if (addChecklistItem(a, title) == null) return;
    setState(() {});
    await widget.sync.saveProjectTasks(p.id, p.tasks);
  }

  Future<void> _toggleTaskAction(Project p, TaskAction a, bool done) async {
    setState(() {
      a.done = done;
      a.doneAt = done ? DateTime.now() : null;
    });
    await widget.sync.saveProjectTasks(p.id, p.tasks);
  }

  /// « Terminé » de la bande Focus : l'action est faite, le chrono s'arrête,
  /// le bloc d'origine passe à fait.
  Future<void> _finishFocus(FocusTarget t) async {
    if (!t.action.done) await _toggleTaskAction(t.project, t.action, true);
    final b = t.block;
    if (b != null) {
      await _finishBlock(b);
    } else {
      await _stopChrono();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Action faite : ${t.action.title}'),
      duration: const Duration(seconds: 2),
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
    final updated = await showScheduleBlockDialog(context, block: b);
    if (updated == null || !mounted) return;
    // Soft-delete : retiré de la frise tout de suite, le flux confirmera.
    final cancelled = isCancelledBlock(updated);
    setState(() {
      if (updated.status == 'deleted' || cancelled) _blocks.remove(updated);
    });
    await widget.sync.upsertScheduleBlock(_today, updated);
    if (cancelled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${updated.title} » annulé — il sort du programme'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => widget.sync.setBlockCancelled(_today, updated.id, false),
        ),
      ));
    }
  }

  Future<void> _addBlock() async {
    // Nouveau bloc au prochain quart d'heure, après la fin du dernier bloc.
    final n = DateTime.now();
    var start = n.hour * 60 + n.minute;
    for (final b in _blocks) {
      start = math.max(start, blockEndMin(b));
    }
    start = math.min(((start + 14) ~/ 15) * 15, 23 * 60 + 45);
    final created = await showScheduleBlockDialog(
      context,
      isNew: true,
      block: ScheduleBlock(
        startTime:
            '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}',
        durationMin: 30,
        title: '',
      ),
    );
    if (created == null || !mounted) return;
    await widget.sync.upsertScheduleBlock(_today, created);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _hit.add(block.id);
    final tgt = logic.activeHabitTarget(act);
    if (tgt > 0 && logic.habitValueOn(id, today) >= tgt) return;
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
          Expanded(
            child: LayoutBuilder(builder: (ctx, box) {
              // Chrono sur une action → la carte MAINTENANT se déploie en
              // bande Focus pleine largeur (étapes + contexte).
              final focus = _focusTarget;
              if (box.maxWidth < 1000) {
                // Écran étroit : les trois temps s'empilent.
                return ListView(children: [
                  if (focus != null) _focusBand(focus) else _nowCard(),
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
                      _nowCard(),
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

  // En-tête : date + résumé, bandeau ORION à droite.
  Widget _header() {
    final now = DateTime.now();
    final title = '${_kDays[now.weekday - 1]} ${now.day} ${_kMonths[now.month - 1]}';
    final done = _blocks.where((b) => b.status == 'done').length;
    final remaining = remainingPlannedMin(_blocks, _nowMin);
    final summary = _blocks.isEmpty
        ? 'Aucun programme pour aujourd\'hui'
        : '$done bloc${done > 1 ? 's' : ''} fait${done > 1 ? 's' : ''} sur ${_blocks.length}'
            '${remaining > 0 ? ' · ${_fmtHm(remaining)} planifiées restantes' : ''}'
            '${_generatedBy == 'auto' ? ' · planifiée automatiquement' : ''}';
    return Row(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
        const SizedBox(height: 3),
        Text(summary,
            style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
      ]),
      const SizedBox(width: 24),
      Expanded(child: Align(alignment: Alignment.centerRight, child: _orionBanner())),
    ]);
  }

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
        final start = DateTime(n.year, n.month, n.day).add(Duration(minutes: blockStartMin(b)));
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
        return (action: r.action, save: () => widget.sync.saveProjectTasks(p.id, p.tasks));
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
    final now = DateTime.now();
    final day0 = DateTime(now.year, now.month, now.day);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: current ? kBActive : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: current ? BorderSide(color: kBPrimary.withOpacity(.45)) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: project != null && !_editing
              ? () => widget.onOpenProject(project, taskId: b.taskId)
              : () => _editBlock(b),
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

  Widget _timelineCard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
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
          _textLink(_editing ? 'Terminé' : 'Modifier',
              () => setState(() => _editing = !_editing)),
        ]),
        const SizedBox(height: 14),
        Expanded(
          child: _blocks.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                      'Aucun programme — demande à Claude de planifier ta journée.',
                      style: TextStyle(fontSize: 13, color: kBText3),
                    ),
                    const SizedBox(height: 12),
                    _pillButton('Ajouter un bloc', onTap: _addBlock),
                  ]),
                )
              : LayoutBuilder(builder: (ctx, box) => _timeline(box.maxHeight)),
        ),
      ]),
    );
  }

  Widget _timeline(double height) {
    final (:startH, :endH) = timelineHours(_blocks, _nowMin);
    final range = (endH - startH) * 60;
    // Échelle : remplit la hauteur dispo, mais jamais sous 0,75 px/min (un
    // bloc de 30 min doit rester lisible) — au-delà, la frise défile.
    final ppm = timelinePxPerMin(height - 8, range);
    final total = range * ppm + 8;

    double y(int min) => (min - startH * 60) * ppm + 4;

    final now = _nowMin;
    final showNow = now >= startH * 60 && now <= endH * 60;

    final stack = SizedBox(
      height: total,
      child: Stack(clipBehavior: Clip.none, children: [
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
        ],
        for (final b in _blocks)
          Positioned(
            left: 56,
            right: 0,
            top: y(blockStartMin(b)) + 1,
            height: math.max(b.durationMin * ppm - 3, 20),
            child: _timelineBlock(b, b.durationMin * ppm - 3),
          ),
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
    return SingleChildScrollView(controller: _timelineCtrl, child: stack);
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
    final current = !done &&
        !skipped &&
        blockStartMin(b) <= now &&
        now < blockStartMin(b) + b.durationMin;
    final compact = h < 40;
    final project = _project(b.projectId);

    final check = InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _toggleDone(b),
      child: Tooltip(
        message: done ? 'Annuler' : 'Marquer comme fait',
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
    final trailing = Text(
      (current ? 'en cours' : fmtMin(b.durationMin)) + progress,
      style: TextStyle(
        fontSize: 12,
        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        color: current ? kBPrimary : kBText3,
        fontFeatures: _tabular,
      ),
    );

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
        // Bloc de projet → Gantt sur la tâche ; autre bloc (ou mode
        // « Modifier ») → éditeur.
        onTap: project != null && !_editing
            ? () => widget.onOpenProject(project, taskId: b.taskId)
            : () => _editBlock(b),
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
                        if (h > 84 && !done && !skipped && _blockHint(b) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _blockHint(b)!,
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
  String? _blockHint(ScheduleBlock b) {
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
      final r = routinesForToday([routine], _hits, DateTime.now()).firstOrNull;
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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
      final r = routinesForToday([routine], _hits, DateTime.now()).firstOrNull;
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    void persist() {
      final key = yyyymmdd(today);
      for (final h in logic.state.habitProgress) {
        if (h.activityId == act.id && h.yyyymmdd == key) widget.sync.saveHabitProgress(h);
      }
    }
    logic.incHabit(act.id, 1, today);
    persist();
    if (logic.state.habitHits.isNotEmpty) widget.sync.saveHabitHit(logic.state.habitHits.last);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
    final list = routinesForToday(widget.activities, _hits, DateTime.now());
    if (list.isEmpty) return const SizedBox.shrink();
    final reached = list.where((r) => r.reached).length;
    const cap = 5;
    final todo = list.where((r) => !r.reached).toList();
    final shown = _routinesAll ? list : todo.take(cap).toList();
    final hidden = list.length - shown.length;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label('ROUTINES DU JOUR')),
          Text('$reached / ${list.length} atteinte${reached > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
        ]),
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
      ]),
    );
  }

  /// Colonne de droite : (contenu des blocs) + routines + semaine.
  Widget _sideColumn({bool withAgenda = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (withAgenda) ...[_agendaCard(), const SizedBox(height: 18)],
        _routinesCard(),
        const SizedBox(height: 18),
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
        ),
        const SizedBox(height: 18),
        _weekColumn(),
      ]);

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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: _label(pairs.isEmpty ? 'À TRAITER' : 'À TRAITER · ${pairs.length}',
                color: pairs.isEmpty ? kBText3 : kBAlert),
          ),
          if (pairs.isNotEmpty) _textLink('Replanifier', widget.onOpenWeek),
        ]),
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
      ]),
    );
  }

  Widget _engagementsCard() {
    final stats = rollingWeekEngagements(activities: widget.activities, hits: _hits);
    final byDomain = <String, ({int done, int target})>{};
    for (final e in stats) {
      final cur = byDomain[e.domainId] ?? (done: 0, target: 0);
      byDomain[e.domainId] =
          (done: cur.done + math.min(e.done, e.target), target: cur.target + e.target);
    }
    final domains = widget.domains.where((d) => !d.deleted && byDomain.containsKey(d.id));

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('CETTE SEMAINE · 7 JOURS'),
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
      ]),
    );
  }

  Widget _deadlinesCard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = widget.projects
        .where((p) =>
            p.status == 'active' &&
            !p.paused &&
            p.endDate != null &&
            !p.endDate!.isBefore(today))
        .toList()
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    final shown = upcoming.take(3).toList();

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label('PROCHAINES ÉCHÉANCES')),
          _textLink('Projets', widget.onOpenProjects),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Text('Aucune échéance de projet.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final p in shown) _projectRow(p, today),
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
