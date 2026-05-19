import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

// ── Constantes de layout ──────────────────────────────────────────────────────

const double _kLabelW = 220.0;   // largeur colonne labels
const double _kCellW = 68.0;     // largeur d'une semaine en pixels
const double _kRowH = 36.0;      // hauteur d'une ligne de tâche
const double _kGroupH = 30.0;    // hauteur d'une ligne de groupe
const double _kPhaseH = 28.0;    // hauteur du header de phase
const double _kWeekH = 26.0;     // hauteur du header de semaines
const double _kBarVPad = 8.0;    // padding vertical dans la barre

// ── Screen ────────────────────────────────────────────────────────────────────

class GanttScreen extends StatefulWidget {
  final Project project;
  const GanttScreen({super.key, required this.project});

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  late Project _project;
  final _sync = FirestoreSync();

  @override
  void initState() {
    super.initState();
    _project = widget.project;
  }

  void _onTaskTap(ProjectTask task) {
    showDialog(
      context: context,
      builder: (_) => _TaskDetailDialog(
        project: _project,
        task: task,
        sync: _sync,
        onProjectUpdated: (p) => setState(() => _project = p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_project.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            if (_project.description != null && _project.description!.isNotEmpty)
              Text(_project.description!,
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          _ZoomHint(),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: _GanttBody(project: _project, onTaskTap: _onTaskTap),
    );
  }
}

class _ZoomHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Pincer / molette pour zoomer · Glisser pour naviguer',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.zoom_in_outlined,
                size: 16, color: cs.onSurface.withOpacity(0.4)),
            const SizedBox(width: 4),
            Text('Pincer pour zoomer',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}

// ── Body avec InteractiveViewer ───────────────────────────────────────────────

class _GanttBody extends StatefulWidget {
  final Project project;
  final void Function(ProjectTask)? onTaskTap;
  const _GanttBody({required this.project, this.onTaskTap});

  @override
  State<_GanttBody> createState() => _GanttBodyState();
}

class _GanttBodyState extends State<_GanttBody> {
  late final TransformationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TransformationController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final start = project.startDate;
    final end = project.endDate ?? start.add(const Duration(days: 84));
    final weeks = max(4, ((end.difference(start).inDays / 7).ceil() + 1));

    return InteractiveViewer(
      transformationController: _ctrl,
      constrained: false,
      minScale: 0.25,
      maxScale: 4.0,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _GanttGrid(
          project: widget.project,
          projectStart: start,
          totalWeeks: weeks,
          onTaskTap: widget.onTaskTap,
        ),
      ),
    );
  }
}

// ── Grille principale ─────────────────────────────────────────────────────────

class _GanttGrid extends StatelessWidget {
  final Project project;
  final DateTime projectStart;
  final int totalWeeks;
  final void Function(ProjectTask)? onTaskTap;

  const _GanttGrid({
    required this.project,
    required this.projectStart,
    required this.totalWeeks,
    this.onTaskTap,
  });

  double get timeW => totalWeeks * _kCellW;
  double get totalW => _kLabelW + timeW;

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(project.tasks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Phase header ──────────────────────────────────────
        _PhaseHeaderRow(
          project: project,
          projectStart: projectStart,
          totalWeeks: totalWeeks,
          timeW: timeW,
        ),
        // ── Week header ───────────────────────────────────────
        _WeekHeaderRow(
          projectStart: projectStart,
          totalWeeks: totalWeeks,
          timeW: timeW,
        ),
        // ── Séparateur ────────────────────────────────────────
        Container(height: 1, width: totalW, color: const Color(0xFFE8E8E8)),
        // ── Groupes et tâches ─────────────────────────────────
        for (final group in groups) ...[
          if (group.label.isNotEmpty)
            _GroupRow(
                label: group.label, timeW: timeW, totalW: totalW),
          for (final task in group.tasks)
            _TaskRow(
              task: task,
              projectStart: projectStart,
              totalWeeks: totalWeeks,
              timeW: timeW,
              onTap: onTaskTap != null ? () => onTaskTap!(task) : null,
            ),
        ],
        // Padding bas
        SizedBox(height: 24, width: totalW),
      ],
    );
  }
}

// ── Phase header ──────────────────────────────────────────────────────────────

class _PhaseHeaderRow extends StatelessWidget {
  final Project project;
  final DateTime projectStart;
  final int totalWeeks;
  final double timeW;

  const _PhaseHeaderRow({
    required this.project,
    required this.projectStart,
    required this.totalWeeks,
    required this.timeW,
  });

