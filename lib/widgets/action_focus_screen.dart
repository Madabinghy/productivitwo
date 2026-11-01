import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show actionDueLabel, focusLabel;
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/widgets/offensive_screen.dart' show OffensiveScreen;
import 'package:productivitwo_v1/widgets/moment_card.dart' show MomentAction, showMomentActions;
import 'package:productivitwo_v1/widgets/undo_snack.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedNowMin;
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin;
import 'package:productivitwo_v1/utils/mode_moves.dart' show DeepWorkCandidate, deepWorkBlock;
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/time_spent.dart' show spentByAction;
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show kBrickRunning;
import 'package:wakelock_plus/wakelock_plus.dart';

/// Page focus (maquette « Page focus », 2026-10) : ▶ sur une action ouvre un
/// écran plein, pas un onglet. Une seule chose devant soi, le chrono qui
/// tourne dessus, les étapes à cocher une à une, et à la fin la trace de ce
/// qu'on a fait. Rien de nouveau en base : chrono ciblé (`Session.actionId`),
/// étapes existantes, bloc deep work (`deepWorkBlock`), pointage d'effort.
/// Trois états : avant · pendant · après.
Future<void> showActionFocusScreen(
  BuildContext context, {
  required AppLogic logic,
  required TaskAction action,
  Project? project,
  ProjectTask? task,
  /// Activité PORTEUSE d'une action propre (sans projet).
  Activity? ownerActivity,
  /// Activité du chrono (liée à l'action, sinon au projet, sinon la porteuse).
  Activity? chronoActivity,
  FirestoreSync? sync,
  /// Gestes de l'appelant (viser un jour, caser, détail, projet…), derrière
  /// le ⋯ de la barre.
  List<MomentAction> moreActions = const [],
}) {
  return Navigator.of(context).push(_focusSheetRoute(
    builder: (_) => (_FocusScreen(
      logic: logic,
      action: action,
      project: project,
      task: task,
      ownerActivity: ownerActivity,
      chronoActivity: chronoActivity,
      sync: sync ?? FirestoreSync(),
      moreActions: moreActions,
    )),
  ));
}

