import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/claude_link.dart';
import 'package:productivitwo_v1/utils/focus_context.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/widgets/now_card.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/widgets/renegotiate_sheet.dart';
import 'package:productivitwo_v1/widgets/ring_painter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Écran Focus mobile (maquette Focus action, cadre 3) : s'ouvre depuis la
/// carte MAINTENANT quand un chrono tourne, par-dessus Aujourd'hui, et se
/// referme en tirant vers le bas. Chrono en grand, étapes à cocher, contexte
/// replié, Terminé / Pas fini / Pause / Réorganiser avec Claude.
Future<void> showFocusScreen(
  BuildContext context, {
  required AppLogic logic,
  required List<ScheduleBlock> blocks,
  required String date,
  required VoidCallback onStopTimer,
  void Function(ScheduleBlock block)? onLaunch,
  void Function(ScheduleBlock block)? onOpenSource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(
      heightFactor: .96,
      child: _FocusScreen(
        logic: logic,
        blocks: blocks,
        date: date,
        onStopTimer: onStopTimer,
        onLaunch: onLaunch,
        onOpenSource: onOpenSource,
      ),
    ),
  );
}

class _FocusScreen extends StatefulWidget {
  final AppLogic logic;
  final List<ScheduleBlock> blocks;
  final String date;
  final VoidCallback onStopTimer;
  final void Function(ScheduleBlock block)? onLaunch;
  final void Function(ScheduleBlock block)? onOpenSource;
  const _FocusScreen({
    required this.logic,
    required this.blocks,
    required this.date,
    required this.onStopTimer,
    this.onLaunch,
    this.onOpenSource,
  });