  @override
  Widget build(BuildContext context) {
    if (project.phases.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _kPhaseH,
      width: _kLabelW + timeW,
      child: Row(
        children: [
          // Cellule vide (align avec les labels)
          const SizedBox(width: _kLabelW),
          // Stack des phases
          SizedBox(
            width: timeW,
            height: _kPhaseH,
            child: Stack(
              children: project.phases.map((phase) {
                final left = max(
                    0.0,
                    phase.startDate
                            .difference(projectStart)
                            .inDays /
                        7 *
                        _kCellW);
                final right = min(
                    timeW,
                    phase.endDate
                            .difference(projectStart)
                            .inDays /
                        7 *
                        _kCellW);
                final w = max(0.0, right - left);
                final bg = _hex(phase.color, const Color(0xFFEEEDFE));
                final fg = _darken(bg);

                return Positioned(
                  left: left,
                  top: 0,
                  width: w,
                  height: _kPhaseH,
                  child: Container(
                    margin: const EdgeInsets.only(right: 1),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      phase.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Week header ───────────────────────────────────────────────────────────────

class _WeekHeaderRow extends StatelessWidget {
  final DateTime projectStart;
  final int totalWeeks;
  final double timeW;

  const _WeekHeaderRow({
    required this.projectStart,
    required this.totalWeeks,
    required this.timeW,
  });

  String _label(int i) {
    final d = projectStart.add(Duration(days: i * 7));
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kWeekH,
      width: _kLabelW + timeW,
      child: Row(
        children: [
          const SizedBox(width: _kLabelW),
          ...List.generate(totalWeeks, (i) {
            return SizedBox(
              width: _kCellW,
              height: _kWeekH,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: const Color(0xFFE8E8E8), width: 1),
                    bottom: BorderSide(
                        color: const Color(0xFFE8E8E8), width: 1),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _label(i),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF888888)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Ligne de groupe ───────────────────────────────────────────────────────────

class _GroupRow extends StatelessWidget {
  final String label;
  final double timeW;
  final double totalW;

  const _GroupRow(
      {required this.label, required this.timeW, required this.totalW});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kGroupH,
      width: totalW,
      child: Container(
        color: const Color(0xFFF9F9F7),
        child: Row(
          children: [
            SizedBox(
              width: _kLabelW,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF888888),
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Container(
              width: timeW,
              height: _kGroupH,
              decoration: const BoxDecoration(
                color: Color(0xFFF9F9F7),
                border: Border(
                    bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ligne de tâche ────────────────────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final ProjectTask task;
  final DateTime projectStart;
  final int totalWeeks;
  final double timeW;
  final VoidCallback? onTap;

  const _TaskRow({
    required this.task,
    required this.projectStart,
    required this.totalWeeks,
    required this.timeW,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';

    return SizedBox(
      height: _kRowH,
      width: _kLabelW + timeW,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label (cliquable)
          SizedBox(
            width: _kLabelW,
            height: _kRowH,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    if (task.isMilestone)
                      const Icon(Icons.diamond_outlined,
                          size: 12, color: Color(0xFF888888))
                    else
                      Icon(
                        isDone
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 12,
                        color: isDone ? Colors.green : const Color(0xFFCCCCCC),
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDone
                              ? const Color(0xFFAAAAAA)
                              : const Color(0xFF1A1A1A),
                          decoration:
                              isDone ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (task.stepsTotal > 0)
                      Text(
                        '${task.stepsDone}/${task.stepsTotal}',
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xFFAAAAAA)),
                      ),
                    if (onTap != null)
                      const Icon(Icons.chevron_right,
                          size: 12, color: Color(0xFFCCCCCC)),
                  ],
                ),
              ),
            ),
          ),
          // Barre Gantt
          SizedBox(
            width: timeW,
            height: _kRowH,
            child: Stack(
              children: [
                // Fond avec bordures de colonnes
                ..._buildGridLines(timeW),
                // Bar ou Milestone
                if (task.isMilestone)
                  _buildMilestone()
                else
                  _buildBar(isDone),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGridLines(double timeW) {
    return [
      // Fond global
      Positioned.fill(
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
          ),
        ),
      ),
      // Lignes verticales par semaine
      ...List.generate(totalWeeks, (i) {
        return Positioned(
          left: i * _kCellW,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: const Color(0xFFF5F5F5)),
        );
      }),
    ];
  }

  Widget _buildBar(bool isDone) {
    final end = task.endDate ?? task.startDate.add(const Duration(days: 7));
    final startDays = task.startDate.difference(projectStart).inDays;
    final endDays = end.difference(projectStart).inDays;

    final left = max(0.0, startDays / 7 * _kCellW);
    final right = min(timeW, endDays / 7 * _kCellW);
    final barW = max(4.0, right - left);

    final barColor = isDone
        ? const Color(0xFFCCCCCC)
        : _hex(task.color, const Color(0xFF6B57F0));
    final textColor = _isDark(barColor)
        ? Colors.white.withOpacity(0.9)
        : barColor.withOpacity(0.7).computeLuminance() > 0.5
            ? Colors.black.withOpacity(0.7)
            : Colors.white.withOpacity(0.9);

    return Positioned(
      left: left,
      top: _kBarVPad,
      height: _kRowH - _kBarVPad * 2,
      width: barW,
      child: Container(
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: task.barLabel != null
            ? Text(
                task.barLabel!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
              )
            : null,
      ),
    );
  }

  Widget _buildMilestone() {
    final centerX = task.startDate.difference(projectStart).inDays / 7 * _kCellW + _kCellW / 2;
    final color = _hex(task.color, const Color(0xFF6B57F0));
    const size = 12.0;

    return Positioned(
      left: centerX - size / 2,
      top: _kRowH / 2 - size / 2,
      width: size,
      height: size,
      child: Transform.rotate(
        angle: pi / 4,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ── Utilitaires ───────────────────────────────────────────────────────────────

Color _hex(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final s = hex.replaceFirst('#', '');
  if (s.length != 6) return fallback;
  try {
    return Color(int.parse('FF$s', radix: 16));
  } catch (_) {
    return fallback;
  }
}

Color _darken(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - 0.35).clamp(0.0, 1.0)).toColor();
}

bool _isDark(Color c) => c.computeLuminance() < 0.4;

// Grouper les tâches par groupLabel
List<({String label, List<ProjectTask> tasks})> _buildGroups(
    List<ProjectTask> tasks) {
  final seen = <String>[];
  final map = <String, List<ProjectTask>>{};
  for (final t in tasks) {
    final g = t.groupLabel ?? '';
    if (!seen.contains(g)) seen.add(g);
    map.putIfAbsent(g, () => []).add(t);
  }
  return seen.map((g) => (label: g, tasks: map[g]!)).toList();
}

// ── Dialog détail tâche (web) ─────────────────────────────────────────────────

class _TaskDetailDialog extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final FirestoreSync sync;
  final void Function(Project) onProjectUpdated;

  const _TaskDetailDialog({
    required this.project,
    required this.task,
    required this.sync,
    required this.onProjectUpdated,
  });

  @override
  State<_TaskDetailDialog> createState() => _TaskDetailDialogState();
}

class _TaskDetailDialogState extends State<_TaskDetailDialog> {
  late ProjectTask _task;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final updatedTasks = widget.project.tasks
        .map((t) => t.id == _task.id ? _task : t)
        .toList();
    await widget.sync.saveProjectTasks(widget.project.id, updatedTasks);
    final updatedProject = widget.project..tasks
        .replaceRange(0, widget.project.tasks.length, updatedTasks);
    widget.onProjectUpdated(updatedProject);
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
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _task.actions.add(TaskAction(title: result)));
    _save();
  }

  String _fmtDate(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = _task.actions.where((a) => !a.done).toList();
    final done = _task.actions.where((a) => a.done).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.project.title.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                letterSpacing: 1, color: cs.primary)),
                        const SizedBox(height: 4),
                        Text(_task.title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          '${_fmtDate(_task.startDate)}'
                          '${_task.endDate != null ? ' → ${_fmtDate(_task.endDate!)}' : ''}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                        ),
                      ],
                    ),
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Actions
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pending.isEmpty && done.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucune action. Clique + pour en ajouter.',
                            style: TextStyle(
                                fontSize: 13, fontStyle: FontStyle.italic,
                                color: cs.onSurface.withOpacity(.4))),
                      ),
                    for (final a in pending)
                      CheckboxListTile(
                        dense: true,
                        value: a.done,
                        title: Text(a.title, style: const TextStyle(fontSize: 13)),
                        onChanged: (v) {
                          setState(() {
                            a.done = v ?? false;
                            a.doneAt = a.done ? DateTime.now() : null;
                          });
                          _save();
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    if (done.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text('Réalisées (${done.length})',
                          style: TextStyle(fontSize: 11,
                              color: cs.onSurface.withOpacity(.4),
                              fontWeight: FontWeight.w600)),
                      for (final a in done)
                        CheckboxListTile(
                          dense: true,
                          value: a.done,
                          title: Text(a.title,
                              style: const TextStyle(fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey)),
                          onChanged: (v) {
                            setState(() { a.done = v ?? false; a.doneAt = null; });
                            _save();
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Ajouter une action'),
                onPressed: _addAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
