import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';

// ── Constantes de layout ──────────────────────────────────────────────────────

const double _kLabelW = 220.0;
const double _kCellW = 68.0;
const double _kRowH = 36.0;
const double _kGroupH = 30.0;
const double _kPhaseH = 28.0;
const double _kWeekH = 26.0;
const double _kBarVPad = 8.0;

// Couleurs de grille — vert teal subtil en sombre, gris en clair
const _kTealGrid   = Color(0xFF1D9E75);
const _kGridLine   = Color(0xFFE8E8E8); // placeholder remplacé au runtime
const _kGridLineAlt = Color(0xFFF5F5F5);

Color _gridColor(BuildContext ctx) {
  final dark = Theme.of(ctx).brightness == Brightness.dark;
  return dark ? _kTealGrid.withOpacity(0.18) : const Color(0xFFE8E8E8);
}

Color _gridColorAlt(BuildContext ctx) {
  final dark = Theme.of(ctx).brightness == Brightness.dark;
  return dark ? _kTealGrid.withOpacity(0.10) : const Color(0xFFF5F5F5);
}

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
      body: Column(
        children: [
          _GanttDashboard(project: _project),
          Expanded(child: _GanttBody(project: _project, onTaskTap: _onTaskTap)),
        ],
      ),
    );
  }
}

// ── Dashboard stratégique ─────────────────────────────────────────────────────

class _GanttDashboard extends StatefulWidget {
  final Project project;
  const _GanttDashboard({required this.project});

  @override
  State<_GanttDashboard> createState() => _GanttDashboardState();
}

class _GanttDashboardState extends State<_GanttDashboard> {
  bool _expanded = true;

  Project get p => widget.project;

  // ── Calculs ────────────────────────────────────────────────────────────────

  DateTime get _today => DateTime.now();

  bool _isOverdue(ProjectTask t) =>
      t.endDate != null &&
      DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day)
          .isBefore(DateTime(_today.year, _today.month, _today.day)) &&
      t.status != 'done' &&
      t.status != 'skipped';

  List<ProjectTask> get _realTasks =>
      p.tasks.where((t) => !t.isMilestone).toList();
  List<ProjectTask> get _milestones =>
      p.tasks.where((t) => t.isMilestone).toList();

  int get _totalTasks => _realTasks.length;
  int get _doneTasks => _realTasks.where((t) => t.status == 'done').length;
  int get _overdueTasks => _realTasks.where(_isOverdue).length;
  double get _globalPct =>
      _totalTasks > 0 ? _doneTasks / _totalTasks : 0.0;

  // Statut d'une phase
  ({int done, int total, int overdue, String label, Color color})
      _phaseStats(ProjectPhase phase) {
    final tasks = _realTasks.where((t) => t.phaseId == phase.id).toList();
    final done = tasks.where((t) => t.status == 'done').length;
    final overdue = tasks.where(_isOverdue).length;
    final today = _today;
    final start = DateTime(phase.startDate.year, phase.startDate.month, phase.startDate.day);
    final end = DateTime(phase.endDate.year, phase.endDate.month, phase.endDate.day);
    final todayD = DateTime(today.year, today.month, today.day);

    String label;
    Color color;
    if (tasks.isNotEmpty && done == tasks.length) {
      label = 'Terminée';
      color = Colors.green;
    } else if (overdue > 0) {
      label = '$overdue en retard';
      color = Colors.orange;
    } else if (todayD.isBefore(start)) {
      label = 'À venir';
      color = Colors.grey;
    } else if (todayD.isAfter(end)) {
      label = 'Dépassée';
      color = Colors.red;
    } else {
      label = 'En cours';
      color = Colors.blue;
    }
    return (done: done, total: tasks.length, overdue: overdue, label: label, color: color);
  }

  // Statut d'un jalon
  ({Color color, String label, IconData icon}) _milestoneStatus(ProjectTask m) {
    if (m.status == 'done') {
      return (color: Colors.green, label: 'Atteint', icon: Icons.check_circle_outline);
    }
    if (_isOverdue(m)) {
      return (color: Colors.red, label: 'En retard', icon: Icons.warning_amber_outlined);
    }
    return (color: Colors.grey, label: 'À venir', icon: Icons.radio_button_unchecked);
  }

  String _fmtDate(DateTime d) {
    const months = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                    'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${months[d.month - 1]}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header cliquable ───────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Suivi stratégique',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(width: 12),
                  // Résumé compact toujours visible
                  _PillStat(
                    label: '${(_globalPct * 100).round()}%',
                    color: cs.primary,
                  ),
                  if (_overdueTasks > 0) ...[
                    const SizedBox(width: 6),
                    _PillStat(
                      label: '$_overdueTasks en retard',
                      color: Colors.orange,
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu dépliable ──────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne 1 : stats globales
                  Row(
                    children: [
                      _StatCard(
                        label: 'Avancement',
                        value: '$_doneTasks / $_totalTasks tâches',
                        progress: _globalPct,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'En retard',
                        value: '$_overdueTasks tâche${_overdueTasks != 1 ? 's' : ''}',
                        color: _overdueTasks > 0 ? Colors.orange : Colors.green,
                        icon: _overdueTasks > 0
                            ? Icons.warning_amber_outlined
                            : Icons.check_circle_outline,
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        label: 'Jalons',
                        value:
                            '${_milestones.where((m) => m.status == 'done').length} / ${_milestones.length} atteint${_milestones.where((m) => m.status == 'done').length != 1 ? 's' : ''}',
                        color: cs.secondary,
                        icon: Icons.diamond_outlined,
                      ),
                    ],
                  ),

                  if (p.phases.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Par phase',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: cs.onSurface.withOpacity(0.45))),
                    const SizedBox(height: 8),
                    // Grille des phases
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: p.phases.map((phase) {
                        final s = _phaseStats(phase);
                        final pct = s.total > 0 ? s.done / s.total : 0.0;
                        return _PhaseChip(
                          label: phase.label,
                          done: s.done,
                          total: s.total,
                          pct: pct,
                          statusLabel: s.label,
                          statusColor: s.color,
                          bgColor: _hex(phase.color, cs.primaryContainer),
                        );
                      }).toList(),
                    ),
                  ],

                  if (_milestones.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Jalons',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: cs.onSurface.withOpacity(0.45))),
                    const SizedBox(height: 6),
                    ..._milestones.map((m) {
                      final s = _milestoneStatus(m);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(s.icon, size: 14, color: s.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(m.title,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withOpacity(0.8))),
                            ),
                            if (m.startDate != null)
                              Text(_fmtDate(m.startDate),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface.withOpacity(0.4))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s.label,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: s.color)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
        ],
      ),
    );
  }
}

