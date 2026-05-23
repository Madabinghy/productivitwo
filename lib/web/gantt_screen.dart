import 'dart:html' as html;
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/web/gantt_pdf_exporter.dart';

// ── Constantes de layout ──────────────────────────────────────────────────────

const double _kLabelW = 280.0;
const double _kCellW = 68.0;
const double _kDayCellW = 28.0;
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
  final String? targetTaskId;
  final List<Domain> domains;
  const GanttScreen({
    super.key,
    required this.project,
    this.targetTaskId,
    this.domains = const [],
  });

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

// Thème clair Productivitwo (même palette que web_app.dart)
final _kGanttLightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF1D9E75),
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF1D9E75),
    secondary: const Color(0xFF155F47),
    surface: const Color(0xFFD6EEE6),
    surfaceContainerLowest: const Color(0xFFC8E8DC),
    surfaceContainerHighest: const Color(0xFFB0DDCB),
  ),
  scaffoldBackgroundColor: const Color(0xFFC8E8DC),
  useMaterial3: true,
);

class _GanttScreenState extends State<GanttScreen> {
  late Project _project;
  final _sync = FirestoreSync();
  bool _forceLight = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    if (widget.targetTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTargetTask());
    }
  }

  void _openTargetTask() {
    final task = _project.tasks
        .where((t) => t.id == widget.targetTaskId)
        .firstOrNull;
    if (task != null) _onTaskTap(task);
  }

  Future<void> _changeDomain() async {
    final domains = widget.domains;
    if (domains.isEmpty) return;
    final cs = Theme.of(context).colorScheme;

    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Changer de domaine'),
        children: [
          // Option "Aucun domaine"
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline,
                    size: 14, color: cs.onSurface.withOpacity(.4)),
                const SizedBox(width: 10),
                Text('Aucun domaine',
                    style:
                        TextStyle(color: cs.onSurface.withOpacity(.5))),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final d in domains)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d.id),
              child: Row(
                children: [
                  if (d.colorValue != null)
                    Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Color(d.colorValue!),
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(width: 20),
                  Text(d.name,
                      style: TextStyle(
                        fontWeight: _project.domainId == d.id
                            ? FontWeight.bold
                            : FontWeight.normal,
                      )),
                  if (_project.domainId == d.id) ...[
                    const Spacer(),
                    Icon(Icons.check, size: 16, color: cs.primary),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    if (selected == null) return; // annulé
    setState(() => _project = _project..domainId = selected.isEmpty ? null : selected);
    await _sync.saveProject(_project);
  }

  Future<void> _exportPdf() async {
    final pdf = await GanttPdfExporter.build(_project);
    final bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrl(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', '${_project.title.replaceAll(' ', '_')}_gantt.pdf')
      ..click();
    html.Url.revokeObjectUrl(url);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final child = _buildScaffold(context);
    if (_forceLight && isDark) {
      return Theme(data: _kGanttLightTheme, child: Builder(builder: _buildScaffold));
    }
    return child;
  }

  Widget _buildScaffold(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          if (widget.domains.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.move_to_inbox_outlined),
              tooltip: 'Changer de domaine',
              onPressed: _changeDomain,
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exporter en PDF',
            onPressed: _exportPdf,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: Column(
        children: [
          _GanttDashboard(project: _project),
          Expanded(child: _GanttBody(
            project: _project,
            onTaskTap: _onTaskTap,
            forceLight: _forceLight,
            onToggleLight: () => setState(() => _forceLight = !_forceLight),
          )),
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
  bool _expanded = false;

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = _isDark(bgColor) || dark
        ? Colors.white.withOpacity(0.92)
        : _darken(bgColor);

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: dark ? bgColor.withOpacity(0.10) : bgColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bgColor.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header coloré (style phase Gantt) ─────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(dark ? 0.35 : 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: labelColor),
                overflow: TextOverflow.ellipsis),
          ),
          // ── Contenu ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                        backgroundColor: bgColor.withOpacity(0.2),
                        color: bgColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$done/$total',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: bgColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(statusLabel,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ],
                ),
              ],
            ),
          ),
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
  final bool forceLight;
  final VoidCallback onToggleLight;
  const _GanttBody({
    required this.project,
    this.onTaskTap,
    required this.forceLight,
    required this.onToggleLight,
  });

  @override
  State<_GanttBody> createState() => _GanttBodyState();
}

