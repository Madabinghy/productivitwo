import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

/// Ouvre le detail sheet d'une tâche Gantt depuis le plan du jour.
Future<void> showGanttTaskSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required String projectId,
  required String taskId,
}) async {
  // Chargement du projet à la demande
  final projects = await sync.fetchProjects();
  if (!context.mounted) return;

  final project = projects.where((p) => p.id == projectId).firstOrNull;
  if (project == null) return;

  final task = project.tasks.where((t) => t.id == taskId).firstOrNull;
  if (task == null) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GanttTaskSheet(
      logic: logic,
      sync: sync,
      project: project,
      task: task,
    ),
  );
}

class _GanttTaskSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final Project project;
  final ProjectTask task;

  const _GanttTaskSheet({
    required this.logic,
    required this.sync,
    required this.project,
    required this.task,
  });

  @override
  State<_GanttTaskSheet> createState() => _GanttTaskSheetState();
}

class _GanttTaskSheetState extends State<_GanttTaskSheet> {
  late Project _project;
  late ProjectTask _task;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _task = widget.task;
  }

  Future<void> _saveActions() async {
    setState(() => _saving = true);
    final updatedTasks = _project.tasks.map((t) {
      return t.id == _task.id ? _task : t;
    }).toList();
    await widget.sync.saveProjectTasks(_project.id, updatedTasks);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addAction() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle action'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      _task.actions.add(TaskAction(title: result));
    });
    _saveActions();
  }

  void _toggle(TaskAction action, bool done) {
    setState(() {
      action.done = done;
      action.doneAt = done ? DateTime.now() : null;
    });
    _saveActions();
  }

  void _addToToday(TaskAction action) {
    widget.logic.addProjectTaskActionToToday(
      projectId: _project.id,
      taskId: _task.id,
      actionId: action.id,
      title: action.title,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ajouté au plan du jour'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = _task.actions.where((a) => !a.done).toList();
    final done = _task.actions.where((a) => a.done).toList();
    final progress = _task.stepsTotal > 0
        ? _task.stepsDone / _task.stepsTotal
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Projet parent
                Text(
                  _project.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (_task.isMilestone)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.diamond_outlined,
                            size: 16, color: cs.onSurface.withOpacity(.5)),
                      ),
                    Expanded(
                      child: Text(
                        _task.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                // Dates
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: cs.onSurface.withOpacity(.4)),
                    const SizedBox(width: 5),
                    Text(
                      '${_fmtDate(_task.startDate)}'
                      '${_task.endDate != null ? ' → ${_fmtDate(_task.endDate!)}' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(.5)),
                    ),
                    const SizedBox(width: 12),
                    // Statut
                    _StatusChip(status: _task.status),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                          backgroundColor: cs.onSurface.withOpacity(.08),
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${_task.stepsDone}/${_task.stepsTotal}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.45))),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // ── Actions ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Actions en attente
                if (pending.isEmpty && done.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucune action. Ajoute le détail opérationnel de cette tâche.',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withOpacity(.4),
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                for (final a in pending)
                  _ActionTile(
                    action: a,
                    alreadyInToday: widget.logic.state.dayPlan
                        .any((it) => it.projectTaskId == a.id),
                    onToggle: (v) => _toggle(a, v),
                    onAddToToday: () => _addToToday(a),
                    onRemoveFromToday: () {
                      widget.logic.removeProjectTaskActionFromToday(a.id);
                      setState(() {});
                    },
                  ),

                // Bouton ajouter
                TextButton.icon(
                  onPressed: _addAction,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter une action'),
                ),

                // Actions faites
                if (done.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'Réalisées (${done.length})',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(.45),
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final a in done)
                    InkWell(
                      onTap: () => _toggle(a, false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_box_rounded,
                                size: 18, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                a.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tiles ─────────────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final TaskAction action;
  final bool alreadyInToday;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAddToToday;
  final VoidCallback onRemoveFromToday;

  const _ActionTile({
    required this.action,
    required this.alreadyInToday,
    required this.onToggle,
    required this.onAddToToday,
    required this.onRemoveFromToday,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Checkbox(value: action.done, onChanged: (v) => onToggle(v ?? false)),
        Expanded(
          child: Text(action.title, style: const TextStyle(fontSize: 14)),
        ),
        IconButton(
          icon: Icon(
            alreadyInToday
                ? Icons.arrow_circle_right
                : Icons.arrow_circle_right_outlined,
            size: 20,
            color: alreadyInToday ? cs.primary : cs.onSurface.withOpacity(.4),
          ),
          tooltip: alreadyInToday
              ? 'Retirer du plan du jour'
              : 'Planifier aujourd\'hui',
          onPressed:
              alreadyInToday ? onRemoveFromToday : onAddToToday,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'done'    => ('Terminée', Colors.green),
      'skipped' => ('Ignorée', Colors.orange),
      _         => ('En cours', cs.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}
