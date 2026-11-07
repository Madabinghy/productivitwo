import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

// Trier les captures en actions, sur le web (2026-11-07, maquette « Web Actions,
// remis en ordre », lot 4) : même geste que la feuille mobile
// (`capture_triage_sheet.dart`) — une capture à la fois, titre retouchable,
// destination projet › tâche (« Au fil de l'eau » = `flowTaskOf`) ou action
// simple d'une activité-temps ; la capture passe `processed` avec la trace.

/// Renvoie le nombre d'actions créées.
Future<int> showCaptureTriageDialog(
  BuildContext context, {
  required FirestoreSync sync,
  required List<CaptureItem> items,
  required List<Project> projects,
  required List<Activity> activities,
}) async {
  final n = await showDesktopDialog<int>(
    context,
    maxWidth: 560,
    builder: (_) => _TriageDialog(sync: sync, items: items, projects: projects, activities: activities),
  );
  return n ?? 0;
}

class _TriageDialog extends StatefulWidget {
  final FirestoreSync sync;
  final List<CaptureItem> items;
  final List<Project> projects;
  final List<Activity> activities;
  const _TriageDialog({required this.sync, required this.items, required this.projects, required this.activities});

  @override
  State<_TriageDialog> createState() => _TriageDialogState();
}

class _TriageDialogState extends State<_TriageDialog> {
  int _i = 0;
  int _created = 0;
  bool _toProject = true;
  String? _projectId;
  String? _taskId;
  String? _activityId;
  final TextEditingController _title = TextEditingController();

  CaptureItem? get _cur => _i < widget.items.length ? widget.items[_i] : null;

  List<Project> get _projects => widget.projects
      .where((p) => p.status == 'active' && !p.paused && !isFolderProject(p, widget.projects))
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  List<Activity> get _timeActivities =>
      widget.activities.where((a) => !a.deleted && a.type == 'time').toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  void initState() {
    super.initState();
    _title.text = _cur?.text ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _next() {
    if (_i + 1 >= widget.items.length) {
      Navigator.pop(context, _created);
      return;
    }
    setState(() {
      _i++;
      _title.text = _cur?.text ?? '';
      _taskId = null;
    });
  }

  bool get _canCreate {
    if (_title.text.trim().isEmpty) return false;
    return _toProject ? _projectId != null : _activityId != null;
  }

  Future<void> _create() async {
    final c = _cur;
    final title = _title.text.trim();
    if (c == null || !_canCreate) return;
    String where;
    if (_toProject) {
      final p = _projects.where((x) => x.id == _projectId).firstOrNull;
      if (p == null) return;
      final t = _taskId == null ? flowTaskOf(p) : p.tasks.firstWhere((x) => x.id == _taskId);
      t.actions.add(TaskAction(title: title, estimatedMin: defaultEstimateFor(title)));
      await widget.sync.saveProjectTasks(p.id, p.tasks);
      where = '${p.title} › ${t.title}';
    } else {
      final a = _timeActivities.where((x) => x.id == _activityId).firstOrNull;
      if (a == null) return;
      await widget.sync.addOwnActionToActivity(a.id, title);
      where = a.name;
    }
    await widget.sync.updateCaptureItem(c.id, {
      'status': 'processed',
      'processedAt': DateTime.now().toIso8601String(),
      'orionNote': '→ action « $title » · $where',
    });
    _created++;
    if (mounted) _next();
  }

  Future<void> _delete() async {
    final c = _cur;
    if (c == null) return;
    await widget.sync.deleteCaptureItem(c.id);
    if (mounted) _next();
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12.5, color: kBText3),
        isDense: true,
        filled: true,
        fillColor: const Color(0x0DFFFFFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  Widget _seg(String label, bool on, VoidCallback onTap, Key key) => InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: on ? kBActive : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? kBPrimary.withOpacity(.4) : kBLine),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? kBText : kBText2)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _cur;
    if (c == null) return const SizedBox.shrink();
    final project = _projects.where((p) => p.id == _projectId).firstOrNull;
    final tasks = project == null
        ? const <ProjectTask>[]
        : project.tasks
            .where((t) => t.id != kFlowTaskId && t.status != 'done' && t.status != 'skipped' && !t.isMilestone)
            .toList();
    return Container(
      color: kBSurface,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Trier les captures · ${_i + 1} / ${widget.items.length}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kBText)),
          ),
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18, color: kBText3),
            onPressed: () => Navigator.pop(context, _created),
          ),
        ]),
        const SizedBox(height: 4),
        Text('« ${c.text} »', style: const TextStyle(fontSize: 13, color: kBText3, fontStyle: FontStyle.italic)),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('triage-title'),
          controller: _title,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14, color: kBText),
          decoration: _deco('Titre de l’action · verbe + objet'),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _seg('Dans un projet', _toProject, () => setState(() => _toProject = true), const ValueKey('triage-to-project')),
          const SizedBox(width: 8),
          _seg('Action simple', !_toProject, () => setState(() => _toProject = false), const ValueKey('triage-to-activity')),
        ]),
        const SizedBox(height: 12),
        if (_toProject) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('triage-project'),
            value: _projectId,
            isExpanded: true,
            dropdownColor: kBSurface,
            decoration: _deco('Projet'),
            style: const TextStyle(fontSize: 13.5, color: kBText),
            items: [for (final p in _projects) DropdownMenuItem(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              _projectId = v;
              _taskId = null;
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            key: ValueKey('triage-task-$_projectId'),
            value: _taskId,
            isExpanded: true,
            dropdownColor: kBSurface,
            decoration: _deco('Tâche'),
            style: const TextStyle(fontSize: 13.5, color: kBText),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Au fil de l’eau')),
              for (final t in tasks) DropdownMenuItem<String?>(value: t.id, child: Text(t.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: project == null ? null : (v) => setState(() => _taskId = v),
          ),
        ] else
          DropdownButtonFormField<String>(
            key: const ValueKey('triage-activity'),
            value: _activityId,
            isExpanded: true,
            dropdownColor: kBSurface,
            decoration: _deco('Activité'),
            style: const TextStyle(fontSize: 13.5, color: kBText),
            items: [for (final a in _timeActivities) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _activityId = v),
          ),
        const SizedBox(height: 18),
        Row(children: [
          TextButton(
            key: const ValueKey('triage-delete'),
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: kBText3),
            child: const Text('Supprimer'),
          ),
          TextButton(
            key: const ValueKey('triage-skip'),
            onPressed: _next,
            style: TextButton.styleFrom(foregroundColor: kBText2),
            child: const Text('Passer'),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('triage-create'),
            onPressed: _canCreate ? _create : null,
            style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg, shape: const StadiumBorder()),
            child: const Text('Créer l’action'),
          ),
        ]),
      ]),
    );
  }
}