// ── Widgets du dashboard ──────────────────────────────────────────────────────

class _PillStat extends StatelessWidget {
  final String label;
  final Color color;
  const _PillStat({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double? progress;
  final IconData? icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    this.progress,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.45),
                    letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                ],
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                backgroundColor: color.withOpacity(0.12),
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final String label;
  final int done;
  final int total;
  final double pct;
  final String statusLabel;
  final Color statusColor;
  final Color bgColor;

  const _PhaseChip({
    required this.label,
    required this.done,
    required this.total,
    required this.pct,
    required this.statusLabel,
    required this.statusColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bgColor.withOpacity(0.6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: statusColor.withOpacity(0.12),
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 6),
              Text('$done/$total',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.black.withOpacity(0.45))),
            ],
          ),
          const SizedBox(height: 4),
          Text(statusLabel,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: statusColor)),
        ],
      ),
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
        Builder(builder: (ctx) => Container(
          height: 1, width: totalW,
          color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.5),
        )),
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
                        color: _kGridLine, width: 1),
                    bottom: BorderSide(
                        color: _kGridLine, width: 1),
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
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final groupBg = cs.surfaceContainerHighest.withOpacity(0.5);
      return SizedBox(
        height: _kGroupH,
        width: totalW,
        child: Container(
          color: groupBg,
          child: Row(
            children: [
              SizedBox(
                width: _kLabelW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.5),
                      letterSpacing: 0.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Container(
                width: timeW,
                height: _kGroupH,
                decoration: BoxDecoration(
                  color: groupBg,
                  border: Border(
                      bottom: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.4),
                          width: 1)),
                ),
              ),
            ],
          ),
        ),
      );
    });
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
                      bottom: BorderSide(color: _kGridLine, width: 1)),
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
                              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.35)
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                          decoration: isDone ? TextDecoration.lineThrough : null,
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
                bottom: BorderSide(color: _kGridLine, width: 1)),
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
          child: Container(color: _kGridLineAlt),
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
