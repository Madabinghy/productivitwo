import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_work.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin;
import 'package:productivitwo_v1/widgets/steps_section.dart';

/// Écran « bloc » (2026-10) : toucher un bloc de tâche dans Aujourd'hui ouvre
/// ce qu'il y a à FAIRE, pas la fiche du projet. L'action visée (sinon la
/// première ouverte) en avant avec ses étapes cochables, les autres actions
/// repliées, les faites à part. Même modèle que partout (checklist des
/// actions) : ce qui se coche ici se retrouve sur le web et via le MCP.
Future<void> showBlockWorkScreen(
  BuildContext context, {
  required Project project,
  required ProjectTask task,
  required ScheduleBlock block,
  required bool isToday,
  FirestoreSync? sync,
  VoidCallback? onStartTimer,
  VoidCallback? onOpenTask,
  Future<void> Function()? onBlockDone,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _BlockWorkScreen(
      project: project,
      task: task,
      block: block,
      isToday: isToday,
      sync: sync ?? FirestoreSync(),
      onStartTimer: onStartTimer,
      onOpenTask: onOpenTask,
      onBlockDone: onBlockDone,
    ),
  ));
}

class _BlockWorkScreen extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final ScheduleBlock block;
  final bool isToday;
  final FirestoreSync sync;
  final VoidCallback? onStartTimer;
  final VoidCallback? onOpenTask;
  final Future<void> Function()? onBlockDone;
  const _BlockWorkScreen({
    required this.project,
    required this.task,
    required this.block,
    required this.isToday,
    required this.sync,
    this.onStartTimer,
    this.onOpenTask,
    this.onBlockDone,
  });

  @override
  State<_BlockWorkScreen> createState() => _BlockWorkScreenState();
}

class _BlockWorkScreenState extends State<_BlockWorkScreen> {
  Timer? _tick;
  String? _focusId;
  bool _timerStarted = false;
  bool _showDone = false;
  final _newAction = TextEditingController();

  ProjectTask get task => widget.task;

  @override
  void initState() {
    super.initState();
    _focusId = widget.block.actionId;
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _newAction.dispose();
    super.dispose();
  }

  Future<void> _save() => widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);

  Future<void> _mutate(void Function() f) async {
    setState(f);
    await _save();
  }

  String _fmt(int min) => min >= 60 ? '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}' : '$min min';

  String _hm(int min) => '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

  Widget _steps(TaskAction a) => StepsSection(
        key: ValueKey('bw_steps_${a.id}'),
        action: a,
        leftInset: 0,
        onToggle: (c, v) => _mutate(() => setChecklistItem(a, c.id, v)),
        onAdd: (t) => _mutate(() => addChecklistItem(a, t)),
        onRemove: (c) => _mutate(() => removeChecklistItem(a, c.id)),
        onRename: (c, t) => _mutate(() => renameChecklistItem(a, c.id, t)),
      );

  Widget _actionRow(ColorScheme cs, TaskAction a, {required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(children: [
            IconButton(
              tooltip: a.done ? 'Rouvrir' : 'Marquer faite',
              icon: Icon(a.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: a.done ? Colors.green : cs.onSurface.withOpacity(.4)),
              onPressed: () => _mutate(() => setActionDone(a, !a.done)),
            ),
            Expanded(
              child: Text(a.title,
                  style: TextStyle(
                      fontSize: 14.5,
                      color: a.done ? cs.onSurface.withOpacity(.45) : cs.onSurface,
                      decoration: a.done ? TextDecoration.lineThrough : null)),
            ),
            if (a.checklist.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text('${a.checklist.where((c) => c.done).length}/${a.checklist.length}',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
              ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurface.withOpacity(.3)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = widget.block;
    final w = blockWork(task, _focusId);
    final focus = w.focus;
    final n = DateTime.now();
    final nowMin = n.hour * 60 + n.minute;
    final start = blockStartMin(b), end = blockEndMin(b);
    final live = widget.isToday && start <= nowMin && nowMin < end;
    final stepsDone = focus?.checklist.where((c) => c.done).length ?? 0;
    final stepsTotal = focus?.checklist.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text('${widget.project.title} · ${_hm(start)}–${_hm(end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
        ]),
        actions: [
          if (widget.onStartTimer != null && !_timerStarted)
            IconButton(
              tooltip: 'Lancer le chrono',
              icon: const Icon(Icons.timer_outlined),
              onPressed: () {
                widget.onStartTimer!();
                setState(() => _timerStarted = true);
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (live)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(children: [
                Container(
                    width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('En cours', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.primary)),
                const Spacer(),
                Text('reste ${_fmt(end - nowMin)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.6),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              if (focus == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                      task.actions.isEmpty
                          ? 'Pas encore d\'action pour cette tâche. Écris la prochaine chose concrète à faire.'
                          : 'Toutes les actions de cette tâche sont faites.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(.6))),
                ),
                TextField(
                  controller: _newAction,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                      hintText: 'Nouvelle action…', border: OutlineInputBorder(), isDense: true),
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isEmpty) return;
                    _newAction.clear();
                    _mutate(() => task.actions.add(TaskAction(title: t, estimatedMin: defaultEstimateFor(t))));
                  },
                ),
              ] else ...[
                // L'action en avant : titre en grand, ses étapes cochables.
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(focus.title,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                decoration: focus.done ? TextDecoration.lineThrough : null,
                                color: focus.done ? cs.onSurface.withOpacity(.5) : cs.onSurface)),
                      ),
                      IconButton(
                        tooltip: focus.done ? 'Rouvrir l\'action' : 'Action faite',
                        icon: Icon(focus.done ? Icons.check_circle_rounded : Icons.check_circle_outline,
                            size: 28, color: focus.done ? Colors.green : cs.primary),
                        onPressed: () => _mutate(() => setActionDone(focus, !focus.done)),
                      ),
                    ]),
                    if (stepsTotal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: Row(children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: stepsDone / stepsTotal,
                                minHeight: 5,
                                backgroundColor: cs.onSurface.withOpacity(.08),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('$stepsDone / $stepsTotal',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(.6))),
                        ]),
                      ),
                    _steps(focus),
                  ]),
                ),
                if (w.open.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
                    child: Text('ENSUITE DANS CETTE TÂCHE',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1,
                            color: cs.onSurface.withOpacity(.45))),
                  ),
                  for (final a in w.open) _actionRow(cs, a, onTap: () => setState(() => _focusId = a.id)),
                ],
              ],
              if (w.done.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showDone = !_showDone),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Row(children: [
                      Icon(_showDone ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: cs.onSurface.withOpacity(.45)),
                      const SizedBox(width: 6),
                      Text('${w.done.length} faite${w.done.length > 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.5))),
                    ]),
                  ),
                ),
                if (_showDone)
                  for (final a in w.done) _actionRow(cs, a, onTap: () => setState(() => _focusId = a.id)),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(children: [
              if (widget.onOpenTask != null)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onOpenTask!();
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Voir la tâche'),
                ),
              const SizedBox(width: 10),
              if (widget.onBlockDone != null && b.status == 'pending')
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await widget.onBlockDone!();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Bloc terminé', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