  @override
  State<_FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<_FocusScreen> {
  final _sync = FirestoreSync();
  Timer? _tick;
  bool _ctxOpen = false;
  List<StrategicObjective> _objectives = const [];
  List<Map<String, dynamic>> _docs = const [];
  String? _docsKey;

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _sync.fetchStrategicObjectives().then((o) {
      if (mounted) setState(() => _objectives = o);
    });
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    _tick?.cancel();
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  // ── Données ───────────────────────────────────────────────────────────────

  Session? get _open {
    Session? last;
    for (final s in logic.state.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  ScheduleBlock? get _currentBlock {
    final n = DateTime.now();
    final f = focusBlock(widget.blocks, n.hour * 60 + n.minute);
    return f != null && f.current ? f.block : null;
  }

  void _loadDocs(FocusTarget t) {
    final key = '${t.project.id}/${t.task.id}';
    if (_docsKey == key) return;
    _docsKey = key;
    _sync.fetchDocuments(projectId: t.project.id).then((all) {
      if (!mounted || _docsKey != key) return;
      final docs = all.where((d) => (d['category'] as String?) != 'playbook').toList();
      setState(() => _docs = focusDocuments(docs, t.task.id));
    });
  }

  String _clock(int min) =>
      '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  String _elapsed(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  String _fmtMin(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  String _date(DateTime d) {
    const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _saveProject(Project p) async {
    logic.onChange();
    await _sync.saveProjectTasks(p.id, p.tasks);
  }

  Future<void> _saveOwn(Activity a) async {
    logic.onChange();
    await _sync.updateOwnActions(a.id, a.ownActions);
  }

  void _toggleItem(TaskAction a, ChecklistItem c, bool v, Future<void> Function() save) {
    HapticFeedback.lightImpact();
    final changed = setChecklistItem(a, c.id, v);
    setState(() {});
    save();
    if (changed && a.done && mounted) _snack('Action faite : ${a.title}');
  }

  void _toggleAction(TaskAction a, bool v, Future<void> Function() save) {
    HapticFeedback.lightImpact();
    a.done = v;
    a.doneAt = v ? DateTime.now() : null;
    if (v) {
      for (final c in a.checklist) {
        c.done = true;
        c.doneAt ??= a.doneAt;
      }
    }
    setState(() {});
    save();
  }

  Future<void> _addStep(TaskAction a, Future<void> Function() save) async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nouvelle étape'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ex. : relire la page 1'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Ajouter')),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    if (addChecklistItem(a, title.trim()) == null) return;
    setState(() {});
    await save();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));

  /// « Terminé » : l'action est faite, le chrono s'arrête, le bloc passe à fait.
  Future<void> _finish({TaskAction? action, Future<void> Function()? save, ScheduleBlock? block}) async {
    HapticFeedback.mediumImpact();
    if (action != null && !action.done && save != null) _toggleAction(action, true, save);
    widget.onStopTimer();
    if (block != null && block.status != 'done') {
      block.status = 'done';
      await _sync.updateBlockStatus(widget.date, block.id, 'done');
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// « Pas fini, décaler » : le chrono s'arrête, la feuille de renégociation
  /// propose les créneaux ; sans bloc, simple arrêt.
  Future<void> _notDone(ScheduleBlock? block) async {
    widget.onStopTimer();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (block == null) return;
    // La feuille s'ouvre sur Aujourd'hui, une fois le Focus refermé.
    final ctx = context;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!ctx.mounted) return;
    await showRenegotiateSheet(ctx,
        logic: logic, block: block, date: widget.date, onLaunch: widget.onLaunch);
  }

  Future<void> _claude(ScheduleBlock block, String activityName) async {
    final prompt = reorganizeAfterAsidePrompt(
        date: widget.date,
        now: DateTime.now(),
        block: block,
        activityName: activityName,
        todayBlocks: widget.blocks);
    await launchUrl(claudeNewUri(prompt), mode: LaunchMode.externalApplication);
  }

  // ── Rendu ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final open = _open;
    if (open == null) {
      // Chrono arrêté ailleurs (widget, autre appareil) : l'écran se referme.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final block = _currentBlock;
    final running = logic.runningActivity();
    final target = resolveFocusTarget(
        open: open, currentBlock: block, projects: logic.currentProjects);
    final own = target == null
        ? resolveOwnActionTarget(open: open, activities: logic.state.activities)
        : null;
    if (target != null) _loadDocs(target);
    // Bloc à l'origine du chrono (cible projet) ou bloc courant qui matche.
    final b = target?.block ??
        (block != null &&
                sessionMatchesBlock(open, block,
                    activityLinkedActivityId: running?.linkedActivityId)
            ? block
            : null);

    final elapsed = now.difference(open.startAt);
    final total = b?.durationMin ?? 0;
    final progress = total > 0 ? (elapsed.inSeconds / (total * 60)).clamp(0.0, 1.0) : 0.0;

    // Titre / fil.
    final String title;
    String? crumb;
    if (target != null) {
      title = target.action.title;
      crumb = [target.project.title, if (target.phase != null) target.phase!.label, target.task.title]
          .join(' › ');
    } else if (own != null) {
      title = own.action.title;
      crumb = own.activity.name;
    } else {
      title = b?.title ?? running?.name ?? 'Chrono libre';
      crumb = running != null && b != null && b.title != running.name ? running.name : null;
    }

    final sub = b != null
        ? 'sur ${_fmtMin(b.durationMin)} · fin ${_clock(blockEndMin(b))}'
        : 'depuis ${_clock(open.startAt.hour * 60 + open.startAt.minute)}';

    return Column(children: [
      // Barre : ⌄  FOCUS  ⋯
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Row(children: [
          IconButton(
              tooltip: 'Fermer',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: pal.text2)),
          const Spacer(),
          Text('FOCUS',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
          const Spacer(),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: pal.text2),
            onSelected: (v) {
              switch (v) {
                case 'source':
                  if (b != null) widget.onOpenSource?.call(b);
                case 'claude':
                  if (b != null) _claude(b, running?.name ?? title);
              }
            },
            itemBuilder: (_) => [
              if (b != null && widget.onOpenSource != null)
                const PopupMenuItem(value: 'source', child: Text('Voir la source')),
              if (b != null)
                const PopupMenuItem(value: 'claude', child: Text('Réorganiser la suite avec Claude')),
            ],
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            // Héros
            if (crumb != null)
              Text(crumb,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text3)),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, color: pal.text)),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 168,
                height: 168,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: const Size(168, 168),
                    painter: RingPainter(
                        progress: progress,
                        color: pal.primary,
                        stroke: 11,
                        trackColor: pal.track,
                        cap: StrokeCap.round),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_elapsed(elapsed),
                        style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: pal.text,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    Text(sub, style: TextStyle(fontSize: 12, color: pal.text3)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            ..._meta(pal, target, own),
            const SizedBox(height: 16),
            // Étapes
            if (target != null)
              _stepsCard(pal, target)
            else if (own != null)
              _ownCard(pal, own)
            else
              _routineOrFree(pal, running, b),
            const SizedBox(height: 12),
            if (target != null) _contextFold(pal, target, open),
          ],
        ),
      ),
      // Barre du bas
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: pal.surface,
          border: Border(top: BorderSide(color: pal.track)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: _btn(pal, 'Pas fini, décaler', onTap: () => _notDone(b))),
            const SizedBox(width: 10),
            Expanded(
              child: _btn(pal, 'Terminé', primary: true, onTap: () {
                if (target != null) {
                  _finish(action: target.action, save: () => _saveProject(target.project), block: b);
                } else if (own != null) {
                  _finish(action: own.action, save: () => _saveOwn(own.activity), block: b);
                } else {
                  _finish(block: b);
                }
              }),
            ),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: () {
                widget.onStopTimer();
                Navigator.of(context).pop();
              },
              child: Text('Pause', style: TextStyle(color: pal.text3, fontWeight: FontWeight.w700)),
            ),
            if (b != null)
              TextButton.icon(
                onPressed: () => _claude(b, running?.name ?? title),
                icon: Icon(Icons.auto_awesome, size: 16, color: pal.text3),
                label: Text('Réorganiser avec Claude',
                    style: TextStyle(color: pal.text3, fontWeight: FontWeight.w700)),
              ),
          ]),
        ]),
      ),
    ]);
  }

  List<Widget> _meta(NowPalette pal, FocusTarget? t, ({Activity activity, TaskAction action})? own) {
    final items = <String>[];
    if (t != null) {
      final next = t.stepsAreTaskActions
          ? taskSteps(t.task).where((a) => !a.done && a.id != t.action.id).firstOrNull?.title
          : t.action.checklist.where((c) => !c.done).firstOrNull?.title;
      if (next != null) items.add('Prochaine étape · $next');
      if (t.task.endDate != null) items.add('Échéance · ${_date(t.task.endDate!)}');
    } else if (own != null) {
      final next = own.action.checklist.where((c) => !c.done).firstOrNull?.title;
      if (next != null) items.add('Prochaine étape · $next');
    }
    if (items.isEmpty) return const [];
    return [
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final s in items)
            Text(s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: pal.text3)),
        ],
      ),
    ];
  }

  // ── Étapes ────────────────────────────────────────────────────────────────

  Widget _card(NowPalette pal, {required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.track),
        ),
        child: child,
      );

  Widget _label(NowPalette pal, String text, {String? trailing}) => Row(children: [
        Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: pal.text3)),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: pal.text4,
                  fontFeatures: const [FontFeature.tabularFigures()])),
      ]);

  Widget _stepsCard(NowPalette pal, FocusTarget t) {
    Future<void> save() => _saveProject(t.project);
    if (t.stepsAreTaskActions) {
      final list = taskSteps(t.task);
      final done = list.where((a) => a.done).length;
      return _card(pal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label(pal, 'ÉTAPES', trailing: '$done / ${list.length} · actions de la tâche'),
            const SizedBox(height: 4),
            for (final a in list)
              _row(pal, a.title, a.done,
                  current: a.id == t.action.id, onTap: () => _toggleAction(a, !a.done, save)),
          ]));
    }
    final a = t.action;
    return _card(pal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label(pal, 'ÉTAPES',
              trailing: a.checklist.isEmpty ? null : '${a.checklistDone} / ${a.checklistTotal}'),
          const SizedBox(height: 4),
          if (a.checklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Pas encore d\'étapes. Découpe l\'action en 2 ou 3 pas.',
                  style: TextStyle(fontSize: 13, color: pal.text3)),
            ),
          for (var i = 0; i < a.checklist.length; i++)
            _row(pal, a.checklist[i].title, a.checklist[i].done,
                current: !a.checklist[i].done &&
                    a.checklist.take(i).every((c) => c.done),
                onTap: () => _toggleItem(a, a.checklist[i], !a.checklist[i].done, save)),
          _addRow(pal, () => _addStep(a, save)),
        ]));
  }

  Widget _ownCard(NowPalette pal, ({Activity activity, TaskAction action}) own) {
    final a = own.action;
    Future<void> save() => _saveOwn(own.activity);
    return _card(pal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label(pal, 'ÉTAPES',
              trailing: a.checklist.isEmpty ? null : '${a.checklistDone} / ${a.checklistTotal}'),
          const SizedBox(height: 4),
          if (a.checklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Pas encore d\'étapes. Découpe l\'action en 2 ou 3 pas.',
                  style: TextStyle(fontSize: 13, color: pal.text3)),
            ),
          for (var i = 0; i < a.checklist.length; i++)
            _row(pal, a.checklist[i].title, a.checklist[i].done,
                current: !a.checklist[i].done && a.checklist.take(i).every((c) => c.done),
                onTap: () => _toggleItem(a, a.checklist[i], !a.checklist[i].done, save)),
          _addRow(pal, () => _addStep(a, save)),
        ]));
  }

  /// Bloc routine : objectif du jour et série ; chrono libre : rien à cocher.
  Widget _routineOrFree(NowPalette pal, Activity? running, ScheduleBlock? b) {
    Activity? act = running;
    if (b?.activityId != null) {
      act = logic.state.activities.where((x) => x.id == b!.activityId).firstOrNull ?? act;
    }
    if (act != null && act.isHabit) {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final tgt = logic.activeHabitTarget(act);
      final val = logic.habitValueOn(act.id, day);
      final streak = logic.habitCurrentStreak(act.id);
      return _card(pal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _label(pal, 'ROUTINE'),
            const SizedBox(height: 8),
            Text(tgt > 0 ? 'Aujourd\'hui : $val / $tgt' : 'Aujourd\'hui : $val',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
            if (streak > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Série : $streak jour${streak > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 13, color: pal.text3)),
              ),
            const SizedBox(height: 6),
          ]));
    }
    return _card(pal,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('Aucune étape rattachée à ce chrono.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: pal.text3)),
        ));
  }

  Widget _row(NowPalette pal, String title, bool done,
      {required bool current, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(minHeight: 46),
        decoration: BoxDecoration(
          color: current ? pal.primary.withOpacity(.08) : null,
          borderRadius: BorderRadius.circular(10),
          border: current ? Border.all(color: pal.primary.withOpacity(.35)) : null,
        ),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 22, color: done ? pal.primary : pal.text4),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 14.5,
                    color: done ? pal.text4 : pal.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: pal.text4)),
          ),
        ]),
      ),
    );
  }

  Widget _addRow(NowPalette pal, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: [
            const SizedBox(width: 8),
            Icon(Icons.add_circle_outline, size: 22, color: pal.text4),
            const SizedBox(width: 10),
            Text('Ajouter une étape', style: TextStyle(fontSize: 14, color: pal.text3)),
          ]),
        ),
      );

  // ── Contexte (replié) ─────────────────────────────────────────────────────

  Widget _contextFold(NowPalette pal, FocusTarget t, Session open) {
    final spec = taskSpecLines(t.task);
    final desc = t.task.description?.trim();
    StrategicObjective? obj;
    for (final o in _objectives) {
      if (o.id == t.project.strategicObjectiveId) obj = o;
    }
    final last = lastSessionOn(logic.state.sessions, taskId: t.task.id, exceptId: open.id);
    final b = t.block;
    final next = b != null ? nextBlockAfter(widget.blocks, b) : null;
    final nextStep = nextStepAfter(t.task, t.action);
    final summary = <String>[
      if (obj != null) 'objectif',
      if (spec.isNotEmpty) 'consignes' else if (desc != null && desc.isNotEmpty) 'description',
      if (_docs.isNotEmpty) '${_docs.length} document${_docs.length > 1 ? 's' : ''}',
      if (last != null) 'dernière session ${_date(last.startAt)}',
    ];

    return _card(pal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _ctxOpen = !_ctxOpen),
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Contexte',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text2)),
                  if (summary.isNotEmpty)
                    Text(summary.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: pal.text4)),
                ]),
              ),
              Icon(_ctxOpen ? Icons.expand_less : Icons.chevron_right, color: pal.text4),
            ]),
          ),
          if (_ctxOpen) ...[
            const SizedBox(height: 10),
            if (obj != null || t.task.endDate != null || b != null)
              _kv(pal, 'POURQUOI', Text(
                [
                  if (obj != null) 'Objectif « ${obj.title} »',
                  if (t.task.endDate != null) 'échéance ${_date(t.task.endDate!)}',
                  if (b != null) 'bloc jusqu\'à ${_clock(blockEndMin(b))}',
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: pal.text2, height: 1.4),
              )),
            if (spec.isNotEmpty)
              _kv(pal, 'CONSIGNES DE LA TÂCHE', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in spec)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${l.label} · ', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text3)),
                      TextSpan(text: l.text),
                    ]), style: TextStyle(fontSize: 13, color: pal.text2, height: 1.4)),
                  ),
              ]))
            else if (desc != null && desc.isNotEmpty)
              _kv(pal, 'DESCRIPTION',
                  Text(desc, style: TextStyle(fontSize: 13, color: pal.text2, height: 1.4))),
            if (_docs.isNotEmpty)
              _kv(pal, 'DOCUMENTS LIÉS', Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final d in _docs)
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocViewer(
                            title: (d['title'] as String?) ?? 'Document',
                            html: (d['content'] as String?) ?? ''),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Row(children: [
                        Icon(Icons.description_outlined, size: 18, color: pal.text3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text((d['title'] as String?) ?? 'Document',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: pal.text)),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: pal.text4),
                      ]),
                    ),
                  ),
              ])),
            if (last != null)
              _kv(pal, 'DERNIÈRE FOIS', Text(
                '${_date(last.startAt)} · ${_fmtMin(last.endAt!.difference(last.startAt).inMinutes)}',
                style: TextStyle(fontSize: 13, color: pal.text2),
              )),
            if (next != null || nextStep != null)
              _kv(pal, 'ENSUITE', Text(
                next != null ? '${next.title} · ${_clock(blockStartMin(next))}' : '${nextStep!.title} · même tâche',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: pal.text2),
              )),
            if (widget.onOpenSource != null && b != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => widget.onOpenSource!(b),
                  child: const Text('Ouvrir la fiche projet'),
                ),
              ),
          ],
        ]));
  }

  Widget _kv(NowPalette pal, String k, Widget v) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: pal.text4)),
          const SizedBox(height: 4),
          v,
        ]),
      );

  Widget _btn(NowPalette pal, String label, {bool primary = false, required VoidCallback onTap}) =>
      SizedBox(
        height: 48,
        child: Material(
          color: primary ? pal.primary : pal.chip,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: primary ? pal.onPrimary : pal.text)),
            ),
          ),
        ),
      );
}
