import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';
import 'package:productivitwo_v1/widgets/now_card.dart';

/// Écran « séance en cours » (lot 3 des interventions, 2026-10) : le téléphone
/// en classe ou en formation. L'étape en cours en grand, l'heure prévue lue
/// dans son libellé (« 13h45 Fiche 01 … »), le temps restant du créneau,
/// « Étape suivante » qui coche, la liste complète en dessous, puis
/// « Terminer la séance » → bilan (texte + points à reprendre) poussé dans la
/// prépa de la séance suivante. Les étapes sont la checklist de l'action
/// « Dérouler la séance » : les mêmes que sur le web et via le MCP.
Future<void> showSessionPlayer(
  BuildContext context, {
  required Project project,
  required ProjectIntervention intervention,
  required ProjectTask sessionTask,
  FirestoreSync? sync,
  VoidCallback? onStartTimer,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _SessionPlayerScreen(
      project: project,
      intervention: intervention,
      sessionTask: sessionTask,
      sync: sync ?? FirestoreSync(),
      onStartTimer: onStartTimer,
    ),
  ));
}

/// Action qui porte le déroulé : « Dérouler la séance … », sinon la première
/// action avec des étapes, sinon la première action.
TaskAction? sessionScriptAction(ProjectTask t) =>
    t.actions.where((a) => a.title.toLowerCase().startsWith('dérouler')).firstOrNull ??
    t.actions.where((a) => a.checklist.isNotEmpty).firstOrNull ??
    t.actions.firstOrNull;

/// « 13h45 Fiche 01 » → 13 h 45 en minutes depuis minuit ; null sans heure.
int? stepPlannedMin(String title) {
  final m = RegExp(r'^\s*(\d{1,2})\s?h\s?(\d{0,2})').firstMatch(title);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mm = (m.group(2) ?? '').isEmpty ? 0 : int.parse(m.group(2)!);
  return h > 23 || mm > 59 ? null : h * 60 + mm;
}

/// Libellé d'une étape sans son heure de tête.
String stepLabel(String title) =>
    title.replaceFirst(RegExp(r'^\s*\d{1,2}\s?h\s?\d{0,2}\s*[—–\-:·]?\s*'), '').trim();

class _SessionPlayerScreen extends StatefulWidget {
  final Project project;
  final ProjectIntervention intervention;
  final ProjectTask sessionTask;
  final FirestoreSync sync;
  final VoidCallback? onStartTimer;
  const _SessionPlayerScreen({
    required this.project,
    required this.intervention,
    required this.sessionTask,
    required this.sync,
    this.onStartTimer,
  });

  @override
  State<_SessionPlayerScreen> createState() => _SessionPlayerScreenState();
}

class _SessionPlayerScreenState extends State<_SessionPlayerScreen> {
  Timer? _tick;
  bool _saving = false;
  bool _timerStarted = false;

  Project get p => widget.project;
  ProjectIntervention get i => widget.intervention;
  ProjectTask get task => widget.sessionTask;
  TaskAction? get action => sessionScriptAction(task);
  List<ChecklistItem> get steps => action?.checklist ?? const [];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _save() => widget.sync.saveProjectTasks(p.id, p.tasks);