class _GanttBodyState extends State<_GanttBody> {
  late final TransformationController _ctrl;
  bool _dayView = false;
  bool _exportingPng = false;
  final _gridKey = GlobalKey();

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

  Future<void> _exportPng() async {
    setState(() => _exportingPng = true);
    try {
      final boundary = _gridKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final blob = html.Blob([bytes], 'image/png');
      final url = html.Url.createObjectUrl(blob);
      html.AnchorElement(href: url)
        ..setAttribute(
            'download',
            '${widget.project.title.replaceAll(' ', '_')}_gantt.png')
        ..click();
      html.Url.revokeObjectUrl(url);
    } finally {
      if (mounted) setState(() => _exportingPng = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final project = widget.project;
    final start = project.startDate;
    final end = project.endDate ?? start.add(const Duration(days: 84));
    final weeks = max(4, ((end.difference(start).inDays / 7).ceil() + 1));

    return Column(
      children: [
        // Toggle Semaine / Jour + thème + export PNG
        Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            children: [
              Tooltip(
                message: 'Exporter en PNG (haute résolution)',
                child: _exportingPng
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.image_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: _exportPng,
                      ),
              ),
              const Spacer(),
              // Toggle clair/sombre
              Tooltip(
                message: widget.forceLight ? 'Mode sombre' : 'Mode clair',
                child: IconButton(
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark && widget.forceLight
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onToggleLight,
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(value: false, label: Text('Semaine')),
                  ButtonSegment<bool>(value: true, label: Text('Jour')),
                ],
                selected: {_dayView},
                onSelectionChanged: (s) => setState(() => _dayView = s.first),
                style: ButtonStyle(
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),
        // Grille
        Expanded(
          child: InteractiveViewer(
            transformationController: _ctrl,
            constrained: false,
            minScale: 0.25,
            maxScale: 4.0,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: RepaintBoundary(
                key: _gridKey,
                child: _GanttGrid(
                  project: widget.project,
                  projectStart: start,
                  totalWeeks: weeks,
                  dayView: _dayView,
                  onTaskTap: widget.onTaskTap,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Grille principale ─────────────────────────────────────────────────────────

class _GanttGrid extends StatelessWidget {
  final Project project;
  final DateTime projectStart;
  final int totalWeeks;
  final bool dayView;
  final void Function(ProjectTask)? onTaskTap;

  const _GanttGrid({
    required this.project,
    required this.projectStart,
    required this.totalWeeks,
    this.dayView = false,
    this.onTaskTap,
  });

  int get totalDays {
    final end = project.endDate ?? projectStart.add(const Duration(days: 84));
    return end.difference(projectStart).inDays + 7;
  }

  double get timeW => dayView ? totalDays * _kDayCellW : totalWeeks * _kCellW;
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
          totalDays: totalDays,
          dayView: dayView,
          timeW: timeW,
        ),
        // ── Week header ───────────────────────────────────────
        _WeekHeaderRow(
          projectStart: projectStart,
          totalWeeks: totalWeeks,
          totalDays: totalDays,
          dayView: dayView,
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
              totalDays: totalDays,
              dayView: dayView,
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
  final int totalDays;
  final bool dayView;
  final double timeW;

  const _PhaseHeaderRow({
    required this.project,
    required this.projectStart,
    required this.totalWeeks,
    required this.totalDays,
    required this.dayView,
    required this.timeW,
  });

  double _toX(int inDays) =>
      dayView ? inDays * _kDayCellW : inDays / 7 * _kCellW;

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
                    _toX(phase.startDate.difference(projectStart).inDays));
                final right = min(
                    timeW,
                    _toX(phase.endDate.difference(projectStart).inDays));
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
  final int totalDays;
  final bool dayView;
  final double timeW;

  const _WeekHeaderRow({
    required this.projectStart,
    required this.totalWeeks,
    required this.totalDays,
    required this.dayView,
    required this.timeW,
  });

  String _weekLabel(int i) {
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
          if (dayView)
            ...List.generate(totalDays, (i) {
              final d = projectStart.add(Duration(days: i));
              final isWeekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
              return SizedBox(
                width: _kDayCellW,
                height: _kWeekH,
                child: Container(
                  decoration: BoxDecoration(
                    color: isWeekend ? const Color(0x11AAAAAA) : null,
                    border: const Border(
                      left: BorderSide(color: _kGridLine, width: 1),
                      bottom: BorderSide(color: _kGridLine, width: 1),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isWeekend
                          ? const Color(0xFFAAAAAA)
                          : const Color(0xFF888888),
                    ),
                  ),
                ),
              );
            })
          else
            ...List.generate(totalWeeks, (i) {
              return SizedBox(
                width: _kCellW,
                height: _kWeekH,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: _kGridLine, width: 1),
                      bottom: BorderSide(color: _kGridLine, width: 1),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _weekLabel(i),
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
  final int totalDays;
  final bool dayView;
  final double timeW;
  final VoidCallback? onTap;

  const _TaskRow({
    required this.task,
    required this.projectStart,
    required this.totalWeeks,
    required this.totalDays,
    required this.dayView,
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
    final count = dayView ? totalDays : totalWeeks;
    final cellW = dayView ? _kDayCellW : _kCellW;
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
      // Lignes verticales
      ...List.generate(count, (i) {
        return Positioned(
          left: i * cellW,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: _kGridLineAlt),
        );
      }),
    ];
  }

  double _toX(int inDays) =>
      dayView ? inDays * _kDayCellW : inDays / 7 * _kCellW;

  Widget _buildBar(bool isDone) {
    final end = task.endDate ?? task.startDate.add(const Duration(days: 7));
    final startDays = task.startDate.difference(projectStart).inDays;
    final endDays = end.difference(projectStart).inDays;

    final left = max(0.0, _toX(startDays));
    final right = min(timeW, _toX(endDays));
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
          boxShadow: isDone
              ? null
              : [
                  BoxShadow(
                    color: barColor.withOpacity(0.55),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
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
    final inDays = task.startDate.difference(projectStart).inDays;
    final cellHalf = dayView ? _kDayCellW / 2 : _kCellW / 2;
    final centerX = _toX(inDays) + cellHalf;
    final color = _hex(task.color, const Color(0xFF6B57F0));
    const size = 13.0;

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
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.7),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
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

class _TaskDetailDialogState extends State<_TaskDetailDialog>
    with SingleTickerProviderStateMixin {
  late ProjectTask _task;
  bool _saving = false;
  late final TabController _tabCtrl;

  // Fichiers
  List<Map<String, dynamic>> _docs = [];
  bool _loadingDocs = true;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _loadDocs();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDocs() async {
    final docs = await widget.sync.fetchDocuments(taskId: _task.id);
    if (mounted) setState(() { _docs = docs; _loadingDocs = false; });
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
    final isFilesTab = _tabCtrl.index == 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
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
                    icon: Icon(Icons.delete_outline,
                        color: cs.onSurface.withOpacity(.4)),
                    tooltip: 'Supprimer la tâche',
                    onPressed: () => _confirmDeleteTask(cs),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TabBar(
                controller: _tabCtrl,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.checklist_outlined, size: 14),
                        const SizedBox(width: 6),
                        Text('Actions (${_task.actions.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_outlined, size: 14),
                        const SizedBox(width: 6),
                        Text('Fichiers${_docs.isNotEmpty ? ' (${_docs.length})' : ''}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),

            // Contenu
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: isFilesTab
                  ? _buildFilesTab(cs)
                  : _buildActionsTab(cs, pending, done),
            ),

            // Footer
            if (!isFilesTab)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter une action'),
                  onPressed: _addAction,
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTask(ColorScheme cs) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la tâche ?'),
        content: Text(
            'Supprimer "${_task.title}" ? Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final updatedTasks =
        widget.project.tasks.where((t) => t.id != _task.id).toList();
    await widget.sync.saveProjectTasks(widget.project.id, updatedTasks);
    final updatedProject = widget.project
      ..tasks.replaceRange(0, widget.project.tasks.length, updatedTasks);
    widget.onProjectUpdated(updatedProject);
    if (mounted) Navigator.pop(context);
  }

  // ── Onglet Actions ───────────────────────────────────────────────────────────

  Widget _buildActionsTab(ColorScheme cs,
      List<TaskAction> pending, List<TaskAction> done) {
    if (pending.isEmpty && done.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Aucune action. Clique + pour en ajouter.',
          style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: cs.onSurface.withOpacity(.4)),
        ),
      );
    }

    // Liste complète dans l'ordre (pending en haut, done en bas)
    final allActions = _task.actions;

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      buildDefaultDragHandles: false,
      itemCount: allActions.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = allActions.removeAt(oldIndex);
          allActions.insert(newIndex, item);
        });
        _save();
      },
      itemBuilder: (ctx, i) {
        final a = allActions[i];
        return ListTile(
          key: ValueKey(a.title + i.toString()),
          dense: true,
          contentPadding: const EdgeInsets.only(left: 0, right: 4),
          leading: Checkbox(
            value: a.done,
            onChanged: (v) {
              setState(() {
                a.done = v ?? false;
                a.doneAt = a.done ? DateTime.now() : null;
              });
              _save();
            },
          ),
          title: Text(
            a.title,
            style: TextStyle(
              fontSize: 13,
              color: a.done ? cs.onSurface.withOpacity(.4) : null,
              decoration: a.done ? TextDecoration.lineThrough : null,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 16, color: cs.onSurface.withOpacity(.3)),
                visualDensity: VisualDensity.compact,
                tooltip: 'Supprimer',
                onPressed: () {
                  setState(() => allActions.removeAt(i));
                  _save();
                },
              ),
              ReorderableDragStartListener(
                index: i,
                child: Icon(Icons.drag_handle,
                    size: 18, color: cs.onSurface.withOpacity(.3)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Onglet Fichiers ──────────────────────────────────────────────────────────

  Widget _buildFilesTab(ColorScheme cs) {
    if (_loadingDocs) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 40, color: cs.onSurface.withOpacity(.2)),
              const SizedBox(height: 12),
              Text('Aucun fichier associé à cette tâche.',
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withOpacity(.5))),
              const SizedBox(height: 6),
              Text('Demandez à Claude de créer un document\net de l\'associer à cette tâche.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withOpacity(.35))),
            ],
          ),
        ),
      );
    }

    // Grouper par catégorie
    const catOrder = ['programme', 'livrable', 'brief', 'recherche', 'notes'];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final d in _docs) {
      final cat = d['category'] as String? ?? 'notes';
      grouped.putIfAbsent(cat, () => []).add(d);
    }
    final cats = catOrder.where(grouped.containsKey).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cat in cats) ...[
            _CatHeader(category: cat),
            const SizedBox(height: 6),
            for (final doc in grouped[cat]!)
              _DocCard(
                doc: doc,
                cs: cs,
                taskTitle: _task.title,
                onRefresh: _loadDocs,
                sync: widget.sync,
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ── En-tête de catégorie ──────────────────────────────────────────────────────

class _CatHeader extends StatelessWidget {
  final String category;
  const _CatHeader({required this.category});

  static const _meta = {
    'programme': (Icons.list_alt_outlined, Color(0xFF2563EB), 'Programme'),
    'brief':     (Icons.assignment_outlined, Color(0xFFD97706), 'Brief'),
    'recherche': (Icons.search, Color(0xFF7C3AED), 'Recherche'),
    'livrable':  (Icons.task_alt_outlined, Color(0xFF059669), 'Livrable'),
    'notes':     (Icons.notes, Color(0xFF6B7280), 'Notes'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _meta[category] ?? _meta['notes']!;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color)),
      ],
    );
  }
}

// ── Carte document ────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final ColorScheme cs;
  final String taskTitle;
  final VoidCallback onRefresh;
  final FirestoreSync sync;

  const _DocCard({
    required this.doc,
    required this.cs,
    required this.taskTitle,
    required this.onRefresh,
    required this.sync,
  });

  void _openViewer(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _TaskDocViewerDialog(
        title: doc['title'] as String? ?? 'Document',
        taskTitle: taskTitle,
        htmlContent: doc['content'] as String? ?? '',
        docId: doc['id'] as String? ?? 'doc',
      ),
    );
  }

  void _printDoc(String htmlContent) {
    final content = htmlContent.contains('</head>')
        ? htmlContent.replaceFirst(
            '</head>',
            '<script>window.onload=function(){window.print()}</script></head>')
        : '<html><head><script>window.onload=function(){window.print()}</script></head><body>$htmlContent</body></html>';
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrl(blob);
    html.window.open(url, '_blank');
    Future.delayed(const Duration(seconds: 10),
        () => html.Url.revokeObjectUrl(url));
  }

  void _downloadDoc(String title, String htmlContent) {
    final content = htmlContent.contains('<html') ? htmlContent
        : '<html><head><meta charset="utf-8"></head><body>$htmlContent</body></html>';
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrl(blob);
    final filename = '${title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(' ', '_')}.html';
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = doc['title'] as String? ?? 'Document';
    final subtitle = doc['subtitle'] as String?;
    final date = _fmtTs(doc['updatedAt'] ?? doc['createdAt']);
    final htmlContent = doc['content'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openViewer(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.5))),
                    ],
                    if (date.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(date,
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withOpacity(.35))),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.print_outlined,
                    size: 18, color: cs.onSurface.withOpacity(.5)),
                tooltip: 'Imprimer / Exporter PDF',
                onPressed: () => _printDoc(htmlContent),
              ),
              IconButton(
                icon: Icon(Icons.download_outlined,
                    size: 18, color: cs.onSurface.withOpacity(.5)),
                tooltip: 'Télécharger (.html)',
                onPressed: () => _downloadDoc(title, htmlContent),
              ),
              IconButton(
                icon: Icon(Icons.open_in_new_outlined,
                    size: 18, color: cs.primary),
                tooltip: 'Ouvrir',
                onPressed: () => _openViewer(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dialog viewer document de tâche ──────────────────────────────────────────

class _TaskDocViewerDialog extends StatefulWidget {
  final String title;
  final String taskTitle;
  final String htmlContent;
  final String docId;

  const _TaskDocViewerDialog({
    required this.title,
    required this.taskTitle,
    required this.htmlContent,
    required this.docId,
  });

  @override
  State<_TaskDocViewerDialog> createState() => _TaskDocViewerDialogState();
}

class _TaskDocViewerDialogState extends State<_TaskDocViewerDialog> {
  void _print() {
    final content = widget.htmlContent.contains('</head>')
        ? widget.htmlContent.replaceFirst(
            '</head>',
            '<script>window.onload=function(){window.print()}</script></head>')
        : '<html><head><script>window.onload=function(){window.print()}</script></head><body>${widget.htmlContent}</body></html>';
    final blob = html.Blob([content], 'text/html');
    final url = html.Url.createObjectUrl(blob);
    html.window.open(url, '_blank');
    Future.delayed(const Duration(seconds: 10),
        () => html.Url.revokeObjectUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(
                    bottom: BorderSide(
                        color: cs.outlineVariant.withOpacity(0.4))),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                        Text(widget.taskTitle,
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(.45))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.print_outlined,
                        size: 18, color: cs.onSurface.withOpacity(.6)),
                    tooltip: 'Imprimer / Exporter PDF',
                    onPressed: _print,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_outlined, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
            Expanded(
              child: _GanttHtmlViewer(
                key: ValueKey(widget.docId),
                docId: widget.docId,
                htmlContent: widget.htmlContent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Viewer HTML via iframe ────────────────────────────────────────────────────

class _GanttHtmlViewer extends StatefulWidget {
  final String docId;
  final String htmlContent;
  const _GanttHtmlViewer(
      {super.key, required this.docId, required this.htmlContent});

  @override
  State<_GanttHtmlViewer> createState() => _GanttHtmlViewerState();
}

class _GanttHtmlViewerState extends State<_GanttHtmlViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'gantt-doc-${widget.docId}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) {
      return html.IFrameElement()
        ..srcdoc = widget.htmlContent
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewId);
}
