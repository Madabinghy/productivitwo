import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/gantt_axis.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/web/gantt_pdf_exporter.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ── Constantes de layout ──────────────────────────────────────────────────────

const double _kLabelW = 280.0;
const double _kRowH = 36.0;
const double _kGroupH = 30.0;
const double _kPhaseH = 28.0;
const double _kMonthH = 22.0;
const double _kDaysH = 26.0;
const double _kBarVPad = 8.0;

// ── Entrée publique pour afficher la dialog tâche depuis d'autres écrans ──────

Future<void> showGanttTaskDetailDialog(
  BuildContext context, {
  required Project project,
  required ProjectTask task,
  required FirestoreSync sync,
  required void Function(Project) onProjectUpdated,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _TaskDetailDialog(
      project: project,
      task: task,
      sync: sync,
      onProjectUpdated: onProjectUpdated,
    ),
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Onglet Gantt de la fiche projet (web). Pas d'en-tête propre : titre,
/// retour et « Ajouter une tâche » vivent dans l'en-tête de la fiche
/// (`project_plan_view.dart`).
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

class _GanttScreenState extends State<GanttScreen> {
  late Project _project;
  final _sync = FirestoreSync();
  // Fiche tâche en panneau latéral — null = fermé.
  ProjectTask? _panelTask;
  StrategicObjective? _objective;
  double? _objectiveWeekPct; // progression hebdo des engagements (0..1)
  // Blocs du programme liés aux tâches du projet, par taskId (points des barres).
  Map<String, List<_DatedBlock>> _blocksByTask = const {};

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    if (widget.targetTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTargetTask());
    }
    _loadObjective();
    _loadBlocks();
  }

  // Une requête sur la plage de l'axe ; les blocs sans taskId ou d'un autre
  // projet sont ignorés.
  Future<void> _loadBlocks() async {
    final axis = GanttAxis.forProject(_project);
    final from = ymdOf(axis.rangeStart);
    final to = ymdOf(axis.rangeEnd.subtract(const Duration(days: 1)));
    final schedules = await _sync.fetchDailySchedulesRange(from, to);
    if (!mounted) return;
    final taskIds = {for (final t in _project.tasks) t.id};
    final map = <String, List<_DatedBlock>>{};
    for (final sch in schedules) {
      final date = DateTime.tryParse(sch.date);
      if (date == null) continue;
      for (final b in sch.blocks) {
        final tid = b.taskId;
        if (tid == null || !taskIds.contains(tid)) continue;
        map.putIfAbsent(tid, () => []).add(_DatedBlock(date, b));
      }
    }
    for (final l in map.values) {
      l.sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : blockStartMin(a.block).compareTo(blockStartMin(b.block));
      });
    }
    setState(() => _blocksByTask = map);
  }

  // Charge l'objectif stratégique lié (s'il existe) pour l'afficher en tête du Gantt.
  Future<void> _loadObjective() async {
    final id = _project.strategicObjectiveId;
    if (id == null) return;
    try {
      final objs = await _sync.fetchStrategicObjectives();
      final matches = objs.where((o) => o.id == id).toList();
      if (matches.isNotEmpty && mounted) {
        setState(() => _objective = matches.first);
        _loadObjectiveProgress(matches.first);
      }
    } catch (_) {}
  }

  // Progression hebdo — fetch supplémentaire seulement si l'objectif porte
  // des engagements (temps/routines).
  Future<void> _loadObjectiveProgress(StrategicObjective o) async {
    if (o.timeCommitments.isEmpty && o.routineCommitments.isEmpty) return;
    try {
      final results = await Future.wait([
        _sync.fetchActivities(),
        _sync.fetchRecentSessions(7),
        _sync.fetchRecentHabitHits(7),
      ]);
      if (!mounted) return;
      final progress = computeObjectiveProgress(
        o,
        results[0] as List<Activity>,
        results[1] as List<Session>,
        results[2] as List<HabitHit>,
        DateTime.now(),
      );
      setState(() => _objectiveWeekPct = progress.weekPercent);
    } catch (_) {}
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

    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Changer de domaine'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 14, color: kBText4),
                SizedBox(width: 10),
                Text('Aucun domaine', style: TextStyle(color: kBText3)),
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
                    const Icon(Icons.check, size: 16, color: kBPrimary),
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
    // Sur écran large la fiche s'ouvre en PANNEAU latéral — le Gantt reste
    // visible et manipulable. En étroit, la Dialog d'origine.
    if (MediaQuery.of(context).size.width >= 1100) {
      setState(() => _panelTask = task);
      return;
    }
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

  Future<void> _editPhase(ProjectPhase phase) async {
    final labelCtrl = TextEditingController(text: phase.label);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la phase'),
        content: TextField(
          controller: labelCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom de la phase',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (labelCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    final newLabel = labelCtrl.text.trim();
    labelCtrl.dispose();
    if (confirmed != true || newLabel.isEmpty || !mounted) return;

    setState(() {
      for (final p in _project.phases) {
        if (p.id == phase.id) p.label = newLabel;
      }
      // Synchronise le groupLabel des tâches liées
      for (final t in _project.tasks) {
        if (t.phaseId == phase.id) t.groupLabel = newLabel;
      }
    });
    await _sync.saveProject(_project);
    await _sync.saveProjectTasks(_project.id, _project.tasks);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBBg,
      child: Column(
        children: [
          if (_project.status == 'draft') _buildDraftBanner(),
          _GanttDashboard(project: _project),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _GanttBody(
                    project: _project,
                    domainColor: _domainColor(),
                    leading: _objectiveLine(),
                    onTaskTap: _onTaskTap,
                    onPhaseTap: _editPhase,
                    onShiftTask: _shiftTask,
                    onResizeTask: _resizeTask,
                    blocksByTask: _blocksByTask,
                    onExportPdf: _exportPdf,
                    onChangeDomain:
                        widget.domains.isNotEmpty ? _changeDomain : null,
                  ),
                ),
                // Fiche tâche en panneau latéral.
                if (_panelTask != null) ...[
                  const VerticalDivider(width: 1, color: kBLine),
                  SizedBox(
                    width: 420,
                    child: _TaskDetailDialog(
                      key: ValueKey(_panelTask!.id),
                      project: _project,
                      task: _panelTask!,
                      sync: _sync,
                      panel: true,
                      onClose: () => setState(() => _panelTask = null),
                      onProjectUpdated: (p) => setState(() => _project = p),
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

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: actionLabel == null ? 2000 : 5000),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, textColor: kBPrimary, onPressed: onAction!),
      ));
  }

  Future<void> _saveTasks() => _sync.saveProjectTasks(_project.id, _project.tasks);

  /// Glisser une barre : décale début et échéance de [deltaDays]. Annulable.
  Future<void> _shiftTask(ProjectTask t, int deltaDays) async {
    if (deltaDays == 0) return;
    final oldStart = t.startDate, oldEnd = t.endDate;
    setState(() {
      t.startDate = t.startDate.add(Duration(days: deltaDays));
      if (t.endDate != null) t.endDate = t.endDate!.add(Duration(days: deltaDays));
    });
    await _saveTasks();
    final n = deltaDays.abs();
    _snack(
      '${t.isMilestone ? 'Jalon' : 'Tâche'} ${deltaDays > 0 ? 'repoussé' : 'avancé'}'
      '${t.isMilestone ? '' : 'e'} de $n jour${n > 1 ? 's' : ''}'
      ' · ${_dmy(t.startDate)}${t.endDate != null ? ' → ${_dmy(t.endDate!)}' : ''}',
      actionLabel: 'Annuler',
      onAction: () async {
        setState(() {
          t.startDate = oldStart;
          t.endDate = oldEnd;
        });
        await _saveTasks();
      },
    );
  }

  /// Tirer le bord droit : change l'échéance de [deltaDays] (jamais avant le
  /// début). Annulable.
  Future<void> _resizeTask(ProjectTask t, int deltaDays) async {
    if (deltaDays == 0) return;
    final oldEnd = t.endDate;
    final start = DateTime(t.startDate.year, t.startDate.month, t.startDate.day);
    final base = t.endDate == null
        ? start.add(const Duration(days: 7))
        : DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day);
    var end = base.add(Duration(days: deltaDays));
    if (end.isBefore(start)) end = start;
    setState(() => t.endDate = end);
    await _saveTasks();
    _snack('Échéance : ${_dmy(end)}', actionLabel: 'Annuler', onAction: () async {
      setState(() => t.endDate = oldEnd);
      await _saveTasks();
    });
  }

  // Ligne d'objectif stratégique (barre d'outils du Gantt), ou null.
  Widget? _objectiveLine() {
    final o = _objective;
    if (o == null) return null;
    const base = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flag_outlined, size: 12, color: kBPrimary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            o.title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
                fontWeight: FontWeight.w700, letterSpacing: 0.8, color: kBPrimary),
          ),
        ),
        if (o.kpiTarget != null) ...[
          const SizedBox(width: 6),
          Text(o.kpiTarget!, style: base.copyWith(color: kBPrimary.withOpacity(.75))),
        ],
        if (o.horizonLabel != null) ...[
          const SizedBox(width: 6),
          Text('· ${o.horizonLabel!}', style: base.copyWith(color: kBPrimary.withOpacity(.55))),
        ],
        if (_objectiveWeekPct != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _objectiveWeekPct,
                minHeight: 4,
                backgroundColor: kBPrimary.withOpacity(.12),
                valueColor: const AlwaysStoppedAnimation<Color>(kBPrimary),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('${(_objectiveWeekPct! * 100).round()}%',
              style: base.copyWith(color: kBPrimary.withOpacity(.75))),
        ],
      ],
    );
  }

  // Couleur du domaine du projet, ou null s'il n'en a pas (fallback des barres Gantt).
  Color? _domainColor() {
    final dom = widget.domains.where((d) => d.id == _project.domainId).firstOrNull;
    final cv = dom?.colorValue;
    return cv != null ? Color(cv) : null;
  }

  /// Bandeau brouillon : le projet reste hors suivi tant qu'il n'est pas
  /// validé. Le bouton bascule le projet en actif.
  Widget _buildDraftBanner() {
    return Container(
      width: double.infinity,
      color: kBAttention.withOpacity(.10),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.edit_note_outlined, size: 18, color: kBAttention),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Brouillon — modifie librement, le projet n\'entre pas encore dans le suivi.',
              style: TextStyle(fontSize: 13, color: kBText2),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _validatePlan,
            icon: const Icon(Icons.rocket_launch_outlined, size: 16),
            label: const Text('Valider le plan'),
            style: TextButton.styleFrom(
                foregroundColor: kBPrimary, visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  /// Valide le plan : brouillon → actif.
  Future<void> _validatePlan() async {
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    setState(() {
      _project.status = 'active';
      for (final t in _project.tasks) {
        if (t.startDate.isBefore(DateTime(2001))) t.startDate = todayMid;
      }
    });
    await _sync.saveProject(_project);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Plan validé — le projet est actif. 🚀')));
  }
}

// ── Corps : barre d'outils + grille défilante à deux axes ─────────────────────

class _GanttBody extends StatefulWidget {
  final Project project;
  final Color? domainColor;
  final Widget? leading;
  final void Function(ProjectTask)? onTaskTap;
  final void Function(ProjectPhase)? onPhaseTap;
  final void Function(ProjectTask, int deltaDays) onShiftTask;
  final void Function(ProjectTask, int deltaDays) onResizeTask;
  final Map<String, List<_DatedBlock>> blocksByTask;
  final VoidCallback onExportPdf;
  final VoidCallback? onChangeDomain;
  const _GanttBody({
    required this.project,
    this.domainColor,
    this.leading,
    this.onTaskTap,
    this.onPhaseTap,
    required this.onShiftTask,
    required this.onResizeTask,
    this.blocksByTask = const {},
    required this.onExportPdf,
    this.onChangeDomain,
  });

  @override
  State<_GanttBody> createState() => _GanttBodyState();
}

class _GanttBodyState extends State<_GanttBody> {
  final _h = ScrollController();
  final _v = ScrollController();
  final _gridKey = GlobalKey();
  GanttScale _scale = GanttScale.day;
  double _zoom = 1;
  bool _exportingPng = false;
  bool _initialScrollDone = false;
  // Largeur visible de la zone de temps (hors colonne des libellés).
  double _viewportW = 0;
  // Glisser en cours sur une barre (aperçu avant enregistrement).
  _BarDrag? _drag;
  // Sections (phases) repliées — clé = id de phase, '_none' pour « Sans phase ».
  final Set<String> _collapsed = {};

  void _toggleGroup(String key) =>
      setState(() => _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key));

  void _dragStart(ProjectTask t, bool resize) =>
      setState(() => _drag = _BarDrag(t.id, resize));
  void _dragUpdate(double dx) {
    final d = _drag;
    if (d == null) return;
    setState(() => _drag = _BarDrag(d.taskId, d.resize, d.dx + dx));
  }
  void _dragEnd(ProjectTask t) {
    final d = _drag;
    if (d == null) return;
    final delta = (d.dx / _axis.dayW).round();
    setState(() => _drag = null);
    if (d.resize) {
      widget.onResizeTask(t, delta);
    } else {
      widget.onShiftTask(t, delta);
    }
  }
  void _dragCancel() => setState(() => _drag = null);

  GanttAxis get _axis =>
      GanttAxis.forProject(widget.project, scale: _scale, zoom: _zoom);

  double get _hOffset => _h.hasClients ? _h.offset : 0;

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _jumpH(double target) {
    if (!_h.hasClients) return;
    _h.jumpTo(target.clamp(0, _h.position.maxScrollExtent).toDouble());
  }

  void _animateH(double target) {
    if (!_h.hasClients) return;
    _h.animateTo(target.clamp(0, _h.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _goToday() {
    final axis = _axis;
    final today = DateTime.now();
    _animateH(axis.contains(today) ? axis.scrollToCenter(today, _viewportW) : 0);
  }

  void _fit() {
    setState(() => _zoom = _axis.zoomToFit(_viewportW));
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpH(0));
  }

  /// Zoome d'un facteur en gardant fixe le point de la grille sous [contentDx]
  /// (abscisse dans le contenu défilant, colonne des libellés comprise).
  void _zoomAt(double factor, double contentDx) {
    final old = _zoom;
    final nz = (old * factor).clamp(kGanttZoomMin, kGanttZoomMax).toDouble();
    if (nz == old) return;
    final timeX = contentDx - _kLabelW;
    final viewX = timeX - _hOffset;
    setState(() => _zoom = nz);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _jumpH(timeX * nz / old - viewX));
  }

  void _zoomCenter(double factor) =>
      _zoomAt(factor, _kLabelW + _hOffset + _viewportW / 2);

  void _setScale(GanttScale s) {
    if (s == _scale) return;
    final before = _axis;
    final centerDate = before.dateAt(_hOffset + _viewportW / 2);
    setState(() => _scale = s);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpH(_axis.scrollToCenter(centerDate, _viewportW)));
  }

  // Molette : défilement par défaut (géré par les Scrollable ; Maj bascule
  // l'axe nativement) ; Ctrl / ⌘ + molette = zoom autour du curseur ;
  // pincement (PointerScaleEvent, émis aussi pour Ctrl + molette sur le web)
  // = zoom. Le resolver garantit qu'un zoom ne défile pas en même temps.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScaleEvent) {
      _zoomAt(e.scale, e.localPosition.dx);
      return;
    }
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final dy = (ev as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      _zoomAt(dy < 0 ? 1.15 : 1 / 1.15, ev.localPosition.dx);
    });
  }

  void _initialScroll() {
    if (_initialScrollDone) return;
    _initialScrollDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final axis = _axis;
      final today = DateTime.now();
      _jumpH(axis.contains(today) ? axis.scrollToCenter(today, _viewportW) : 0);
    });
  }

  // ── Export PNG ─────────────────────────────────────────────────────────────

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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final axis = _axis;
    final hasPhases = widget.project.phases.isNotEmpty;
    final headerH = (hasPhases ? _kPhaseH : 0.0) + _kMonthH + _kDaysH + 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = _buildGroups(widget.project, today, _collapsed);

    return Column(
      children: [
        _toolbar(),
        const Divider(height: 1, color: kBLine),
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            _viewportW = max(0, box.maxWidth - _kLabelW);
            _initialScroll();
            return Stack(
              children: [
                // ── Contenu défilant (grille complète, exportable en PNG) ──
                Scrollbar(
                  controller: _h,
                  thumbVisibility: true,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: Scrollbar(
                    controller: _v,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _v,
                      child: SingleChildScrollView(
                        controller: _h,
                        scrollDirection: Axis.horizontal,
                        child: Listener(
                          onPointerSignal: _onPointerSignal,
                          behavior: HitTestBehavior.translucent,
                          child: RepaintBoundary(
                            key: _gridKey,
                            child: _GanttGrid(
                              project: widget.project,
                              axis: axis,
                              groups: groups,
                              domainColor: widget.domainColor,
                              headerH: headerH,
                              onTaskTap: widget.onTaskTap,
                              onPhaseTap: widget.onPhaseTap,
                              onToggleGroup: _toggleGroup,
                              blocksByTask: widget.blocksByTask,
                              today: today,
                              drag: _drag,
                              onDragStart: _dragStart,
                              onDragUpdate: _dragUpdate,
                              onDragEnd: _dragEnd,
                              onDragCancel: _dragCancel,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── En-tête figé (suit le défilement horizontal) ──────────
                Positioned(
                  left: _kLabelW,
                  right: 0,
                  top: 0,
                  height: headerH,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _h,
                      builder: (_, __) => Transform.translate(
                        offset: Offset(-_hOffset, 0),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          child: _GanttTimeHeader(
                            project: widget.project,
                            axis: axis,
                            onPhaseTap: widget.onPhaseTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Colonne des libellés figée (suit le défilement vertical)
                Positioned(
                  left: 0,
                  top: headerH,
                  bottom: 0,
                  width: _kLabelW,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _v,
                      builder: (_, __) => Transform.translate(
                        offset: Offset(0, -(_v.hasClients ? _v.offset : 0.0)),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: _GanttLabelColumn(
                            groups: groups,
                            onTaskTap: widget.onTaskTap,
                            onToggleGroup: _toggleGroup,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Coin fixe ─────────────────────────────────────────────
                Positioned(
                  left: 0,
                  top: 0,
                  width: _kLabelW,
                  height: headerH,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kBSurface,
                      border: Border(
                          right: BorderSide(color: kBLine),
                          bottom: BorderSide(color: kBLine)),
                    ),
                    alignment: Alignment.bottomLeft,
                    padding: const EdgeInsets.only(left: 16, bottom: 6),
                    child: Text(
                      '${widget.project.tasks.length} tâche${widget.project.tasks.length > 1 ? 's' : ''}'
                      ' · ${axis.totalWeeks} sem.',
                      style: const TextStyle(fontSize: 11, color: kBText4),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _toolbar() {
    final leading = widget.leading;
    return Container(
      color: kBSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (leading != null) Expanded(child: leading) else const Spacer(),
          const SizedBox(width: 12),
          _toolBtn(Icons.today_outlined, 'Aujourd\'hui — centrer sur la colonne du jour',
              _goToday),
          _toolBtn(Icons.fit_screen_outlined, 'Ajuster au projet — toute la plage dans la largeur',
              _fit),
          const SizedBox(width: 6),
          _toolBtn(Icons.remove, 'Zoom arrière (Ctrl / ⌘ + molette)',
              _zoom > kGanttZoomMin ? () => _zoomCenter(1 / 1.25) : null),
          SizedBox(
            width: 40,
            child: Text('${(_zoom * 100).round()} %',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: kBText3)),
          ),
          _toolBtn(Icons.add, 'Zoom avant (Ctrl / ⌘ + molette)',
              _zoom < kGanttZoomMax ? () => _zoomCenter(1.25) : null),
          const SizedBox(width: 10),
          SegmentedButton<GanttScale>(
            segments: const [
              ButtonSegment(value: GanttScale.week, label: Text('Semaine')),
              ButtonSegment(value: GanttScale.day, label: Text('Jour')),
            ],
            selected: {_scale},
            showSelectedIcon: false,
            onSelectionChanged: (s) => _setScale(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
              foregroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? kBBg : kBText2),
              backgroundColor: WidgetStateProperty.resolveWith((s) =>
                  s.contains(WidgetState.selected) ? kBPrimary : Colors.transparent),
              side: WidgetStateProperty.all(const BorderSide(color: kBLine)),
            ),
          ),
          const SizedBox(width: 6),
          _exportingPng
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBPrimary)),
                )
              : PopupMenuButton<String>(
                  tooltip: 'Plus',
                  icon: const Icon(Icons.more_horiz, size: 18, color: kBText2),
                  color: kBRaised,
                  onSelected: (v) {
                    switch (v) {
                      case 'png':
                        _exportPng();
                      case 'pdf':
                        widget.onExportPdf();
                      case 'domain':
                        widget.onChangeDomain?.call();
                    }
                  },
                  itemBuilder: (_) => [
                    _menuItem('png', Icons.image_outlined, 'Exporter en PNG'),
                    _menuItem('pdf', Icons.picture_as_pdf_outlined, 'Exporter en PDF'),
                    if (widget.onChangeDomain != null)
                      _menuItem('domain', Icons.move_to_inbox_outlined, 'Changer de domaine'),
                  ],
                ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label) =>
      PopupMenuItem(
        value: v,
        height: 38,
        child: Row(children: [
          Icon(icon, size: 16, color: kBText2),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: kBText)),
        ]),
      );

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback? onTap) => Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 18),
          color: kBText2,
          disabledColor: kBText4.withOpacity(.5),
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        ),
      );
}

// ── Grille complète (contenu défilant) ───────────────────────────────────────

class _GanttGrid extends StatelessWidget {
  final Project project;
  final GanttAxis axis;
  final List<_GanttGroup> groups;
  final Color? domainColor;
  final double headerH;
  final void Function(ProjectTask)? onTaskTap;
  final void Function(ProjectPhase)? onPhaseTap;
  final void Function(String key) onToggleGroup;
  final Map<String, List<_DatedBlock>> blocksByTask;
  final DateTime today;
  final _BarDrag? drag;
  final void Function(ProjectTask, bool resize) onDragStart;
  final void Function(double dx) onDragUpdate;
  final void Function(ProjectTask) onDragEnd;
  final VoidCallback onDragCancel;

  const _GanttGrid({
    required this.project,
    required this.axis,
    required this.groups,
    this.domainColor,
    required this.headerH,
    this.onTaskTap,
    this.onPhaseTap,
    required this.onToggleGroup,
    required this.blocksByTask,
    required this.today,
    this.drag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  // Couleur de repli d'une barre quand la tâche n'a pas de couleur propre :
  // couleur de sa phase → couleur du domaine → violet.
  Color _taskFallbackColor(ProjectTask task) {
    final phase = project.phases.where((p) => p.id == task.phaseId).firstOrNull ??
        project.phases.where((p) => p.label == task.groupLabel).firstOrNull;
    return _hex(phase?.color, domainColor ?? const Color(0xFF6B57F0));
  }

  @override
  Widget build(BuildContext context) {
    final timeW = axis.width;
    final totalW = _kLabelW + timeW;

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          if (group.showHeader)
            SizedBox(
              height: _kGroupH,
              width: totalW,
              child: Row(children: [
                _GroupLabelCell(group: group, onTap: () => onToggleGroup(group.key)),
                _GroupBarCell(
                    group: group,
                    axis: axis,
                    color: _hex(group.phase?.color, domainColor ?? kBText4)),
              ]),
            ),
          if (!group.collapsed)
            for (final task in group.tasks)
            SizedBox(
              height: _kRowH,
              width: totalW,
              child: Row(children: [
                _TaskLabelCell(
                    task: task,
                    overdue: isTaskOverdue(task, today),
                    onTap: onTaskTap != null ? () => onTaskTap!(task) : null),
                _TaskBarCell(
                  task: task,
                  axis: axis,
                  fallbackColor: _taskFallbackColor(task),
                  overdue: isTaskOverdue(task, today),
                  blocks: blocksByTask[task.id] ?? const [],
                  drag: drag?.taskId == task.id ? drag : null,
                  onTap: onTaskTap != null ? () => onTaskTap!(task) : null,
                  onDragStart: (resize) => onDragStart(task, resize),
                  onDragUpdate: onDragUpdate,
                  onDragEnd: () => onDragEnd(task),
                  onDragCancel: onDragCancel,
                ),
              ]),
            ),
        ],
        SizedBox(height: 24, width: totalW),
      ],
    );

    return Container(
      color: kBBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerH,
            width: totalW,
            child: Row(children: [
              const SizedBox(width: _kLabelW),
              _GanttTimeHeader(project: project, axis: axis, onPhaseTap: onPhaseTap),
            ]),
          ),
          Stack(
            children: [
              rows,
              // Week-ends ombrés (vue Jour) et colonne d'aujourd'hui.
              Positioned.fill(
                left: _kLabelW,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ColumnsPainter(axis: axis, today: today),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fond de la zone de temps : week-ends (vue Jour) + colonne d'aujourd'hui.
class _ColumnsPainter extends CustomPainter {
  final GanttAxis axis;
  final DateTime today;
  _ColumnsPainter({required this.axis, required this.today});

  @override
  void paint(Canvas canvas, Size size) {
    if (axis.scale == GanttScale.day && axis.dayW >= 6) {
      final we = Paint()..color = Colors.white.withOpacity(.025);
      for (var i = 0; i < axis.totalDays; i++) {
        final d = axis.rangeStart.add(Duration(days: i));
        if (d.weekday >= DateTime.saturday) {
          canvas.drawRect(Rect.fromLTWH(i * axis.dayW, 0, axis.dayW, size.height), we);
        }
      }
    }
    if (axis.contains(today)) {
      final x = axis.x(today);
      canvas.drawRect(Rect.fromLTWH(x, 0, axis.dayW, size.height),
          Paint()..color = kBPrimary.withOpacity(.07));
      final line = Paint()
        ..color = kBPrimary.withOpacity(.35)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(x + axis.dayW, 0), Offset(x + axis.dayW, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) =>
      old.axis.dayW != axis.dayW ||
      old.axis.rangeStart != axis.rangeStart ||
      old.axis.totalDays != axis.totalDays ||
      old.axis.scale != axis.scale ||
      old.today != today;
}

// ── En-tête de la zone de temps : phases · mois · jours ou semaines ──────────

class _GanttTimeHeader extends StatelessWidget {
  final Project project;
  final GanttAxis axis;
  final void Function(ProjectPhase)? onPhaseTap;
  const _GanttTimeHeader({required this.project, required this.axis, this.onPhaseTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timeW = axis.width;
    return Container(
      width: timeW,
      decoration: const BoxDecoration(
        color: kBSurface,
        border: Border(bottom: BorderSide(color: kBLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project.phases.isNotEmpty) _phasesRow(timeW),
          _monthsRow(timeW, today),
          if (axis.scale == GanttScale.day) _daysRow(today) else _weeksRow(today),
        ],
      ),
    );
  }

  Widget _phasesRow(double timeW) {
    return SizedBox(
      height: _kPhaseH,
      width: timeW,
      child: Stack(
        children: project.phases.map((phase) {
          final left = max(0.0, axis.x(phase.startDate));
          final right = min(timeW, axis.x(phase.endDate.add(const Duration(days: 1))));
          final w = max(0.0, right - left);
          final c = _hex(phase.color, kBPrimaryDark);
          final fg = _onDark(c);
          return Positioned(
            left: left,
            top: 3,
            width: w,
            height: _kPhaseH - 5,
            child: Tooltip(
              message: '${phase.label}\n${_dmy(phase.startDate)} → ${_dmy(phase.endDate)}'
                  '${onPhaseTap != null ? '\nCliquer pour renommer' : ''}',
              waitDuration: const Duration(milliseconds: 500),
              child: MouseRegion(
                cursor: onPhaseTap != null ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  onTap: onPhaseTap != null ? () => onPhaseTap!(phase) : null,
                  child: Container(
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      color: c.withOpacity(.22),
                      borderRadius: BorderRadius.circular(4),
                      border: Border(left: BorderSide(color: c, width: 2)),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      phase.label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _monthsRow(double timeW, DateTime today) {
    final segs = axis.monthSegments();
    return SizedBox(
      height: _kMonthH,
      width: timeW,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              for (final s in segs)
                Container(
                  width: s.days * axis.dayW,
                  height: _kMonthH,
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: kBLine)),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    s.days * axis.dayW < 60 ? '' : s.label,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: kBText2),
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
          if (axis.contains(today))
            Positioned(
              left: axis.x(today) + axis.dayW / 2 - 14,
              top: 3,
              child: Container(
                width: 28,
                padding: const EdgeInsets.symmetric(vertical: 1),
                decoration: BoxDecoration(
                  color: kBPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('auj.',
                    style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700, color: kBBg)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _daysRow(DateTime today) {
    final w = axis.dayW;
    // En zoom arrière, n'étiqueter que les lundis pour rester lisible.
    final every = w >= 18 ? 1 : 7;
    return SizedBox(
      height: _kDaysH,
      child: Row(
        children: List.generate(axis.totalDays, (i) {
          final d = axis.rangeStart.add(Duration(days: i));
          final weekend = d.weekday >= DateTime.saturday;
          final isToday = d == today;
          final labelled = every == 1 || d.weekday == DateTime.monday;
          return Container(
            width: w,
            height: _kDaysH,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: d.weekday == DateTime.monday ? kBLine : Colors.transparent),
              ),
            ),
            alignment: Alignment.center,
            child: !labelled
                ? null
                : isToday
                    ? Container(
                        width: min(w - 2, 22),
                        height: 18,
                        decoration: BoxDecoration(
                          color: kBPrimary.withOpacity(.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text('${d.day}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: kBPrimary)),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${d.day}',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: weekend ? kBText4 : kBText3)),
                          if (w >= 24)
                            Text(kGanttWeekdayInitials[d.weekday - 1],
                                style: TextStyle(
                                    fontSize: 8,
                                    color: (weekend ? kBText4 : kBText3).withOpacity(.7))),
                        ],
                      ),
          );
        }),
      ),
    );
  }

  Widget _weeksRow(DateTime today) {
    final w = axis.dayW * 7;
    return SizedBox(
      height: _kDaysH,
      child: Row(
        children: axis.weekStarts().map((monday) {
          final isCurrent = !today.isBefore(monday) &&
              today.isBefore(monday.add(const Duration(days: 7)));
          return Container(
            width: w,
            height: _kDaysH,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: kBLine)),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              w < 48 ? '${monday.day}' : ganttWeekLabel(monday),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent ? kBPrimary : kBText3),
              overflow: TextOverflow.clip,
              softWrap: false,
              maxLines: 1,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Colonne des libellés (overlay figé) ───────────────────────────────────────

class _GanttLabelColumn extends StatelessWidget {
  final List<_GanttGroup> groups;
  final void Function(ProjectTask)? onTaskTap;
  final void Function(String key) onToggleGroup;
  const _GanttLabelColumn(
      {required this.groups, this.onTaskTap, required this.onToggleGroup});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kLabelW,
      decoration: const BoxDecoration(
        color: kBBg,
        border: Border(right: BorderSide(color: kBLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups) ...[
            if (group.showHeader)
              SizedBox(
                  height: _kGroupH,
                  child: _GroupLabelCell(
                      group: group, onTap: () => onToggleGroup(group.key))),
            if (!group.collapsed)
              for (final task in group.tasks)
                SizedBox(
                  height: _kRowH,
                  child: _TaskLabelCell(
                      task: task,
                      overdue: isTaskOverdue(task, DateTime.now()),
                      onTap: onTaskTap != null ? () => onTaskTap!(task) : null),
                ),
          ],
        ],
      ),
    );
  }
}

// ── Cellules ──────────────────────────────────────────────────────────────────

class _GroupLabelCell extends StatelessWidget {
  final _GanttGroup group;
  final VoidCallback onTap;
  const _GroupLabelCell({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Tooltip(
      message: g.collapsed ? 'Déplier la phase' : 'Replier la phase',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: _kLabelW,
          height: _kGroupH,
          color: kBRaised.withOpacity(.45),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 6, right: 8),
          child: Row(children: [
            Icon(g.collapsed ? Icons.chevron_right : Icons.expand_more, size: 14, color: kBText3),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                g.label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: kBText3, letterSpacing: 0.8),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (g.overdue > 0) ...[
              Text('${g.overdue} en retard',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: kBAlert)),
              const SizedBox(width: 6),
            ],
            Text('${g.done}/${g.total}',
                style: const TextStyle(fontSize: 10, color: kBText4)),
          ]),
        ),
      ),
    );
  }
}

/// Zone de temps d'une ligne de phase : trait résumé de la première à la
/// dernière tâche (lisible même replié) et progression.
class _GroupBarCell extends StatelessWidget {
  final _GanttGroup group;
  final GanttAxis axis;
  final Color color;
  const _GroupBarCell({required this.group, required this.axis, required this.color});

  @override
  Widget build(BuildContext context) {
    final span = group.span;
    final pct = group.total == 0 ? 0.0 : group.done / group.total;
    return Container(
      width: axis.width,
      height: _kGroupH,
      decoration: BoxDecoration(
        color: kBRaised.withOpacity(.45),
        border: const Border(bottom: BorderSide(color: kBLine)),
      ),
      child: span == null
          ? null
          : Stack(children: [
              Positioned(
                left: axis.x(span.start),
                width: max(4.0, axis.x(span.end.add(const Duration(days: 1))) - axis.x(span.start)),
                top: _kGroupH / 2 - 3,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(children: [
                    Positioned.fill(child: ColoredBox(color: color.withOpacity(.25))),
                    FractionallySizedBox(
                        widthFactor: pct.clamp(0.0, 1.0),
                        child: ColoredBox(color: color.withOpacity(.85))),
                  ]),
                ),
              ),
            ]),
    );
  }
}

class _TaskLabelCell extends StatelessWidget {
  final ProjectTask task;
  final bool overdue;
  final VoidCallback? onTap;
  const _TaskLabelCell({required this.task, this.overdue = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    return SizedBox(
      width: _kLabelW,
      height: _kRowH,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kBLine)),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              if (task.isMilestone)
                const Icon(Icons.diamond_outlined, size: 12, color: kBText3)
              else
                Icon(
                  isDone ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                  size: 12,
                  color: isDone ? kBPrimary : kBText4,
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDone ? kBText4 : kBText,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: kBText4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (overdue)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.warning_amber_rounded, size: 12, color: kBAlert),
                ),
              if (task.stepsTotal > 0)
                Text('${task.stepsDone}/${task.stepsTotal}',
                    style: const TextStyle(fontSize: 9, color: kBText4)),
              if (onTap != null)
                const Icon(Icons.chevron_right, size: 12, color: kBText4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glisser en cours : barre [taskId], poignée droite si [resize], décalage
/// cumulé [dx] en pixels.
class _BarDrag {
  final String taskId;
  final bool resize;
  final double dx;
  const _BarDrag(this.taskId, this.resize, [this.dx = 0]);
}

class _TaskBarCell extends StatelessWidget {
  final ProjectTask task;
  final GanttAxis axis;
  final Color fallbackColor;
  final bool overdue;
  final List<_DatedBlock> blocks;
  final _BarDrag? drag;
  final VoidCallback? onTap;
  final void Function(bool resize) onDragStart;
  final void Function(double dx) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  const _TaskBarCell({
    required this.task,
    required this.axis,
    required this.fallbackColor,
    this.overdue = false,
    this.blocks = const [],
    this.drag,
    this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  int get _previewDays => drag == null ? 0 : (drag!.dx / axis.dayW).round();

  String get _tip {
    final d = _previewDays;
    final start = task.startDate.add(Duration(days: drag != null && !drag!.resize ? d : 0));
    final visEnd = task.endDate ?? (task.isMilestone ? null : task.startDate.add(const Duration(days: 7)));
    final end = visEnd?.add(Duration(days: drag != null ? d : 0));
    final lines = <String>[task.title];
    if (task.isMilestone) {
      lines.add(_dmy(start));
    } else {
      final days = end == null ? null : end.difference(start).inDays + 1;
      lines.add('${_dmy(start)}${end != null ? ' → ${_dmy(end)} · $days j' : ' · sans échéance'}'
          '${task.endDate == null && !task.isMilestone ? ' (barre indicative : 7 j)' : ''}');
      lines.add('Estimé ${fmtMin(task.plannedMin)}'
          '${task.stepsTotal > 0 ? ' · ${task.stepsDone}/${task.stepsTotal} action${task.stepsTotal > 1 ? 's' : ''}' : ''}'
          '${task.status == 'done' ? ' · terminée' : task.status == 'skipped' ? ' · ignorée' : overdue ? ' · EN RETARD' : ''}');
      if (blocks.isNotEmpty) {
        final done = blocks.where((b) => b.block.status == 'done').length;
        final min = blocks.fold<int>(0, (s, b) => s + b.block.durationMin);
        lines.add('${blocks.length} bloc${blocks.length > 1 ? 's' : ''} du programme · ${fmtMin(min)}'
            '${done > 0 ? ' · $done fait${done > 1 ? 's' : ''}' : ''}');
      }
    }
    if (drag == null) {
      lines.add(task.isMilestone
          ? 'Clic = fiche · glisser = déplacer'
          : 'Clic = fiche · glisser = déplacer · bord droit = échéance');
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    return SizedBox(
      width: axis.width,
      height: _kRowH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: kBLine)),
              ),
            ),
          ),
          if (task.isMilestone) _buildMilestone() else ..._buildBar(isDone),
        ],
      ),
    );
  }

  Widget _gestures({required Widget child, required bool resize, MouseCursor? cursor}) {
    final dragging = drag != null;
    return MouseRegion(
      cursor: cursor ??
          (dragging && !drag!.resize ? SystemMouseCursors.grabbing : SystemMouseCursors.grab),
      child: Tooltip(
        message: _tip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: resize ? null : onTap,
          onHorizontalDragStart: (_) => onDragStart(resize),
          onHorizontalDragUpdate: (d) => onDragUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd(),
          onHorizontalDragCancel: onDragCancel,
          child: child,
        ),
      ),
    );
  }

  List<Widget> _buildBar(bool isDone) {
    final d = _previewDays;
    final shift = drag != null && !drag!.resize ? d : 0;
    final grow = drag != null ? d : 0;
    final start = task.startDate.add(Duration(days: shift));
    final baseEnd = task.endDate ?? task.startDate.add(const Duration(days: 7));
    var end = baseEnd.add(Duration(days: grow));
    if (end.isBefore(start)) end = start;
    final left = axis.x(start);
    final right = axis.x(end.add(const Duration(days: 1)));
    final barW = max(4.0, right - left);
    final dragging = drag != null;

    final barColor = isDone ? kBText4.withOpacity(.45) : _hex(task.color, fallbackColor);
    final textColor = _isDark(barColor)
        ? Colors.white.withOpacity(0.9)
        : Colors.black.withOpacity(0.7);
    // Progression : actions cochées (sinon 0 ou 1 selon le statut).
    final pct = isDone
        ? 1.0
        : task.stepsTotal > 0
            ? task.stepsDone / task.stepsTotal
            : 0.0;
    final label = task.barLabel ?? task.title;
    // Barre trop courte pour son titre : le texte déborde à droite.
    final labelOutside = barW < 72;
    const barH = _kRowH - _kBarVPad * 2;

    return [
      Positioned(
        left: left,
        top: _kBarVPad,
        height: barH,
        width: barW,
        child: _gestures(
          resize: false,
          child: Container(
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(3),
              border: dragging
                  ? Border.all(color: Colors.white.withOpacity(.7))
                  : overdue
                      ? Border.all(color: kBAlert, width: 1.5)
                      : null,
              boxShadow: isDone
                  ? null
                  : [BoxShadow(color: (overdue ? kBAlert : barColor).withOpacity(0.35), blurRadius: 8)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              if (pct > 0 && pct < 1)
                FractionallySizedBox(
                  widthFactor: pct,
                  child: ColoredBox(color: Colors.white.withOpacity(.22)),
                ),
              if (!labelOutside)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: textColor),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      if (labelOutside)
        Positioned(
          left: left + barW + 8,
          top: _kBarVPad,
          height: barH,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(label,
                  style: TextStyle(fontSize: 10, color: overdue ? kBAlert : kBText3),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false),
            ),
          ),
        ),
      // Points des blocs du programme, sous la barre, à la date de chaque bloc.
      for (final db in blocks)
        Positioned(
          left: axis.x(db.date) + axis.dayW / 2 - 4,
          top: _kRowH - _kBarVPad + 1,
          width: 8,
          height: 6,
          child: _blockDot(db),
        ),
      // Poignée droite : tirer pour changer l'échéance.
      Positioned(
        left: left + barW - 5,
        top: _kBarVPad,
        height: _kRowH - _kBarVPad * 2,
        width: 8,
        child: _gestures(
          resize: true,
          cursor: SystemMouseCursors.resizeLeftRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(dragging && drag!.resize ? .9 : .45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _blockDot(_DatedBlock db) {
    final b = db.block;
    final done = b.status == 'done';
    final skipped = b.status == 'skipped';
    return Tooltip(
      message: '${_dmy(db.date)} · ${b.startTime} · ${fmtMin(b.durationMin)}'
          ' · ${done ? 'fait' : skipped ? 'sauté' : 'à venir'}',
      waitDuration: const Duration(milliseconds: 400),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: done ? kBPrimary : skipped ? Colors.transparent : kBBg,
            shape: BoxShape.circle,
            border: Border.all(
                color: skipped ? kBText4 : kBPrimary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildMilestone() {
    final start = task.startDate.add(Duration(days: _previewDays));
    final centerX = axis.x(start) + axis.dayW / 2;
    final color = _hex(task.color, fallbackColor);
    const size = 13.0;
    const hit = 24.0;

    return Positioned(
      left: centerX - hit / 2,
      top: _kRowH / 2 - hit / 2,
      width: hit,
      height: hit,
      child: _gestures(
        resize: false,
        child: Center(
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                border: drag != null ? Border.all(color: Colors.white.withOpacity(.8)) : null,
                boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 10, spreadRadius: 1)],
              ),
            ),
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

/// Variante lisible sur fond sombre (luminosité ≥ 0.72).
Color _onDark(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness(max(hsl.lightness, 0.72)).toColor();
}

bool _isDark(Color c) => c.computeLuminance() < 0.4;


String _dmy(DateTime d) => '${d.day} ${kGanttMonthsShort[d.month - 1]} ${d.year}';

/// Bloc du programme daté (le doc `daily_schedules` porte la date).
class _DatedBlock {
  final DateTime date;
  final ScheduleBlock block;
  const _DatedBlock(this.date, this.block);
}

/// Section du Gantt = phase (ou « Sans phase »), avec ses tâches en ordre
/// Gantt et ses compteurs.
class _GanttGroup {
  final ProjectPhase? phase;
  final List<ProjectTask> tasks;
  final bool collapsed;
  final int done;
  final int total;
  final int overdue;
  /// Faux quand le projet n'a aucune phase : la liste est plate.
  final bool showHeader;
  const _GanttGroup({
    required this.phase,
    required this.tasks,
    required this.collapsed,
    required this.done,
    required this.total,
    required this.overdue,
    required this.showHeader,
  });

  String get key => phase?.id ?? '_none';
  String get label => phase?.label ?? 'Sans phase';

  /// Étendue des tâches (début min → fin visuelle max), null si vide.
  ({DateTime start, DateTime end})? get span {
    if (tasks.isEmpty) return null;
    DateTime? s, e;
    for (final t in tasks) {
      final ts = DateTime(t.startDate.year, t.startDate.month, t.startDate.day);
      final te = taskVisualEnd(t).subtract(const Duration(days: 1));
      if (s == null || ts.isBefore(s)) s = ts;
      if (e == null || te.isAfter(e)) e = te;
    }
    return (start: s!, end: e!);
  }
}

List<_GanttGroup> _buildGroups(Project p, DateTime today, Set<String> collapsed) {
  final sections = phaseSections(p);
  final flat = p.phases.isEmpty;
  return [
    for (final sec in sections)
      _GanttGroup(
        phase: sec.phase,
        tasks: sec.tasks,
        collapsed: !flat && collapsed.contains(sec.phase?.id ?? '_none'),
        done: sec.tasks.where((t) => t.status == 'done').length,
        total: sec.tasks.where((t) => t.status != 'skipped').length,
        overdue: sec.tasks.where((t) => isTaskOverdue(t, today)).length,
        showHeader: !flat,
      ),
  ];
}

// ── Bandeau d'état (aligné sur project_health, comme l'onglet Projets) ───────

class _GanttDashboard extends StatelessWidget {
  final Project project;
  const _GanttDashboard({required this.project});

  @override
  Widget build(BuildContext context) {
    final p = project;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final prog = taskProgress(p);
    final pct = prog.total == 0 ? 0 : (prog.done * 100 / prog.total).round();
    final overdue = overdueTasks(p, today);
    final phase = currentPhase(p, today);
    final milestone = nextMilestone(p, today);
    final msDays = milestone == null
        ? null
        : (milestone.endDate ?? milestone.startDate).difference(today).inDays;
    final left = p.endDate == null ? null : daysLeftLabel(p.endDate, today);

    return Container(
      color: kBSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        _chip(Icons.task_alt_outlined,
            prog.total == 0 ? 'Aucune tâche' : '${prog.done} / ${prog.total} · $pct %',
            tip: 'Avancement : tâches faites / tâches comptées (hors ignorées)'),
        if (overdue.isNotEmpty)
          _chip(Icons.warning_amber_rounded,
              '${overdue.length} en retard',
              color: kBAlert,
              tip: 'Tâches ouvertes dont l\'échéance est passée'),
        if (phase != null)
          _chip(Icons.layers_outlined, 'Phase : ${phase.label}',
              color: _onDark(_hex(phase.color, kBPrimary)),
              tip: 'Phase contenant aujourd\'hui'),
        if (milestone != null)
          _chip(Icons.diamond_outlined, 'J-$msDays · ${milestone.title}',
              color: msDays != null && msDays <= 7 ? kBAttention : null,
              tip: 'Prochain jalon'),
        const Spacer(),
        if (left != null)
          Text('Fin du projet ${_dmy(p.endDate!)} · $left',
              style: const TextStyle(fontSize: 11, color: kBText4)),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, {Color? color, required String tip}) {
    final c = color ?? kBText2;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withOpacity(color == null ? .08 : .14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ── Dialog détail tâche (web) ─────────────────────────────────────────────────

class _TaskDetailDialog extends StatefulWidget {
  final Project project;
  final ProjectTask task;
  final FirestoreSync sync;
  final void Function(Project) onProjectUpdated;
  // Mode panneau latéral (lot 3) : la fiche vit à droite du Gantt au lieu
  // d'une Dialog 720×360 — onClose remplace alors le Navigator.pop.
  final bool panel;
  final VoidCallback? onClose;

  const _TaskDetailDialog({
    super.key,
    required this.project,
    required this.task,
    required this.sync,
    required this.onProjectUpdated,
    this.panel = false,
    this.onClose,
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
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _loadDocs();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // Fermer la fiche : panneau → callback ; Dialog → pop.
  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _loadDocs() async {
    final docs = await widget.sync.fetchDocuments(taskId: _task.id);
    if (mounted) setState(() { _docs = docs; _loadingDocs = false; });
  }

  ProjectPhase? get _currentPhase =>
      widget.project.phases.where((p) => p.id == _task.phaseId).firstOrNull;

  Future<void> _changePhase() async {
    final cs = Theme.of(context).colorScheme;
    final phases = widget.project.phases;
    if (phases.isEmpty) return;

    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Changer de phase'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(children: [
              Icon(Icons.layers_clear_outlined, size: 14, color: cs.onSurface.withOpacity(.4)),
              const SizedBox(width: 10),
              Text('Aucune phase', style: TextStyle(color: cs.onSurface.withOpacity(.5))),
            ]),
          ),
          const Divider(height: 1),
          for (final p in phases)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p.id),
              child: Row(children: [
                Container(
                  width: 10, height: 10,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: _hex(p.color, const Color(0xFF6B57F0)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(p.label, style: TextStyle(
                  fontWeight: _task.phaseId == p.id ? FontWeight.bold : FontWeight.normal,
                )),
                if (_task.phaseId == p.id) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: cs.primary),
                ],
              ]),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final newPhaseId = selected.isEmpty ? null : selected;
    final newPhase = phases.where((p) => p.id == newPhaseId).firstOrNull;
    setState(() {
      _task.phaseId = newPhaseId;
      _task.groupLabel = newPhase?.label; // synchronise le groupe visuel dans le Gantt
    });
    _save();
  }

  Future<void> _pickColor() async {
    const presets = [
      '#6B57F0', '#1D9E75', '#E53935', '#F4A01D',
      '#2196F3', '#9C27B0', '#00BCD4', '#4CAF50',
      '#FF5722', '#795548', '#607D8B', '#EC407A',
    ];

    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final phase = _currentPhase;
        return AlertDialog(
          title: const Text('Couleur de la barre'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phase?.color != null) ...[
                InkWell(
                  onTap: () => Navigator.pop(ctx, phase.color),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(children: [
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: _hex(phase!.color, Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Couleur de la phase "${phase.label}"',
                          style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                ),
                const Divider(),
              ],
              Wrap(
                spacing: 8, runSpacing: 8,
                children: presets.map((hex) {
                  final isSelected = _task.color == hex;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, hex),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: _hex(hex, Colors.grey),
                        borderRadius: BorderRadius.circular(6),
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 2.5)
                            : Border.all(color: Colors.black12),
                        boxShadow: isSelected
                            ? [const BoxShadow(color: Colors.black26, blurRadius: 4)]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ],
        );
      },
    );
    if (picked == null) return;
    setState(() => _task.color = picked);
    _save();
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

  /// Renommer la tâche (clic sur le titre).
  Future<void> _renameTask() async {
    final ctrl = TextEditingController(text: _task.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la tâche'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder()),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || title.isEmpty || title == _task.title || !mounted) return;
    setState(() => _task.title = title);
    await _save();
  }

  /// Modifier début et échéance (clic sur la ligne des dates). Un jalon n'a
  /// qu'une date ; une tâche sans échéance peut en recevoir une.
  Future<void> _editDates() async {
    final start = DateTime(_task.startDate.year, _task.startDate.month, _task.startDate.day);
    if (_task.isMilestone) {
      final picked = await showDatePicker(
        context: context,
        initialDate: start,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Date du jalon',
      );
      if (picked == null || !mounted) return;
      setState(() => _task.startDate = DateTime(picked.year, picked.month, picked.day));
      await _save();
      return;
    }
    final end = _task.endDate;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
          start: start,
          end: end == null ? start : DateTime(end.year, end.month, end.day)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Début → échéance',
      saveText: 'Enregistrer',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _task.startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _task.endDate = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _save();
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

  // ── Opérations structurelles (déplacer / promouvoir) ──────────────────────
  // Les helpers FirestoreSync relisent Firestore (autoritatif) puis écrivent ;
  // ici on reflète le retrait local + on notifie le parent (pas de _save() en
  // plus, pour éviter une double écriture).

  Future<Project?> _pickProject(String title, {String? excludeId}) async {
    final projects = await widget.sync.fetchProjects();
    if (!mounted) return null;
    final candidates = projects
        .where((p) => p.id != excludeId && p.status != 'archived')
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun autre projet disponible.')));
      return null;
    }
    return showDialog<Project>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final p in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.title),
            ),
        ],
      ),
    );
  }

  Future<ProjectTask?> _pickTask(Project project, {String? excludeTaskId}) async {
    final tasks =
        project.tasks.where((t) => t.id != excludeTaskId).toList();
    if (!mounted) return null;
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('« ${project.title} » n\'a aucune autre tâche.')));
      return null;
    }
    return showDialog<ProjectTask>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SimpleDialog(
        title: Text('Tâche cible — ${project.title}'),
        children: [
          for (final t in tasks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(t.title),
            ),
        ],
      ),
    );
  }

  Future<void> _moveTaskToAnotherProject() async {
    final target = await _pickProject('Déplacer la tâche vers…',
        excludeId: widget.project.id);
    if (target == null) return;
    setState(() => _saving = true);
    await widget.sync
        .moveTaskToProject(widget.project.id, target.id, _task.id);
    widget.project.tasks.removeWhere((t) => t.id == _task.id);
    widget.onProjectUpdated(widget.project);
    if (!mounted) return;
    _close(); // la tâche a quitté ce projet → on ferme la fiche
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Tâche déplacée vers « ${target.title} ».')));
  }

  Future<void> _moveActionToAnotherTask(TaskAction a) async {
    final target = await _pickProject('Déplacer l\'action vers…');
    if (target == null) return;
    final excludeTaskId =
        target.id == widget.project.id ? _task.id : null;
    final targetTask = await _pickTask(target, excludeTaskId: excludeTaskId);
    if (targetTask == null) return;
    setState(() => _saving = true);
    await widget.sync.moveActionToTask(
      fromProjectId: widget.project.id,
      fromTaskId: _task.id,
      toProjectId: target.id,
      toTaskId: targetTask.id,
      actionId: a.id,
    );
    _task.actions.removeWhere((x) => x.id == a.id);
    if (target.id == widget.project.id) {
      widget.project.tasks
          .where((t) => t.id == targetTask.id)
          .firstOrNull
          ?.actions
          .add(a);
    }
    widget.onProjectUpdated(widget.project);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Action déplacée vers « ${targetTask.title} ».')));
  }

  Future<void> _promoteActionToSubproject(TaskAction a) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Promouvoir en sous-projet'),
        content: Text(
            'Créer un sous-projet « ${a.title} » sous « ${widget.project.title} » ? '
            'L\'action sera retirée de cette tâche.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final child = await widget.sync.promoteActionToSubproject(
      parentProjectId: widget.project.id,
      taskId: _task.id,
      actionId: a.id,
    );
    _task.actions.removeWhere((x) => x.id == a.id);
    widget.onProjectUpdated(widget.project);
    if (!mounted) return;
    setState(() => _saving = false);
    if (child != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sous-projet « ${child.title} » créé.')));
    }
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
    final isFilesTab   = _tabCtrl.index == 2;
    final isDoneTab    = _tabCtrl.index == 1;

    final Widget body = Column(
          mainAxisSize: widget.panel ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        Tooltip(
                          message: 'Renommer la tâche',
                          waitDuration: const Duration(milliseconds: 600),
                          child: InkWell(
                            onTap: _renameTask,
                            borderRadius: BorderRadius.circular(4),
                            child: Text(_task.title,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Tooltip(
                          message: _task.isMilestone
                              ? 'Modifier la date du jalon'
                              : 'Modifier le début et l\'échéance',
                          waitDuration: const Duration(milliseconds: 600),
                          child: InkWell(
                            onTap: _editDates,
                            borderRadius: BorderRadius.circular(4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                '${_fmtDate(_task.startDate)}'
                                '${_task.endDate != null ? ' → ${_fmtDate(_task.endDate!)}' : _task.isMilestone ? '' : ' · sans échéance'}',
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.edit_calendar_outlined, size: 12,
                                  color: cs.onSurface.withOpacity(.35)),
                            ]),
                          ),
                        ),
                        // Phase (si le projet en a)
                        if (widget.project.phases.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _changePhase,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_currentPhase != null)
                                  Container(
                                    width: 8, height: 8,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      color: _hex(_currentPhase!.color, cs.primary),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  )
                                else
                                  Icon(Icons.layers_outlined, size: 12,
                                      color: cs.onSurface.withOpacity(.35)),
                                const SizedBox(width: 3),
                                Text(
                                  _currentPhase?.label ?? 'Assigner à une phase',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _currentPhase != null
                                        ? _hex(_currentPhase!.color, cs.primary)
                                        : cs.onSurface.withOpacity(.35),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.edit_outlined, size: 10,
                                    color: cs.onSurface.withOpacity(.25)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(right: 8, top: 4),
                      child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  // Swatch couleur de la barre
                  Tooltip(
                    message: 'Couleur de la barre',
                    child: GestureDetector(
                      onTap: _pickColor,
                      child: Container(
                        width: 20, height: 20,
                        margin: const EdgeInsets.only(top: 6, right: 4),
                        decoration: BoxDecoration(
                          color: _hex(_task.color, cs.primary),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(.5), width: 1),
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    icon: Icon(Icons.drive_file_move_outline,
                        color: cs.onSurface.withOpacity(.4)),
                    onSelected: (v) {
                      if (v == 'move_task') _moveTaskToAnotherProject();
                      if (v == 'dates') _editDates();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'move_task',
                        child: Text('Déplacer vers un autre projet'),
                      ),
                      PopupMenuItem(
                        value: 'dates',
                        child: Text(_task.isMilestone ? 'Modifier la date' : 'Modifier les dates'),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: cs.onSurface.withOpacity(.4)),
                    tooltip: 'Supprimer la tâche',
                    onPressed: () => _confirmDeleteTask(cs),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _close,
                  ),
                ],
              ),
            ),

            // ── Statut ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Row(
                children: [
                  for (final (status, label, icon) in [
                    ('pending',  'En cours',  Icons.radio_button_unchecked),
                    ('done',     'Terminée',  Icons.check_circle_outline),
                    ('skipped',  'Ignorée',   Icons.block_outlined),
                  ]) ...[
                    InkWell(
                      onTap: () {
                        if (_task.status == status) return;
                        setState(() => _task.status = status);
                        _save();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _task.status == status
                              ? (status == 'done'
                                  ? Colors.green.withOpacity(.15)
                                  : status == 'skipped'
                                      ? Colors.orange.withOpacity(.12)
                                      : Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withOpacity(.6))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _task.status == status
                                ? (status == 'done'
                                    ? Colors.green.withOpacity(.4)
                                    : status == 'skipped'
                                        ? Colors.orange.withOpacity(.4)
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(.4))
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withOpacity(.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 14,
                              color: _task.status == status
                                  ? (status == 'done'
                                      ? Colors.green.shade600
                                      : status == 'skipped'
                                          ? Colors.orange.shade700
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(.4),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _task.status == status
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: _task.status == status
                                    ? (status == 'done'
                                        ? Colors.green.shade600
                                        : status == 'skipped'
                                            ? Colors.orange.shade700
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary)
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

            // Description (éditable au tap)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: GestureDetector(
                onTap: _editDescription,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _task.description?.isNotEmpty == true
                              ? _task.description!
                              : 'Ajouter une description…',
                          style: TextStyle(
                            fontSize: 12,
                            color: _task.description?.isNotEmpty == true
                                ? cs.onSurface.withOpacity(.75)
                                : cs.onSurface.withOpacity(.35),
                            fontStyle: _task.description?.isNotEmpty == true
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.edit_outlined, size: 12, color: cs.onSurface.withOpacity(.25)),
                    ],
                  ),
                ),
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
                        const Icon(Icons.radio_button_unchecked, size: 13),
                        const SizedBox(width: 5),
                        Text('À faire${pending.isNotEmpty ? ' (${pending.length})' : ''}'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 13,
                            color: done.isNotEmpty ? Colors.green.shade600 : null),
                        const SizedBox(width: 5),
                        Text('Fait${done.isNotEmpty ? ' (${done.length})' : ''}',
                            style: TextStyle(
                                color: done.isNotEmpty ? Colors.green.shade600 : null)),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_outlined, size: 13),
                        const SizedBox(width: 5),
                        Text('Fichiers${_docs.isNotEmpty ? ' (${_docs.length})' : ''}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.4)),

            // Contenu — Dialog : plafonné à 360 ; panneau : toute la hauteur.
            if (widget.panel)
              Expanded(
                child: isFilesTab
                    ? _buildFilesTab(cs)
                    : isDoneTab
                        ? _buildDoneActionsTab(cs, done)
                        : _buildPendingActionsTab(cs, pending),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: isFilesTab
                    ? _buildFilesTab(cs)
                    : isDoneTab
                        ? _buildDoneActionsTab(cs, done)
                        : _buildPendingActionsTab(cs, pending),
              ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: isFilesTab
                  ? Row(children: [
                      _uploading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton.icon(
                              icon: const Icon(Icons.upload_file_outlined, size: 16),
                              label: const Text('Déposer un fichier'),
                              onPressed: _uploadFile,
                            ),
                      const Spacer(),
                      Text(
                        'txt · md · html · json · images…',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(.3),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ])
                  : isDoneTab
                      ? const SizedBox.shrink()
                      : Row(children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Ajouter une action'),
                            onPressed: _addAction,
                          ),
                          const Spacer(),
                          if (pending.isNotEmpty)
                            Text(
                              'Appui long pour modifier',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(.3),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ]),
            ),
          ],
        );

    if (widget.panel) {
      return Material(color: cs.surface, child: body);
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(width: 720, child: body),
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
    if (mounted) _close();
  }

  // ── Description ─────────────────────────────────────────────────────────────

  Future<void> _editDescription() async {
    final ctrl = TextEditingController(text: _task.description ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Description'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Contexte, objectifs, notes…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          if (_task.description?.isNotEmpty == true)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text('Effacer', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    setState(() => _task.description = result.isEmpty ? null : result);
    _save();
  }

  // ── Upload fichier ───────────────────────────────────────────────────────────

  static const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'};
  static const _codeExts = {
    'json', 'xml', 'dart', 'js', 'ts', 'py', 'swift', 'kt', 'java',
    'yaml', 'yml', 'toml', 'sh',
  };

  Future<void> _uploadFile() async {
    final input = html.FileUploadInputElement()..accept = '*/*';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;

    final file = input.files![0];
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    setState(() => _uploading = true);
    try {
      final reader = html.FileReader();
      String content;

      if (ext == 'pdf') {
        // Vérifie la taille (Firestore limite à 1 Mo, base64 ×1.33)
        if (file.size > 700 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('PDF trop grand (max ~700 Ko). Compresse-le d\'abord.'),
            ));
          }
          setState(() => _uploading = false);
          return;
        }
        reader.readAsDataUrl(file);
        await reader.onLoad.first;
        // Stocker le data URL brut — le viewer détecte et crée un Blob URL
        content = reader.result as String;
      } else if (_imageExts.contains(ext)) {
        reader.readAsDataUrl(file);
        await reader.onLoad.first;
        final dataUrl = reader.result as String;
        content = '<html><body style="margin:0;text-align:center;background:#111">'
            '<img src="$dataUrl" style="max-width:100%;height:auto"></body></html>';
      } else {
        reader.readAsText(file);
        await reader.onLoad.first;
        final text = reader.result as String;
        if (ext == 'html' || ext == 'htm') {
          content = text;
        } else {
          final isCode = _codeExts.contains(ext);
          final escaped = text
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
          content = '<html><head><meta charset="utf-8"><style>'
              'body{font-family:${isCode ? "monospace" : "system-ui"};'
              'padding:24px;line-height:1.6;color:#1a1a1a;}'
              'pre{white-space:pre-wrap;word-wrap:break-word;font-size:13px;}'
              'h3{margin:0 0 12px;color:#888;font-size:11px;font-weight:700;letter-spacing:1px}'
              '</style></head><body>'
              '<h3>${_htmlEscape(name)}</h3>'
              '<pre>$escaped</pre></body></html>';
        }
      }

      final titleWithoutExt = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      final now = DateTime.now().toIso8601String();
      await widget.sync.saveDocument({
        'id': _uuid.v4(),
        'title': titleWithoutExt,
        'subtitle': name,
        'content': content,
        'category': 'fichier',
        'projectId': widget.project.id,
        'taskId': _task.id,
        'createdAt': now,
        'updatedAt': now,
      });
      await _loadDocs();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _htmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  // ── Onglet Actions ───────────────────────────────────────────────────────────

  // ── Onglet À faire ───────────────────────────────────────────────────────────

  Widget _buildPendingActionsTab(ColorScheme cs, List<TaskAction> pending) {
    if (pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _task.actions.isEmpty
                ? 'Aucune action. Clique + pour en ajouter.'
                : 'Tout est fait 🎉',
            style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withOpacity(.4)),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      buildDefaultDragHandles: false,
      itemCount: pending.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final movedItem = pending[oldIndex];
          final targetItem = newIndex < pending.length ? pending[newIndex] : null;
          _task.actions.remove(movedItem);
          if (targetItem == null) {
            _task.actions.add(movedItem);
          } else {
            final targetIdx = _task.actions.indexOf(targetItem);
            _task.actions.insert(targetIdx, movedItem);
          }
        });
        _save();
      },
      itemBuilder: (ctx, i) {
        final a = pending[i];
        return ListTile(
          key: ValueKey('pending_${a.title}_$i'),
          dense: true,
          contentPadding: const EdgeInsets.only(left: 0, right: 4),
          onLongPress: () async {
            final ctrl = TextEditingController(text: a.title);
            final result = await showDialog<String>(
              context: context,
              useRootNavigator: true,
              builder: (c) => AlertDialog(
                title: const Text('Modifier l\'action'),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(c, v.trim());
                  },
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler')),
                  FilledButton(
                    onPressed: () {
                      final v = ctrl.text.trim();
                      if (v.isNotEmpty) Navigator.pop(c, v);
                    },
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            );
            ctrl.dispose();
            if (result != null) {
              setState(() => a.title = result);
              _save();
            }
          },
          leading: Checkbox(
            value: false,
            onChanged: (v) {
              setState(() {
                a.done = true;
                a.doneAt = DateTime.now();
              });
              _save();
            },
          ),
          title: Text(a.title, style: const TextStyle(fontSize: 13)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                tooltip: 'Réorganiser',
                icon: Icon(Icons.more_vert,
                    size: 16, color: cs.onSurface.withOpacity(.3)),
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'move') _moveActionToAnotherTask(a);
                  if (v == 'promote') _promoteActionToSubproject(a);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'move',
                    child: Text('Déplacer vers une autre tâche'),
                  ),
                  PopupMenuItem(
                    value: 'promote',
                    child: Text('Promouvoir en sous-projet'),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 16, color: cs.onSurface.withOpacity(.3)),
                visualDensity: VisualDensity.compact,
                tooltip: 'Supprimer',
                onPressed: () {
                  setState(() => _task.actions.remove(a));
                  _save();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    duration: Duration(seconds: 2),
                    content: Text('Action supprimée'),
                  ));
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

  // ── Onglet Fait ───────────────────────────────────────────────────────────────

  Widget _buildDoneActionsTab(ColorScheme cs, List<TaskAction> done) {
    if (done.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucune action réalisée.',
            style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withOpacity(.4)),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: done.length,
      itemBuilder: (ctx, i) {
        final a = done[i];
        return ListTile(
          key: ValueKey('done_${a.title}_$i'),
          dense: true,
          contentPadding: const EdgeInsets.only(left: 0, right: 4),
          leading: Checkbox(
            value: true,
            activeColor: Colors.green.shade600,
            onChanged: (v) {
              setState(() {
                a.done = false;
                a.doneAt = null;
              });
              _save();
            },
          ),
          title: Text(
            a.title,
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(.4),
              decoration: TextDecoration.lineThrough,
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.delete_outline,
                size: 16, color: cs.onSurface.withOpacity(.3)),
            visualDensity: VisualDensity.compact,
            tooltip: 'Supprimer',
            onPressed: () {
              setState(() => _task.actions.remove(a));
              _save();
            },
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
    const catOrder = ['fichier', 'programme', 'livrable', 'brief', 'recherche', 'notes'];
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
    'fichier':   (Icons.attach_file_outlined, Color(0xFF0891B2), 'Fichiers'),
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
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: cs.onSurface.withOpacity(.35)),
                tooltip: 'Supprimer',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce fichier ?'),
        content: Text('Supprimer "${doc['title']}" ? Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await sync.deleteDocument(doc['id'] as String);
    onRefresh();
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
      final iframe = html.IFrameElement()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';

      final content = widget.htmlContent;
      if (content.startsWith('data:application/pdf;base64,')) {
        // Créer un Blob URL pour que le PDF s'affiche dans le viewer
        final base64Data = content.substring('data:application/pdf;base64,'.length);
        final bytes = base64Decode(base64Data);
        final blob = html.Blob([bytes], 'application/pdf');
        iframe.src = html.Url.createObjectUrl(blob);
      } else {
        iframe.srcdoc = content;
      }
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewId);
}