  int get _nowMin {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  int get _endMin => hmToMin(i.endTime);

  ChecklistItem? get _current => steps.where((c) => !c.done).firstOrNull;
  int get _currentIdx => _current == null ? steps.length : steps.indexOf(_current!);

  /// Heure prévue de la fin de l'étape en cours = heure de la suivante.
  int? get _currentEndMin {
    final idx = _currentIdx;
    for (var k = idx + 1; k < steps.length; k++) {
      final m = stepPlannedMin(steps[k].title);
      if (m != null) return m;
    }
    return _endMin > 0 ? _endMin : null;
  }

  Future<void> _next() async {
    final a = action, c = _current;
    if (a == null || c == null) return;
    HapticFeedback.lightImpact();
    setState(() => setChecklistItem(a, c.id, true));
    await _save();
  }

  Future<void> _previous() async {
    final a = action;
    if (a == null) return;
    final last = steps.lastWhere((c) => c.done, orElse: () => ChecklistItem(title: ''));
    if (last.title.isEmpty && !last.done) return;
    setState(() => setChecklistItem(a, last.id, false));
    await _save();
  }

  Future<void> _toggle(ChecklistItem c) async {
    final a = action;
    if (a == null) return;
    setState(() => setChecklistItem(a, c.id, !c.done));
    await _save();
  }

  Future<void> _addStep() async {
    final a = action;
    if (a == null) return;
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Ajouter une étape'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '14h10 Correction au tableau'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('Ajouter')),
        ],
      ),
    );
    ctrl.dispose();
    if (v == null || v.trim().isEmpty) return;
    setState(() => addChecklistItem(a, v.trim()));
    await _save();
  }

  Future<void> _finish() async {
    final a = action;
    final debrief = await _askDebrief();
    if (debrief == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (a != null) setActionDone(a, true);
      task.status = 'done';
      i.status = 'done';
      i.debriefText = debrief.text.isEmpty ? null : debrief.text;
      i.carryOver = [for (final t in debrief.points) ChecklistItem(title: t)];
      i.debriefAt = DateTime.now();
      final fed = applyCarryOver(p, i, debrief.points);
      await widget.sync.saveProject(p);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fed == null
            ? 'Séance terminée. Bilan enregistré.'
            : 'Séance terminée · ${debrief.points.length} point${debrief.points.length > 1 ? 's' : ''} '
                'à reprendre dans la prépa de « ${fed.title} ».'),
        duration: const Duration(seconds: 4),
      ));
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<({String text, List<String> points})?> _askDebrief() {
    final textCtrl = TextEditingController(text: i.debriefText ?? '');
    final pointCtrl = TextEditingController();
    final points = i.carryOver.map((c) => c.title).toList();
    final skipped = steps.where((c) => !c.done).toList();
    return showModalBottomSheet<({String text, List<String> points})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          void add() {
            final v = pointCtrl.text.trim();
            if (v.isEmpty) return;
            setSt(() {
              points.add(v);
              pointCtrl.clear();
            });
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Bilan de la séance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${interventionDayLabel(i.date)} · ${i.title}',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.55))),
                const SizedBox(height: 14),
                TextField(
                  controller: textCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Comment ça s\'est passé ?',
                    hintText: 'Ce qui a marché, ce qui a coincé, où vous en êtes…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                Text('À REPRENDRE LA PROCHAINE FOIS',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.5))),
                if (skipped.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in skipped)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: Text('Non fait : ${stepLabel(s.title)}', overflow: TextOverflow.ellipsis),
                        onPressed: () => setSt(() {
                          final t = 'Reprendre : ${stepLabel(s.title)}';
                          if (!points.contains(t)) points.add(t);
                        }),
                      ),
                  ]),
                ],
                const SizedBox(height: 6),
                for (var k = 0; k < points.length; k++)
                  Row(children: [
                    const Icon(Icons.subdirectory_arrow_right, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(points[k], style: const TextStyle(fontSize: 14))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setSt(() => points.removeAt(k)),
                    ),
                  ]),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: pointCtrl,
                      decoration: const InputDecoration(hintText: 'Ajouter un point', isDense: true),
                      onSubmitted: (_) => add(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add), onPressed: add),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Plus tard')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      add();
                      Navigator.pop(ctx, (text: textCtrl.text.trim(), points: List<String>.of(points)));
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Terminer la séance'),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    ).whenComplete(() {
      textCtrl.dispose();
      pointCtrl.dispose();
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  String _hm(int min) => '${min ~/ 60}h${(min % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final cs = Theme.of(context).colorScheme;
    final now = _nowMin;
    final total = steps.length, done = steps.where((c) => c.done).length;
    final current = _current;
    final plannedStart = current == null ? null : stepPlannedMin(current.title);
    final plannedEnd = _currentEndMin;
    final late = plannedEnd != null && now > plannedEnd && current != null ? now - plannedEnd : 0;
    final remaining = _endMin > 0 ? _endMin - now : null;
    final place = (i.place ?? '').trim();

    return Scaffold(
      backgroundColor: cs.brightness == Brightness.dark ? pal.surface : cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text(
            '${p.title} · ${hmFr(i.startTime)}–${hmFr(i.endTime)}${place.isNotEmpty ? ' · $place' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.55)),
          ),
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
          // Bandeau : progression + reste du créneau
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              Text(total == 0 ? 'Pas d\'étapes' : 'Étape ${(_currentIdx + 1).clamp(1, total)} / $total',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(.6))),
              const Spacer(),
              if (remaining != null)
                Text(
                  remaining >= 0 ? 'reste ${_fmt(remaining)}' : 'dépassé de ${_fmt(-remaining)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: remaining < 0 ? cs.error : cs.onSurface.withOpacity(.6),
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
            ]),
          ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 6,
                  backgroundColor: cs.onSurface.withOpacity(.08),
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              ),
            ),
          // Étape en cours, en grand
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: current == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline, size: 56, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(total == 0 ? 'Ajoutez les étapes du déroulé.' : 'Toutes les étapes sont faites.',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (plannedStart != null)
                          Text(_hm(plannedStart),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                        if (plannedStart != null && plannedEnd != null)
                          Text(' → ${_hm(plannedEnd)}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.5))),
                        const Spacer(),
                        if (late > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: cs.error.withOpacity(.12), borderRadius: BorderRadius.circular(8)),
                            child: Text('+${_fmt(late)}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.error)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(stepLabel(current.title),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.2)),
                        ),
                      ),
                      if (_currentIdx + 1 < total)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Ensuite : ${stepLabel(steps[_currentIdx + 1].title)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13.5, color: cs.onSurface.withOpacity(.55))),
                        ),
                    ]),
            ),
          ),
          // Commandes
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              OutlinedButton.icon(
                onPressed: done == 0 ? null : _previous,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Précédente'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: current == null ? null : _next,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Étape suivante', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ]),
          ),
          // Liste complète
          Expanded(
            flex: 4,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              children: [
                for (var k = 0; k < steps.length; k++)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      steps[k].done
                          ? Icons.check_circle
                          : k == _currentIdx
                              ? Icons.play_circle_outline
                              : Icons.radio_button_unchecked,
                      size: 20,
                      color: steps[k].done
                          ? cs.primary
                          : k == _currentIdx
                              ? cs.primary
                              : cs.onSurface.withOpacity(.4),
                    ),
                    title: Text(
                      steps[k].title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: k == _currentIdx ? FontWeight.w700 : FontWeight.w500,
                        color: cs.onSurface.withOpacity(steps[k].done ? .45 : .9),
                        decoration: steps[k].done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    onTap: () => _toggle(steps[k]),
                  ),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.add, size: 20, color: cs.primary),
                  title: Text('Ajouter une étape', style: TextStyle(fontSize: 13.5, color: cs.primary)),
                  onTap: _addStep,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _saving ? null : _finish,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Terminer la séance et faire le bilan'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmt(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }
}
