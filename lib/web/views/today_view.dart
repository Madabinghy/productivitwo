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
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/assistant_engine.dart';
import 'package:productivitwo_v1/web/assistant_history_sheet.dart';
import 'package:productivitwo_v1/web/assistant_widget.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
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
  List<Session> _sessions = [];
  List<HabitHit> _hits = [];
  AppLogic? _logic; // pour valider la routine liée à un bloc (comme Focus)
  final Set<String> _hit = {};
  bool _busy = false;
  // Mode « Modifier » de la frise : chaque bloc s'ouvre dans l'éditeur.
  bool _editing = false;
  late String _today;

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
      }
      setState(() {});
    });
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
    final blocks = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    setState(() => _blocks = blocks);
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

  /// « Pour ce bloc » : le chrono en cours (lancé sur autre chose, ou avant
  /// l'heure du bloc) est ré-attribué au bloc — même règle que le mobile.
  Future<void> _attachToBlock(Session s, ScheduleBlock b) async {
    final ok = attachSessionToBlock(s, b,
        blockActivity: _activityOf(b.activityId), project: _project(b.projectId));
    if (!ok) return;
    setState(() {});
    await widget.sync.saveSession(s);
  }

  Future<void> _toggleDone(ScheduleBlock b) async {
    if (_busy) return;
    _busy = true;
    try {
      final newStatus = b.status == 'done' ? 'pending' : 'done';
      setState(() => b.status = newStatus);
      await widget.sync.updateBlockStatus(_today, b.id, newStatus);
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
    setState(() {
      if (updated.status == 'deleted') _blocks.remove(updated);
    });
    await widget.sync.upsertScheduleBlock(_today, updated);
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
                  SizedBox(height: 640, child: _timelineCard()),
                  const SizedBox(height: 18),
                  _weekColumn(),
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
                          child: SingleChildScrollView(child: _weekColumn()),
                        ),
                      ],
                    ),
                  ),
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 340, child: _nowCard()),
                  const SizedBox(width: 24),
                  Expanded(child: _timelineCard()),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 340,
                    child: SingleChildScrollView(child: _weekColumn()),
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
            '${remaining > 0 ? ' · ${_fmtHm(remaining)} planifiées restantes' : ''}';
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
      final blockAct = _activityOf(b?.activityId);
      final blockProject = _project(b?.projectId);
      // Le chrono tourne-t-il sur la SOURCE du bloc en cours ? Sinon la carte
      // montre ce qu'on fait ET ce qui était prévu, sans jamais cocher le bloc
      // par accident (même règle que la carte mobile).
      final onBlock = open != null &&
          b != null &&
          isCurrent &&
          sessionMatchesBlock(open, b,
              projectLinkedActivityId: blockProject?.linkedActivityId,
              activityLinkedActivityId: blockAct?.linkedActivityId);
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
          canAttachSessionToBlock(b, blockActivity: blockAct, project: blockProject);
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
    return SingleChildScrollView(child: stack);
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