/// La page focus s'ouvre en FEUILLE (retour user 2026-10-30) : même mécanique
/// que `showFiche` — `DraggableScrollableSheet` dont le contrôleur pilote la
/// liste de la page (`_SheetScroll`) : tirer vers le bas, depuis la liste
/// remontée en haut ou n'importe quelle zone fixe, réduit puis ferme la
/// feuille. Les enchaînements la remplacent sur place.
Route<void> _focusSheetRoute({required WidgetBuilder builder}) => ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: .95,
        minChildSize: .5,
        maxChildSize: .95,
        expand: false,
        builder: (ctx, scroll) {
          final cs = Theme.of(ctx).colorScheme;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _SheetScroll(
              controller: scroll,
              child: Stack(children: [
                Positioned.fill(child: builder(ctx)),
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .25), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

/// Le contrôleur de la feuille, pour la liste de la page.
class _SheetScroll extends InheritedWidget {
  final ScrollController controller;
  const _SheetScroll({required this.controller, required super.child});
  static ScrollController? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SheetScroll>()?.controller;
  @override
  bool updateShouldNotify(_SheetScroll old) => old.controller != controller;
}

/// Mode « bloc » (maquette « Blocs d'activité », 2026-10) : la page focus
/// ouverte depuis le ▶ d'un bloc d'ACTIVITÉ porte la file du bloc (une action
/// par projet lié, puis les actions propres) ; on en prend une, le chrono
/// tourne sur l'activité du bloc, « Suivante » passe à la prochaine sans
/// sortir. Le bloc ne retient que le temps.
class BlockFocus {
  final ScheduleBlock block;
  final Activity activity;
  final List<QueueItem> queue;
  /// Jour du programme qui porte le bloc (`YYYY-MM-DD`).
  final String ymd;
  const BlockFocus({required this.block, required this.activity, required this.queue, required this.ymd});

  DateTime get date => DateTime.parse(ymd);
  /// Minutes restantes sur la journée VÉCUE (un bloc de la nuit après minuit
  /// compte +24 h, comme `blockStartMin`).
  int remainingMin(DateTime now, {int dayStartMin = 0}) {
    final start = blockStartMin(block);
    final nowMin = livedNowMin(now, dayStartMin);
    if (nowMin < start) return block.durationMin;
    final end = start + block.durationMin;
    return end > nowMin ? end - nowMin : 0;
  }
}

/// Ouvre la page focus sur la file d'un bloc d'activité ([queue] non vide).
Future<void> showBlockFocusScreen(
  BuildContext context, {
  required AppLogic logic,
  required ScheduleBlock block,
  required Activity activity,
  required List<QueueItem> queue,
  required String ymd,
  FirestoreSync? sync,
}) {
  final bf = BlockFocus(block: block, activity: activity, queue: queue, ymd: ymd);
  return Navigator.of(context).push(_focusSheetRoute(
    builder: (_) => (_FocusScreen.ofQueue(logic: logic, bloc: bf, index: 0, sync: sync ?? FirestoreSync(), picking: true)),
  ));
}

enum _Phase { before, running, after }

class _FocusScreen extends StatefulWidget {
  final AppLogic logic;
  final TaskAction action;
  final Project? project;
  final ProjectTask? task;
  final Activity? ownerActivity;
  final Activity? chronoActivity;
  final FirestoreSync sync;
  final BlockFocus? bloc;
  final int index;
  /// Mode bloc, à l'entrée : la file est montrée avant de choisir.
  final bool picking;
  final List<MomentAction> moreActions;
  const _FocusScreen({
    this.moreActions = const [],
    required this.logic,
    required this.action,
    this.project,
    this.task,
    this.ownerActivity,
    this.chronoActivity,
    required this.sync,
    this.bloc,
    this.index = 0,
    this.picking = false,
  });

  factory _FocusScreen.ofQueue({
    required AppLogic logic,
    required BlockFocus bloc,
    required int index,
    required FirestoreSync sync,
    bool picking = false,
  }) {
    final it = bloc.queue[index];
    return _FocusScreen(
      logic: logic,
      action: it.action,
      project: it.project,
      task: it.task,
      ownerActivity: it.project == null ? bloc.activity : null,
      chronoActivity: bloc.activity,
      sync: sync,
      bloc: bloc,
      index: index,
      picking: picking,
    );
  }

  @override
  State<_FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<_FocusScreen> {
  Timer? _tick;
  _Phase _phase = _Phase.before;
  int _thisChronoMin = 0;
  int? _effort;
  int? _plannedMin;
  late bool _picking = widget.picking;
  // Mode bloc : l'élément de la file affiché. Changer d'action = changer
  // d'index SUR PLACE (retour user 2026-10-30 : plus de fermeture / réouverture).
  late int _index = widget.index;

  QueueItem? get _item => widget.bloc?.queue[_index];
  TaskAction get a => _item?.action ?? widget.action;
  Project? get _project => _item == null ? widget.project : _item!.project;
  ProjectTask? get _task => _item == null ? widget.task : _item!.task;
  Activity? get _owner => _item == null ? widget.ownerActivity : (_item!.project == null ? (_item!.activity ?? widget.bloc!.activity) : null);
  /// Activité du chrono : celle de l'élément pour un bloc de TEMPS (chaque
  /// action a la sienne), sinon celle de la page.
  Activity? get _chronoAct => widget.bloc?.block.timeBlock != null ? _item?.activity : widget.chronoActivity;
  int _remaining(BlockFocus b) => b.remainingMin(DateTime.now(), dayStartMin: logic.dayStartMin);

  /// Prochain élément ouvert de la file après celui-ci (en boucle), sinon null.
  int? get _nextIndex {
    final b = widget.bloc;
    if (b == null) return null;
    final n = b.queue.length;
    for (var k = 1; k < n; k++) {
      final i = (_index + k) % n;
      if (!b.queue[i].action.done) return i;
    }
    return null;
  }

  /// Fin du bloc : chrono arrêté, récap (temps tenu, fait, reste) et
  /// « Caser un bloc demain ». Le bloc passe « fait » dès qu'il a du temps.
  void _endBlock() {
    final r = _running;
    if (r != null) logic.stopActive();
    Navigator.of(context).pushReplacement(_focusSheetRoute(
      builder: (_) => (_BlockEndScreen(logic: logic, bloc: widget.bloc!, sync: widget.sync)),
    ));
  }

  void _goTo(int index, {bool picking = false}) {
    if (_running != null) logic.stopActive();
    HapticFeedback.selectionClick();
    setState(() {
      _index = index;
      _picking = picking;
      _phase = _Phase.before;
      _thisChronoMin = 0;
      _effort = null;
      _plannedMin = null;
    });
  }
  AppLogic get logic => widget.logic;

  Session? get _running =>
      logic.state.sessions.where((s) => s.endAt == null && !s.deleted && s.actionId == a.id).firstOrNull;

  @override
  void initState() {
    super.initState();
    final r = _running;
    if (r != null) _phase = _Phase.running;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _phase == _Phase.running) setState(() {});
    });
    logic.addListener(_onLogic);
    WakelockPlus.enable().catchError((_) {});
  }

  void _onLogic() {
    if (!mounted) return;
    // Chrono arrêté ailleurs (barre du haut, autre écran) → on repasse « avant ».
    if (_phase == _Phase.running && _running == null) setState(() => _phase = _Phase.before);
  }

  @override
  void dispose() {
    _tick?.cancel();
    logic.removeListener(_onLogic);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ── Écritures ───────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final p = _project;
    try {
      if (p != null) {
        await widget.sync.patchActionOf(p, a);
      } else if (_owner != null) {
        await widget.sync.updateOwnActions(_owner!.id, _owner!.ownActions);
      }
    } catch (_) {
      // Hors ligne / pas de session : l'état local reste la vérité de l'écran.
    }
    logic.onChange();
  }

  Future<void> _mutate(void Function() f) async {
    setState(f);
    await _persist();
    if (a.done && _phase != _Phase.after) _finish();
  }

  void _start({int? minutes}) {
    final act = _chronoAct;
    if (act == null) return;
    HapticFeedback.lightImpact();
    logic.start(act.id, taskId: _task?.id, actionId: a.id);
    setState(() {
      _phase = _Phase.running;
      _plannedMin = minutes;
    });
  }

  Future<void> _deepWork() async {
    final act = _chronoAct;
    if (act == null) return;
    final block = deepWorkBlock(
      DeepWorkCandidate(
        kind: _project != null ? 'project' : 'other',
        title: a.title,
        subtitle: _project?.title ?? act.name,
        projectId: _project?.id,
        taskId: _task?.id,
        actionId: a.id,
        activityId: act.id,
      ),
      DateTime.now(),
      dayStartMin: logic.dayStartMin,
    );
    await widget.sync.upsertScheduleBlock(logic.livedTodayYmd, block);
    _start(minutes: 90);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, 
        duration: const Duration(seconds: 3),
        content: Text('Bloc Deep work posé ${block.startTime} → ${_plus(block.startTime, 90)} · compte pour le badge'),
      ));
    }
  }

  String _plus(String hm, int min) {
    final m = (int.parse(hm.substring(0, 2)) * 60 + int.parse(hm.substring(3, 5)) + min) % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  void _pause() {
    final r = _running;
    if (r != null) {
      _thisChronoMin += DateTime.now().difference(r.startAt).inMinutes;
      logic.stopActive();
    }
    setState(() => _phase = _Phase.before);
  }

  void _finish() {
    final r = _running;
    if (r != null) {
      _thisChronoMin += DateTime.now().difference(r.startAt).inMinutes;
      logic.stopActive();
    }
    setState(() => _phase = _Phase.after);
  }

  Future<void> _chooseDuration() async {
    final est = a.estimatedMin;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget opt(int min, String title, String hint, {bool deep = false}) => ListTile(
              leading: SizedBox(
                  width: 44,
                  child: Text('$min', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(hint, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
              trailing: deep ? const Icon(Icons.bolt_rounded, color: kPalierAmber) : null,
              onTap: () => Navigator.pop(ctx, min),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(children: [
                const Expanded(child: Text('Mode d\'exécution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (est != null) Text('estimé ${fmtMin(est)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
              ]),
            ),
            opt(25, 'Un sprint', 'le chrono, rien d\'autre'),
            if (est != null && est != 25 && est != 90) opt(est, 'L\'estimation', 'le chrono sur ≈ ${fmtMin(est)}'),
            opt(90, 'Deep work', 'bloc posé dans le programme à partir de maintenant · badge Deep work', deep: true),
            if (_project != null)
              ListTile(
                leading: const SizedBox(width: 44, child: Icon(Icons.north_east_rounded, color: Color(0xFFFF8A4C))),
                title: const Text('Offensive', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('enchaîner « ${_project!.title} » en coups de 10 à 25 min, à partir de cette action',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
                onTap: () => Navigator.pop(ctx, -1),
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (picked == -1) {
      _openOffensive();
      return;
    }
    if (picked == 90) {
      await _deepWork();
    } else {
      _start(minutes: picked);
    }
  }

  /// La page focus laisse la place à l'offensive, front et première action posés.
  void _openOffensive() {
    final p = _project;
    if (p == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => OffensiveScreen(logic: logic, projectId: p.id, firstActionId: a.id)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  // Même grammaire que l'écran « séance en cours » (retour user 2026-10-30) :
  // en-tête ✕ + titre + contexte, bandeau « Étape k / n » + temps + barre,
  // l'étape en cours en grand, « Ensuite : … », Précédente / Étape suivante,
  // la liste complète des étapes, le chrono en bas.

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text3 = cs.onSurface.withValues(alpha: .55);
    final spentBefore = spentByAction(logic.state.sessions)[a.id] ?? 0;
    final stepsDone = a.checklist.where((c) => c.done).length;
    final stepsTotal = a.checklist.length;
    final next = nextChecklistItem(a);
    final after = _phase == _Phase.after;
    final canChrono = _chronoAct != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).maybePop()),
        titleSpacing: 0,
        // Après : le titre fait de l'action en tête ; avant / pendant, il est en grand dans la page.
        title: after
            ? Text('${a.title}${a.done ? ' ✓' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))
            : null,
        actions: [
          if (!after && canChrono && _phase == _Phase.before)
            IconButton(tooltip: 'Lancer le chrono', icon: const Icon(Icons.timer_outlined), onPressed: () => _start(minutes: a.estimatedMin)),
          if (!after && _project != null && _phase == _Phase.before)
            IconButton(
              tooltip: 'Offensive sur ce projet',
              icon: const Icon(Icons.north_east_rounded, color: Color(0xFFFF8A4C)),
              onPressed: _openOffensive,
            ),
          if (widget.moreActions.isNotEmpty)
            IconButton(
              tooltip: 'Autres gestes',
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () => showMomentActions(context, title: a.title, actions: widget.moreActions).then((_) {
                if (mounted) setState(() {});
              }),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _SheetScroll.of(context),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              children: [
                _whereAmI(cs, text3),
                ...after ? _trace(cs, text3, spentBefore, stepsDone, stepsTotal) : _session(cs, text3, spentBefore, stepsDone, stepsTotal, next),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _bottom(cs, text3, next)),
          ),
        ]),
      ),
    );
  }

  /// Où on en est (retour user 2026-10-30 : le fil d'Ariane tronqué dans la
  /// barre ne se lisait pas) : projet, tâche, bloc, chacun sur sa ligne et
  /// en entier.
  Widget _whereAmI(ColorScheme cs, Color text3) {
    final rows = <(String, String)>[
      if (widget.bloc case final b?) ('BLOC', b.activity.name),
      if (_project case final p?) ('PROJET', p.title),
      if (_task case final t?) ('TÂCHE', t.title),
      if (_project == null && _owner != null) ('ACTIVITÉ', _owner!.name),
      // Avec des étapes, c'est l'étape qui est en grand : l'action se lit ici.
      if (a.checklist.isNotEmpty && _phase != _Phase.after) ('ACTION', a.title),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .05), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, r) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 64,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(r.$1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: text3)),
                ),
              ),
              Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3))),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _session(ColorScheme cs, Color text3, int spentBefore, int stepsDone, int stepsTotal, ChecklistItem? next) {
    final r = _running;
    final elapsed = r == null ? Duration.zero : DateTime.now().difference(r.startAt);
    final goalMin = _plannedMin ?? a.estimatedMin;
    final bloc = widget.bloc;
    final remaining = bloc == null ? null : _remaining(bloc);
    final steps = a.checklist;
    final currentIdx = next == null ? steps.length : steps.indexOf(next);
    final lastDone = steps.where((c) => c.done).lastOrNull;
    final String right;
    final Color rightColor;
    if (r != null) {
      right = '${_mmss(elapsed)}${goalMin != null ? ' · sur ≈ ${fmtMin(goalMin)}' : ''}';
      rightColor = kBrickRunning;
    } else if (remaining != null) {
      right = remaining > 0 ? 'bloc · reste ${fmtMin(remaining)}' : 'bloc terminé';
      rightColor = remaining > 0 ? text3 : kPalierAmber;
    } else {
      right = [
        if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
        if (spentBefore > 0) 'déjà ${fmtMin(spentBefore)}',
      ].join(' · ');
      rightColor = text3;
    }
    final progress = stepsTotal > 0
        ? stepsDone / stepsTotal
        : (a.estimatedMin == null || a.estimatedMin! <= 0 ? 0.0 : (spentBefore / a.estimatedMin!).clamp(0.0, 1.0));
    final openCount = steps.where((c) => !c.done).length;
    return [
      Row(children: [
        Flexible(
          child: Text(
            stepsTotal == 0 ? 'Une seule chose à faire' : (next == null ? 'Étapes faites · $stepsTotal / $stepsTotal' : 'Étape ${currentIdx + 1} / $stepsTotal'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: .6)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(right,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: rightColor, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: cs.onSurface.withValues(alpha: .08), valueColor: const AlwaysStoppedAnimation(kPalierGreen)),
      ),
      if (r != null && goalMin != null && goalMin > 0) ...[
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: (elapsed.inSeconds / (goalMin * 60)).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation(kBrickRunning)),
        ),
      ],
      if (bloc != null && _picking && _phase == _Phase.before) ...[const SizedBox(height: 16), ..._queueList(cs, text3, bloc)],
      // L'étape en cours, en grand.
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 150),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (next != null) ...[
              Text(next.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 10),
              Text(_afterNext(next), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: text3)),
            ] else if (stepsTotal == 0) ...[
              Text(a.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 10),
              Text('Pas d’étapes : ajoute-les en dessous, ou fais-la d’un trait.', style: TextStyle(fontSize: 13.5, color: text3)),
            ] else ...[
              Row(children: [
                const Icon(Icons.check_circle_outline, size: 30, color: kPalierGreen),
                const SizedBox(width: 10),
                Expanded(child: Text(a.done ? 'Action faite.' : 'Toutes les étapes sont faites.', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              ]),
            ],
            if (a.allContexts.isNotEmpty || (r != null && _chronoAct != null)) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (r != null && _chronoAct != null) _pill('● chrono · ${_chronoAct!.name}', kBrickRunning),
                for (final c in a.allContexts) _pill(c, text3),
              ]),
            ],
          ]),
        ),
      ),
      // Commandes, comme la séance : Précédente · Étape suivante.
      Row(children: [
        OutlinedButton.icon(
          onPressed: lastDone == null ? null : () => _mutate(() => setChecklistItem(a, lastDone.id, false)),
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Précédente'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: a.done ? null : () => _mutate(() => next != null ? setChecklistItem(a, next.id, true) : setActionDone(a, true)),
              icon: Icon(next != null && openCount > 1 ? Icons.skip_next_rounded : Icons.check_rounded),
              label: Text(next != null && openCount > 1 ? 'Étape suivante' : 'Action faite', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      // La liste complète.
      for (var k = 0; k < steps.length; k++)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          leading: Icon(
            steps[k].done ? Icons.check_circle : (k == currentIdx ? Icons.play_circle_outline : Icons.radio_button_unchecked),
            size: 20,
            color: steps[k].done || k == currentIdx ? kPalierGreen : cs.onSurface.withValues(alpha: .4),
          ),
          title: Text(
            steps[k].title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: k == currentIdx ? FontWeight.w700 : FontWeight.w500,
              color: cs.onSurface.withValues(alpha: steps[k].done ? .45 : .9),
              decoration: steps[k].done ? TextDecoration.lineThrough : null,
            ),
          ),
          trailing: IconButton(
            tooltip: 'Modifier l’étape',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.more_horiz, size: 20, color: cs.onSurface.withValues(alpha: .5)),
            onPressed: () => _editStep(steps[k]),
          ),
          onTap: () => _mutate(() => setChecklistItem(a, steps[k].id, !steps[k].done)),
          onLongPress: () => _editStep(steps[k]),
        ),
      ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: const Icon(Icons.add, size: 20, color: kPalierGreen),
        title: const Text('Ajouter une étape', style: TextStyle(fontSize: 13.5, color: kPalierGreen)),
        onTap: _addStep,
      ),
      if (a.note != null && a.note!.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('DÉTAIL', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
        const SizedBox(height: 4),
        Text(a.note!, style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurface.withValues(alpha: .75))),
      ],
    ];
  }

  Future<String?> _askText(String title, {String initial = '', String hint = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return v == null || v.trim().isEmpty ? null : v.trim();
  }

  Future<void> _addStep() async {
    final v = await _askText('Ajouter une étape', hint: 'Relire le premier jet');
    if (v != null) await _mutate(() => addChecklistItem(a, v));
  }

  Future<void> _editStep(ChecklistItem c) async {
    final i = a.checklist.indexWhere((x) => x.id == c.id);
    if (i < 0) return;
    final n = a.checklist.length;
    final err = Theme.of(context).colorScheme.error;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Renommer'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: Icon(c.done ? Icons.radio_button_unchecked : Icons.check_circle_outline),
              title: Text(c.done ? 'Décocher' : 'Cocher'),
              onTap: () => Navigator.pop(ctx, 'toggle')),
          if (i > 0) ListTile(leading: const Icon(Icons.arrow_upward_rounded), title: const Text('Monter'), onTap: () => Navigator.pop(ctx, 'up')),
          if (i < n - 1) ListTile(leading: const Icon(Icons.arrow_downward_rounded), title: const Text('Descendre'), onTap: () => Navigator.pop(ctx, 'down')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: err),
              title: Text('Supprimer l’étape', style: TextStyle(color: err)),
              onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'rename':
        final v = await _askText('Renommer l’étape', initial: c.title);
        if (v != null) await _mutate(() => renameChecklistItem(a, c.id, v));
      case 'toggle':
        await _mutate(() => setChecklistItem(a, c.id, !c.done));
      case 'up':
        await _mutate(() => moveChecklistItem(a, i, i - 1));
      case 'down':
        await _mutate(() => moveChecklistItem(a, i, i + 2));
      case 'remove':
        await _mutate(() => removeChecklistItem(a, c.id));
        if (!mounted) return;
        showUndoSnackBar(context, 'Étape supprimée : ${c.title}',
            () => _mutate(() => a.checklist.insert(i.clamp(0, a.checklist.length), c)));
    }
  }

  List<Widget> _trace(ColorScheme cs, Color text3, int spentBefore, int stepsDone, int stepsTotal) {
    final total = spentBefore; // spentByAction inclut déjà la session qu'on vient de fermer
    final t = _task;
    final actionsDone = t?.actions.where((x) => x.done).length ?? 0;
    final actionsTotal = t?.actions.length ?? 0;
    final nextAction = t?.actions.where((x) => !x.done && x.id != a.id).firstOrNull;
    Widget tile(String v, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              Text(l, style: TextStyle(fontSize: 11, color: text3)),
            ]),
          ),
        );
    return [
      Row(children: [
        tile(fmtMin(_thisChronoMin), 'ce chrono'),
        const SizedBox(width: 8),
        tile(fmtMin(total), a.estimatedMin != null ? 'au total · estimé ${fmtMin(a.estimatedMin!)}' : 'au total'),
        const SizedBox(width: 8),
        tile(stepsTotal > 0 ? '$stepsDone / $stepsTotal' : (a.done ? '✓' : '—'), stepsTotal > 0 ? 'étapes faites' : (a.done ? 'faite' : 'en cours')),
      ]),
      if (t != null) ...[
        const SizedBox(height: 18),
        Text('LA TÂCHE AVANCE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: actionsTotal == 0 ? 0 : actionsDone / actionsTotal,
              minHeight: 10,
              color: kPalierGreen,
              backgroundColor: cs.onSurface.withValues(alpha: .08)),
        ),
        const SizedBox(height: 6),
        Text(
          nextAction == null
              ? '$actionsDone / $actionsTotal actions faites · ${actionsDone == actionsTotal ? 'la tâche est finie' : 'rien d\'autre d\'ouvert'}'
              : '$actionsDone / $actionsTotal actions faites · reste ${nextAction.title}${nextAction.estimatedMin != null ? ' ≈ ${fmtMin(nextAction.estimatedMin!)}' : ''}',
          style: TextStyle(fontSize: 12.5, color: text3),
        ),
      ],
      const SizedBox(height: 18),
      Text('C\'ÉTAIT COMMENT ?', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (var i = 0; i < kEffortLabels.length; i++)
          ChoiceChip(
            label: Text(kEffortLabels[i]),
            selected: _effort == i,
            onSelected: (_) {
              setState(() => _effort = i);
              logic.logMood(kMoodEffort, i);
            },
          ),
      ]),
    ];
  }

  /// Mode bloc, avant de choisir : la file du bloc, l'élément courant cerclé.
  List<Widget> _queueList(ColorScheme cs, Color text3, BlockFocus bloc) {
    final open = [for (var i = 0; i < bloc.queue.length; i++) if (!bloc.queue[i].action.done) i];
    final est = queueEstimateMin([for (final i in open) bloc.queue[i]]);
    final remaining = _remaining(bloc);
    final today = DateTime.now();
    return [
      Text(bloc.block.timeBlock != null ? 'SUR QUOI TU PARS ? · ${open.length}' : 'LA FILE DU BLOC · ${open.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: text3)),
      const SizedBox(height: 8),
      for (final i in open)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => i == _index ? setState(() => _picking = false) : _goTo(i, picking: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: i == _index ? kBrickRunning : Colors.transparent, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (bloc.queue[i].reason case final r?)
                      Text(r, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: r == 'EN RETARD' ? kPalierCoral : kBrickRunning)),
                    if (bloc.queue[i].context ?? bloc.queue[i].activity?.name case final c?) Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: text3)),
                    Text(bloc.queue[i].action.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(
                  [
                    if (bloc.queue[i].focus case final f?) '☀ ${focusLabel(f, today)}',
                    if (bloc.queue[i].due case final d?) actionDueLabel(d, today),
                    if (bloc.queue[i].action.estimatedMin case final m?) fmtMin(m),
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: bloc.queue[i].overdue ? kPalierCoral : text3),
                ),
              ]),
            ),
          ),
        ),
      if (open.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            'Total ≈ ${fmtMin(est)} pour ${fmtMin(remaining)} de bloc${est > remaining ? ' : le reste glissera au prochain bloc ${bloc.activity.name}' : ''}.',
            style: TextStyle(fontSize: 12, color: text3, height: 1.35),
          ),
        ),
      const SizedBox(height: 14),
    ];
  }

  List<Widget> _bottom(ColorScheme cs, Color text3, ChecklistItem? next) {
    Widget primary(String label, IconData icon, VoidCallback? onTap) => SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
          ),
        );
    Widget link(String label, VoidCallback? onTap, {Color? color}) => Flexible(
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
                foregroundColor: color ?? cs.onSurface.withValues(alpha: .75),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    final canChrono = _chronoAct != null;
    final nextIdx = _nextIndex;
    switch (_phase) {
      case _Phase.before:
        // Étape suivante / Action faite sont dans la page (comme la séance) ;
        // en bas, le chrono et la sortie.
        return [
          const SizedBox(height: 6),
          if (canChrono)
            SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed: () => _start(minutes: a.estimatedMin),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(widget.bloc != null && _picking ? 'Commencer · ${a.title}' : 'Lancer le chrono',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            if (widget.bloc != null)
              link('Terminer le bloc', _endBlock, color: text3)
            else if (canChrono)
              Flexible(
                child: TextButton.icon(
                  onPressed: _chooseDuration,
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: const Text('Mode d\'exécution', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: TextButton.styleFrom(
                      foregroundColor: kPalierAmber,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ),
            link('Terminer · bilan', _finish, color: text3),
          ]),
        ];
      case _Phase.running:
        final over = widget.bloc != null && _remaining(widget.bloc!) == 0;
        return [
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text('Le bloc est fini · le chrono continue', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPalierAmber))),
                link('Terminer le bloc', _endBlock, color: kPalierAmber),
              ]),
            ),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(onPressed: _pause, icon: const Icon(Icons.pause_rounded), label: const Text('Pause', style: TextStyle(fontWeight: FontWeight.w800))),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            link('Terminer · bilan', _finish, color: text3),
            if (nextIdx != null) link('Suivante ›', () => _goTo(nextIdx), color: kPalierAmber),
          ]),
        ];
      case _Phase.after:
        final t = _task;
        final nextAction = t?.actions.where((x) => !x.done && x.id != a.id).firstOrNull;
        return [
          const SizedBox(height: 8),
          if (nextIdx != null)
            primary('Enchaîner · ${widget.bloc!.queue[nextIdx].action.title}', Icons.play_arrow_rounded, () => _goTo(nextIdx))
          else if (widget.bloc != null)
            primary('Terminer le bloc', Icons.check_rounded, _endBlock)
          else if (nextAction != null && _project != null && widget.bloc == null)
            primary('Enchaîner · ${nextAction.title}', Icons.play_arrow_rounded, () {
              Navigator.of(context).pushReplacement(_focusSheetRoute(
                builder: (_) => (_FocusScreen(
                  logic: logic,
                  action: nextAction,
                  project: _project,
                  task: t,
                  chronoActivity: _chronoAct,
                  sync: widget.sync,
                )),
              ));
            })
          else
            primary('Fermer', Icons.check_rounded, () => Navigator.of(context).maybePop()),
          if (nextIdx != null || widget.bloc != null || nextAction != null)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (nextIdx != null && widget.bloc != null) link('Terminer le bloc', _endBlock, color: text3),
              link('Fermer', () => Navigator.of(context).maybePop(), color: text3),
            ]),
        ];
    }
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      );

  String _afterNext(ChecklistItem next) {
    final open = a.checklist.where((c) => !c.done).toList();
    if (open.length <= 1) return 'Dernière étape : elle termine l\'action.';
    return 'Ensuite : ${open[1].title}${open.length > 2 ? ' · puis ${open[2].title}' : ''}';
  }

  String _mmss(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Écran de fin d'un bloc d'activité (lot 2) : le temps tenu, ce qui a été
/// fait sur ce bloc, ce qui reste dans la file (qui ne va nulle part : ça
/// revient au prochain bloc de l'activité), « Caser un bloc demain ».
class _BlockEndScreen extends StatefulWidget {
  final AppLogic logic;
  final BlockFocus bloc;
  final FirestoreSync sync;
  const _BlockEndScreen({required this.logic, required this.bloc, required this.sync});

  @override
  State<_BlockEndScreen> createState() => _BlockEndScreenState();
}

class _BlockEndScreenState extends State<_BlockEndScreen> {
  late final BlockOutcome outcome;
  bool _carried = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bloc;
    outcome = blockOutcome(
      block: b.block,
      date: b.date,
      activityId: b.block.timeBlock != null ? null : b.activity.id,
      queue: b.queue,
      sessions: widget.logic.state.sessions,
      now: DateTime.now(),
    );
    if (outcome.heldMin > 0 && b.block.status != 'done') {
      widget.sync.updateBlockStatus(b.ymd, b.block.id, 'done', doneBy: 'focus').catchError((_) {});
    }
  }

  Future<void> _carry() async {
    final b = widget.bloc;
    final tomorrow = b.date.add(const Duration(days: 1));
    final ymd = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    try {
      await widget.sync.upsertScheduleBlock(ymd, carriedActivityBlock(b.block, b.ymd));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _carried = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, content: Text('Bloc ${b.activity.name} posé demain à ${b.block.startTime}.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text3 = cs.onSurface.withValues(alpha: .55);
    final b = widget.bloc;
    final w = blockWindow(b.block, b.date);
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    Widget tile(String v, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(l, style: TextStyle(fontSize: 11, color: text3)),
            ]),
          ),
        );
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: text3)),
        );
    Widget row(QueueItem q, {String? right, bool done = false}) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (q.context case final c?) Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: text3)),
                Text(q.action.title,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null, color: done ? text3 : null)),
              ]),
            ),
            if (right != null) Text(right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: text3)),
          ]),
        );
    final steps = outcome.stepsDone;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text('BLOC TERMINÉ', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: text3)),
              ),
              IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Navigator.of(context).maybePop()),
            ]),
            Expanded(
              child: ListView(controller: _SheetScroll.of(context), padding: const EdgeInsets.only(top: 10, bottom: 12), children: [
                Text('${b.activity.name}${outcome.heldMin > 0 ? ' ✓' : ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 4),
                Text('${hm(w.start)} → ${hm(w.end)} · ${days[b.date.weekday - 1]}', style: TextStyle(fontSize: 12.5, color: text3)),
                const SizedBox(height: 14),
                Row(children: [
                  tile(fmtMin(outcome.heldMin), 'tenu sur ${fmtMin(b.block.durationMin)}'),
                  const SizedBox(width: 8),
                  tile('${outcome.doneItems.length}', outcome.doneItems.length == 1 ? 'action faite' : 'actions faites'),
                  const SizedBox(width: 8),
                  tile('$steps', steps == 1 ? 'étape' : 'étapes'),
                ]),
                if (outcome.doneItems.isNotEmpty) ...[
                  section('FAIT SUR CE BLOC'),
                  for (final q in outcome.doneItems) row(q, done: true, right: outcome.minutesByAction[q.id] == null ? null : fmtMin(outcome.minutesByAction[q.id]!)),
                ],
                if (outcome.remaining.isNotEmpty) ...[
                  section('RESTE DANS LA FILE · ${outcome.remaining.length}'),
                  for (final q in outcome.remaining) row(q, right: q.action.estimatedMin == null ? null : fmtMin(q.action.estimatedMin!)),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Elles ne vont nulle part : elles restent la prochaine action de leur projet et reviendront dans la file du prochain bloc ${b.activity.name}.',
                      style: TextStyle(fontSize: 12.5, color: text3, height: 1.4),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _carried ? null : _carry,
                icon: Icon(_carried ? Icons.check_rounded : Icons.event_repeat_rounded),
                label: Text(_carried ? 'Bloc posé demain' : 'Caser un bloc ${b.activity.name} demain',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(foregroundColor: text3, textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                child: const Text('Fermer'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
