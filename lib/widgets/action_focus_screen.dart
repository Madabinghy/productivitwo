import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show actionDueLabel;
import 'package:productivitwo_v1/utils/block_queue.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/mode_moves.dart' show DeepWorkCandidate, deepWorkBlock;
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/time_spent.dart' show spentByAction;
import 'package:productivitwo_v1/widgets/moment_card.dart' show MomentRing;
import 'package:productivitwo_v1/widgets/progress_bricks.dart' show StepDots, kBrickRunning;
import 'package:productivitwo_v1/widgets/steps_section.dart';
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
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _FocusScreen(
      logic: logic,
      action: action,
      project: project,
      task: task,
      ownerActivity: ownerActivity,
      chronoActivity: chronoActivity,
      sync: sync ?? FirestoreSync(),
    ),
  ));
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
  const BlockFocus({required this.block, required this.activity, required this.queue});

  int remainingMin(DateTime now) => blockRemainingMin(block, now.hour * 60 + now.minute);
}

/// Ouvre la page focus sur la file d'un bloc d'activité ([queue] non vide).
Future<void> showBlockFocusScreen(
  BuildContext context, {
  required AppLogic logic,
  required ScheduleBlock block,
  required Activity activity,
  required List<QueueItem> queue,
  FirestoreSync? sync,
}) {
  final bf = BlockFocus(block: block, activity: activity, queue: queue);
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _FocusScreen.ofQueue(logic: logic, bloc: bf, index: 0, sync: sync ?? FirestoreSync(), picking: true),
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
  const _FocusScreen({
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

  TaskAction get a => widget.action;

  /// Prochain élément ouvert de la file après celui-ci (en boucle), sinon null.
  int? get _nextIndex {
    final b = widget.bloc;
    if (b == null) return null;
    final n = b.queue.length;
    for (var k = 1; k < n; k++) {
      final i = (widget.index + k) % n;
      if (!b.queue[i].action.done) return i;
    }
    return null;
  }

  void _goTo(int index, {bool picking = false}) {
    final r = _running;
    if (r != null) {
      _thisChronoMin += DateTime.now().difference(r.startAt).inMinutes;
      logic.stopActive();
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _FocusScreen.ofQueue(logic: logic, bloc: widget.bloc!, index: index, sync: widget.sync, picking: picking),
    ));
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
    final p = widget.project;
    try {
      if (p != null) {
        await widget.sync.patchActionOf(p, a);
      } else if (widget.ownerActivity != null) {
        await widget.sync.updateOwnActions(widget.ownerActivity!.id, widget.ownerActivity!.ownActions);
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
    final act = widget.chronoActivity;
    if (act == null) return;
    HapticFeedback.lightImpact();
    logic.start(act.id, taskId: widget.task?.id, actionId: a.id);
    setState(() {
      _phase = _Phase.running;
      _plannedMin = minutes;
    });
  }

  Future<void> _deepWork() async {
    final act = widget.chronoActivity;
    if (act == null) return;
    final block = deepWorkBlock(
      DeepWorkCandidate(
        kind: widget.project != null ? 'project' : 'other',
        title: a.title,
        subtitle: widget.project?.title ?? act.name,
        projectId: widget.project?.id,
        taskId: widget.task?.id,
        actionId: a.id,
        activityId: act.id,
      ),
      DateTime.now(),
      dayStartMin: logic.dayStartMin,
    );
    await widget.sync.upsertScheduleBlock(logic.livedTodayYmd, block);
    _start(minutes: 90);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
                const Expanded(child: Text('Combien de temps ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (est != null) Text('estimé ${fmtMin(est)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
              ]),
            ),
            opt(25, 'Un sprint', 'le chrono, rien d\'autre'),
            if (est != null && est != 25 && est != 90) opt(est, 'L\'estimation', 'le chrono sur ≈ ${fmtMin(est)}'),
            opt(90, 'Deep work', 'bloc posé dans le programme à partir de maintenant · badge Deep work', deep: true),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (picked == 90) {
      await _deepWork();
    } else {
      _start(minutes: picked);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text3 = cs.onSurface.withValues(alpha: .55);
    final ctx = widget.project != null
        ? '${widget.project!.title}${widget.task != null ? ' › ${widget.task!.title}' : ''}'
        : widget.ownerActivity?.name;
    final spentBefore = spentByAction(logic.state.sessions)[a.id] ?? 0;
    final stepsDone = a.checklist.where((c) => c.done).length;
    final stepsTotal = a.checklist.length;
    final next = nextChecklistItem(a);
    final r = _running;
    final elapsed = r == null ? Duration.zero : DateTime.now().difference(r.startAt);
    final goalMin = _plannedMin ?? a.estimatedMin;

    final bloc = widget.bloc;
    final String headerLabel = switch (_phase) {
      _Phase.before => bloc != null ? 'FOCUS · ${bloc.activity.name.toUpperCase()}' : 'FOCUS',
      _Phase.running => 'FOCUS · CHRONO',
      _Phase.after => 'FOCUS · TERMINÉ',
    };
    final remaining = bloc?.remainingMin(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(headerLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.3, color: text3)),
              ),
              if (remaining != null)
                Text(remaining > 0 ? 'bloc · reste ${fmtMin(remaining)}' : 'bloc terminé',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: remaining > 0 ? text3 : kPalierAmber))
              else
                const SizedBox(width: 48),
            ]),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 12), children: [
                if (bloc != null && _picking && _phase == _Phase.before) ..._queueList(cs, text3, bloc),
                if (ctx != null)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: kPalierGreen, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(ctx, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .75)))),
                  ]),
                const SizedBox(height: 6),
                Text('${a.title}${_phase == _Phase.after && a.done ? ' ✓' : ''}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 4),
                Text(
                  switch (_phase) {
                    _Phase.before => [
                        if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
                        if (spentBefore > 0) 'déjà ${fmtMin(spentBefore)} passées',
                        if (stepsTotal > 0) '$stepsDone / $stepsTotal étapes',
                      ].join(' · '),
                    _Phase.running => 'en cours depuis ${_hm(r?.startAt)}${goalMin != null ? ' · sur ≈ ${fmtMin(goalMin)}' : ''}',
                    _Phase.after => ctx ?? '',
                  },
                  style: TextStyle(fontSize: 12.5, color: text3),
                ),
                const SizedBox(height: 18),
                if (_phase != _Phase.after) ...[
                  Center(child: _ring(elapsed, goalMin, stepsDone, stepsTotal)),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
                    if (_phase == _Phase.running && widget.chronoActivity != null) _pill('● chrono · ${widget.chronoActivity!.name}', kBrickRunning),
                    for (final c in a.allContexts) _pill(c, text3),
                  ]),
                ],
                if (_phase == _Phase.after) ..._trace(cs, text3, spentBefore, stepsDone, stepsTotal),
                if (_phase != _Phase.after) ...[
                  const SizedBox(height: 18),
                  Text(_phase == _Phase.running && next != null ? 'ÉTAPE EN COURS' : 'ÉTAPES',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
                  const SizedBox(height: 6),
                  if (_phase == _Phase.running && next != null) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: kBrickRunning.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kBrickRunning.withValues(alpha: .5), width: 1.5),
                      ),
                      child: Text(next.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    StepDots(done: stepsDone, total: stepsTotal, allDone: a.done, size: 12),
                    const SizedBox(height: 6),
                    Text(_afterNext(next), style: TextStyle(fontSize: 12, color: text3)),
                  ] else
                    StepsSection(
                      key: ValueKey('focus_steps_${a.id}'),
                      action: a,
                      leftInset: 0,
                      onToggle: (c, v) => _mutate(() => setChecklistItem(a, c.id, v)),
                      onAdd: (t) => _mutate(() => addChecklistItem(a, t)),
                      onRemove: (c) => _mutate(() => removeChecklistItem(a, c.id)),
                      onRename: (c, t) => _mutate(() => renameChecklistItem(a, c.id, t)),
                    ),
                  if (a.note != null && a.note!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('DÉTAIL', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: text3)),
                    const SizedBox(height: 4),
                    Text(a.note!, style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurface.withValues(alpha: .75))),
                  ],
                ],
              ]),
            ),
            ..._bottom(cs, text3, next),
          ]),
        ),
      ),
    );
  }

  Widget _ring(Duration elapsed, int? goalMin, int stepsDone, int stepsTotal) {
    if (_phase == _Phase.running) {
      final v = goalMin == null || goalMin <= 0 ? 0.0 : (elapsed.inSeconds / (goalMin * 60)).clamp(0.0, 1.0);
      return MomentRing(value: v, color: kBrickRunning, big: _mmss(elapsed), small: goalMin == null ? 'EN COURS' : 'SUR ≈ ${fmtMin(goalMin)}', size: 150);
    }
    if (stepsTotal > 0) {
      return MomentRing(value: stepsDone / stepsTotal, color: kPalierGreen, big: '$stepsDone / $stepsTotal', small: 'ÉTAPES', size: 150);
    }
    final spent = spentByAction(logic.state.sessions)[a.id] ?? 0;
    final est = a.estimatedMin;
    return MomentRing(
        value: est == null || est <= 0 ? 0 : (spent / est).clamp(0.0, 1.0),
        color: kPalierGreen,
        big: fmtMin(spent),
        small: est == null ? 'PASSÉES' : 'SUR ≈ ${fmtMin(est)}',
        size: 150);
  }

  List<Widget> _trace(ColorScheme cs, Color text3, int spentBefore, int stepsDone, int stepsTotal) {
    final total = spentBefore; // spentByAction inclut déjà la session qu'on vient de fermer
    final t = widget.task;
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
    final remaining = bloc.remainingMin(DateTime.now());
    final today = DateTime.now();
    return [
      Text('LA FILE DU BLOC · ${open.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: text3)),
      const SizedBox(height: 8),
      for (final i in open)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: i == widget.index ? () => setState(() => _picking = false) : () => _goTo(i, picking: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: i == widget.index ? kBrickRunning : Colors.transparent, width: 1.5),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (bloc.queue[i].context case final c?) Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: text3)),
                    Text(bloc.queue[i].action.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(
                  [
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
    final canChrono = widget.chronoActivity != null;
    final nextIdx = _nextIndex;
    switch (_phase) {
      case _Phase.before:
        return [
          const SizedBox(height: 8),
          if (canChrono && widget.bloc != null)
            primary(_picking ? 'Commencer · ${a.title}' : 'Lancer le chrono', Icons.play_arrow_rounded, () => _start(minutes: a.estimatedMin))
          else if (canChrono)
            primary('Lancer le chrono', Icons.play_arrow_rounded, () => _start(minutes: a.estimatedMin))
          else if (next != null)
            primary('Étape faite', Icons.check_rounded, () => _mutate(() => setChecklistItem(a, next.id, true)))
          else
            primary('Action faite', Icons.check_rounded, () => _mutate(() => setActionDone(a, true))),
          Row(children: [
            if (canChrono) link('Durée · Deep work 90 min', _chooseDuration, color: kPalierAmber),
            const Spacer(),
            if (canChrono) link(next != null ? 'Étape faite' : 'Action faite', () => _mutate(() => next != null ? setChecklistItem(a, next.id, true) : setActionDone(a, true))),
          ]),
        ];
      case _Phase.running:
        return [
          const SizedBox(height: 8),
          if (next != null)
            primary('Étape faite', Icons.check_rounded, () => _mutate(() => setChecklistItem(a, next.id, true)))
          else
            primary('Action faite', Icons.check_rounded, () => _mutate(() => setActionDone(a, true))),
          Row(children: [
            link('Pause', _pause),
            const Spacer(),
            if (next != null) link('Action faite', () => _mutate(() => setActionDone(a, true))),
            if (nextIdx != null) link('Suivante ›', () => _goTo(nextIdx), color: kPalierAmber) else link('Terminer', _finish, color: text3),
          ]),
        ];
      case _Phase.after:
        final t = widget.task;
        final nextAction = t?.actions.where((x) => !x.done && x.id != a.id).firstOrNull;
        return [
          const SizedBox(height: 8),
          if (nextIdx != null)
            primary('Enchaîner · ${widget.bloc!.queue[nextIdx].action.title}', Icons.play_arrow_rounded, () => _goTo(nextIdx))
          else if (nextAction != null && widget.project != null && widget.bloc == null)
            primary('Enchaîner · ${nextAction.title}', Icons.play_arrow_rounded, () {
              Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => _FocusScreen(
                  logic: logic,
                  action: nextAction,
                  project: widget.project,
                  task: t,
                  chronoActivity: widget.chronoActivity,
                  sync: widget.sync,
                ),
              ));
            })
          else
            primary('Fermer', Icons.check_rounded, () => Navigator.of(context).maybePop()),
          if (nextIdx != null || (nextAction != null && widget.bloc == null))
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [link('Fermer', () => Navigator.of(context).maybePop(), color: text3)]),
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

  String _hm(DateTime? d) => d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _mmss(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
