import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';

/// Trier les captures de la boîte d'entrée en actions, sans attendre ORION ni
/// la revue hebdo (onglet Actions, 2026-10) : une capture à la fois, titre
/// retouchable, destination = une tâche d'un projet (« Au fil de l'eau » par
/// défaut) ou une activité-temps (action simple). Créer = l'action naît comme
/// depuis « Prochaine action » / « Action simple », la capture passe
/// `processed` avec la trace « → action … » ; Supprimer ; Passer.
Future<void> showCaptureTriageSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required List<CaptureItem> items,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _TriageSheet(logic: logic, sync: sync, items: List.of(items), onChanged: onChanged),
  );
}

class _TriageSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final List<CaptureItem> items;
  final VoidCallback? onChanged;
  const _TriageSheet({required this.logic, required this.sync, required this.items, this.onChanged});

  @override
  State<_TriageSheet> createState() => _TriageSheetState();
}

class _TriageSheetState extends State<_TriageSheet> {
  int _i = 0;
  int _created = 0;
  final _title = TextEditingController();
  bool _toProject = true;
  String? _projectId;
  String? _taskId; // null = « Au fil de l'eau »
  String? _activityId;

  CaptureItem? get _cur => _i < widget.items.length ? widget.items[_i] : null;

  List<Project> get _projects => widget.logic.currentProjects
      .where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, widget.logic.currentProjects))
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  List<Activity> get _timeActivities =>
      widget.logic.state.activeActivities.where((a) => a.type == 'time').toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final c = _cur;
    _title.text = c?.text ?? '';
    _taskId = null;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _next() {
    if (_i + 1 >= widget.items.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _i++;
      _load();
    });
  }

  Future<void> _create() async {
    final c = _cur;
    final title = _title.text.trim();
    if (c == null || title.isEmpty) return;
    String where;
    if (_toProject) {
      final p = _projects.firstWhereOrNull((x) => x.id == _projectId);
      if (p == null) return;
      final t = _taskId == null ? flowTaskOf(p) : p.tasks.firstWhere((x) => x.id == _taskId);
      t.actions.add(TaskAction(title: title, estimatedMin: defaultEstimateFor(title)));
      // Optimiste, comme « Prochaine action » : l'écriture part, l'UI suit.
      unawaited(widget.sync.saveProjectTasks(p.id, p.tasks));
      where = '${p.title} › ${t.title}';
    } else {
      final a = _timeActivities.firstWhereOrNull((x) => x.id == _activityId);
      if (a == null) return;
      unawaited(widget.sync.addOwnActionToActivity(a.id, title));
      a.ownActions.add(TaskAction(title: title, linkedActivityId: a.id, estimatedMin: defaultEstimateFor(title)));
      where = a.name;
    }
    widget.logic.onChange();
    unawaited(widget.sync.updateCaptureItem(c.id, {
      'status': 'processed',
      'processedAt': DateTime.now().toIso8601String(),
      'orionNote': '→ action « $title » · $where',
    }));
    _created++;
    widget.onChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text('Action créée · $where'), duration: const Duration(seconds: 2)));
    _next();
  }

  Future<void> _delete() async {
    final c = _cur;
    if (c == null) return;
    unawaited(widget.sync.deleteCaptureItem(c.id));
    widget.onChanged?.call();
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _cur;
    if (c == null) return const SizedBox.shrink();
    final projects = _projects;
    final project = projects.firstWhereOrNull((p) => p.id == _projectId);
    final openTasks = project == null
        ? const <ProjectTask>[]
        : project.tasks
            .where((t) => t.id != kFlowTaskId && !t.isMilestone && t.status != 'done' && t.status != 'skipped')
            .toList();
    final acts = _timeActivities;
    final domains = widget.logic.state.activeDomains;
    final canCreate = _title.text.trim().isNotEmpty && (_toProject ? _projectId != null : _activityId != null);
    Text label(String t) => Text(t,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurface.withOpacity(.45)));
    Widget chip(String text, bool on, VoidCallback onTap) => ChoiceChip(
          selected: on,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          visualDensity: VisualDensity.compact,
        );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber.shade600),
          const SizedBox(width: 8),
          const Expanded(child: Text('Trier une capture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          Text('${_i + 1} / ${widget.items.length}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(.45))),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Action', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Dans un projet'), icon: Icon(Icons.folder_outlined, size: 16)),
                ButtonSegment(value: false, label: Text('Action simple'), icon: Icon(Icons.flash_on_outlined, size: 16)),
              ],
              selected: {_toProject},
              onSelectionChanged: (s) => setState(() => _toProject = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (_toProject) ...[
          label('PROJET'),
          const SizedBox(height: 6),
          if (projects.isEmpty)
            Text('Aucun projet actif.', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5)))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in projects)
                chip(p.title, _projectId == p.id, () => setState(() {
                      _projectId = p.id;
                      _taskId = null;
                    })),
            ]),
          if (project != null) ...[
            const SizedBox(height: 12),
            label('TÂCHE'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              chip('Au fil de l\'eau', _taskId == null, () => setState(() => _taskId = null)),
              for (final t in openTasks) chip(t.title, _taskId == t.id, () => setState(() => _taskId = t.id)),
            ]),
          ],
        ] else ...[
          label('SUR L\'ACTIVITÉ'),
          const SizedBox(height: 6),
          if (acts.isEmpty)
            Text('Aucune activité-temps.', style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.5)))
          else
            for (final g in groupActivitiesByDomain(acts, domains)) ...[
              ActivityDomainHeader(name: g.name, color: g.color, padding: const EdgeInsets.only(top: 8, bottom: 4)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in g.activities) chip(a.name, _activityId == a.id, () => setState(() => _activityId = a.id)),
              ]),
            ],
        ],
        const SizedBox(height: 18),
        Row(children: [
          IconButton(
            tooltip: 'Supprimer la capture',
            icon: Icon(Icons.delete_outline, color: cs.error),
            onPressed: _delete,
          ),
          TextButton(onPressed: _next, child: Text(_i + 1 >= widget.items.length ? 'Fermer' : 'Passer')),
          const Spacer(),
          FilledButton.icon(
            onPressed: canCreate ? _create : null,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Créer l\'action'),
          ),
        ]),
        if (_created > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('$_created action${_created > 1 ? 's' : ''} créée${_created > 1 ? 's' : ''} dans ce tri',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.45))),
          ),
      ]),
    );
  }
}
