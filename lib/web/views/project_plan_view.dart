import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/add_task_dialog.dart';
import 'package:productivitwo_v1/web/checklist_widget.dart';
import 'package:productivitwo_v1/web/document_viewer_dialog.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/project_doc_view.dart';
import 'package:productivitwo_v1/web/project_edit_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

// Fiche projet (refonte web § 4.5) : s'ouvre dans le shell à la place du
// Gantt. Segmented « Plan d'action · Gantt · Document » — Gantt = GanttScreen
// existant, Document = ProjectDocView.

const _tabular = [FontFeature.tabularFigures()];
const _kMonthShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
const _kDayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

String _dm(DateTime d) => '${d.day} ${_kMonthShort[d.month - 1]}';
String _ddmm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String _clock(int min) => '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

enum ProjectPlanTab { plan, gantt, document }

class ProjectPlanView extends StatefulWidget {
  final Project project;
  final String? targetTaskId;
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Session> recentSessions;
  final List<Map<String, dynamic>> documents;
  final FirestoreSync sync;
  final VoidCallback onClose;
  final VoidCallback onChanged;
  final void Function(String projectId) onOpenLibrary;

  const ProjectPlanView({
    super.key,
    required this.project,
    this.targetTaskId,
    required this.domains,
    required this.activities,
    required this.recentSessions,
    required this.documents,
    required this.sync,
    required this.onClose,
    required this.onChanged,
    required this.onOpenLibrary,
  });

  @override
  State<ProjectPlanView> createState() => _ProjectPlanViewState();
}

class _ProjectPlanViewState extends State<ProjectPlanView> {
  late ProjectPlanTab _tab;
  bool _hideDone = false;
  final Set<String> _expanded = {};
  bool _phasesInit = false;
  final Map<String, List<ScheduleBlock>> _byDay = {};
  final List<StreamSubscription<DailySchedule?>> _subs = [];
  Map<String, int> _capacity = defaultWeekCapacity();

  Project get _p => widget.project;
  DateTime get _today => dateOnly(DateTime.now());
  List<DateTime> get _weekDays => weekDates(weekStart(DateTime.now()));

  @override
  void initState() {
    super.initState();
    // Ouverture ciblée sur une tâche (depuis Aujourd'hui, Cette semaine…)
    // → directement le Gantt ; sinon le plan d'action.
    _tab = widget.targetTaskId != null ? ProjectPlanTab.gantt : ProjectPlanTab.plan;
    for (final d in _weekDays) {
      final key = ymdOf(d);
      _subs.add(widget.sync.streamDailySchedule(key).listen((s) {
        if (!mounted) return;
        setState(() => _byDay[key] =
            (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
              ..sort((a, b) => a.startTime.compareTo(b.startTime)));
      }));
    }
    widget.sync.fetchWeekCapacity().then((c) {
      if (mounted) setState(() => _capacity = c);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ── Données dérivées ────────────────────────────────────────────────────────

  Color get _accent => domainColor(_p.domainId, widget.domains) ?? kBPrimary;
  Domain? get _domain => widget.domains.where((d) => d.id == _p.domainId).firstOrNull;

  /// Blocs de la semaine liés au projet (tâche du projet ou projectId).
  List<({DateTime day, ScheduleBlock block})> get _weekBlocks {
    final ids = {for (final t in _p.tasks) t.id};
    final out = <({DateTime day, ScheduleBlock block})>[];
    for (final e in _byDay.entries) {
      for (final b in e.value) {
        if (b.projectId == _p.id || (b.taskId != null && ids.contains(b.taskId))) {
          out.add((day: DateTime.parse(e.key), block: b));
        }
      }
    }
    out.sort((a, b) {
      final c = a.day.compareTo(b.day);
      return c != 0 ? c : blockStartMin(a.block).compareTo(blockStartMin(b.block));
    });
    return out;
  }

  ScheduleBlock? _todayBlockFor(String taskId) {
    for (final b in _byDay[ymdOf(_today)] ?? const <ScheduleBlock>[]) {
      if (b.taskId == taskId && b.status != 'done') return b;
    }
    return null;
  }

  bool _plannedThisWeek(String taskId) =>
      _byDay.values.any((l) => l.any((b) => b.taskId == taskId));

  bool _taskOpen(ProjectTask t) => t.status != 'done' && t.status != 'skipped';
  bool _overdue(ProjectTask t) =>
      _taskOpen(t) && t.endDate != null && dateOnly(t.endDate!).isBefore(_today);

  /// Sections du plan : phases par date de début, puis « Sans phase ».
  List<({ProjectPhase? phase, List<ProjectTask> tasks})> get _sections {
    final phases = List.of(_p.phases)..sort((a, b) => a.startDate.compareTo(b.startDate));
    final ordered = ganttOrder(_p);
    final out = <({ProjectPhase? phase, List<ProjectTask> tasks})>[];
    for (final ph in phases) {
      out.add((phase: ph, tasks: ordered.where((t) => t.phaseId == ph.id).toList()));
    }
    final phaseIds = {for (final ph in phases) ph.id};
    final loose = ordered.where((t) => t.phaseId == null || !phaseIds.contains(t.phaseId)).toList();
    if (loose.isNotEmpty || out.isEmpty) out.add((phase: null, tasks: loose));
    return out;
  }

  void _initExpanded() {
    if (_phasesInit) return;
    _phasesInit = true;
    final cur = currentPhase(_p, DateTime.now());
    if (cur != null) {
      _expanded.add(cur.id);
    } else {
      // Pas de phase courante : la première avec une tâche ouverte, sinon « sans phase ».
      final first = _sections.where((s) => s.tasks.any(_taskOpen)).firstOrNull ?? _sections.first;
      _expanded.add(first.phase?.id ?? '_none');
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ));
  }

  Future<void> _save() async {
    await widget.sync.saveProjectTasks(_p.id, _p.tasks);
    widget.onChanged();
  }

  Future<void> _toggleAction(TaskAction a) async {
    setState(() {
      a.done = !a.done;
      a.doneAt = a.done ? DateTime.now() : null;
    });
    await _save();
  }

  Future<void> _toggleChecklist(TaskAction a, ChecklistItem c, bool done) async {
    final changed = setChecklistItem(a, c.id, done);
    setState(() {});
    await _save();
    if (changed && mounted) {
      _snack(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}');
    }
  }

  Future<void> _addChecklist(TaskAction a, String title) async {
    if (addChecklistItem(a, title) == null) return;
    setState(() {});
    await _save();
  }

  Future<void> _removeChecklist(TaskAction a, ChecklistItem c) async {
    setState(() => removeChecklistItem(a, c.id));
    await _save();
  }

  Future<void> _toggleTask(ProjectTask t) async {
    setState(() => t.status = t.status == 'done' ? 'pending' : 'done');
    await _save();
  }

  Future<void> _editProject() async {
    final saved = await showProjectEditDialog(context,
        project: _p, domains: widget.domains, sync: widget.sync);
    if (!saved || !mounted) return;
    setState(() {
      _phasesInit = false;
      _expanded.clear();
    });
    widget.onChanged();
  }

  /// Report volontaire de l'échéance d'une tâche en retard (sélecteur de date).
  Future<void> _rescheduleDeadline(ProjectTask t) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _today,
      firstDate: _today,
      lastDate: DateTime(2032),
      helpText: 'Nouvelle échéance',
    );
    if (picked == null || !mounted) return;
    final day = dateOnly(picked);
    final oldStart = t.startDate, oldEnd = t.endDate;
    setState(() {
      t.endDate = day;
      if (dateOnly(t.startDate).isAfter(day)) t.startDate = day;
    });
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Échéance reportée au ${_ddmm(day)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: kBPrimary,
          onPressed: () async {
            setState(() {
              t.startDate = oldStart;
              t.endDate = oldEnd;
            });
            await _save();
          },
        ),
      ));
  }

  Future<void> _addTask() async {
    final task = await showAddTaskDialog(context, project: _p, sync: widget.sync);
    if (task == null || !mounted) return;
    setState(() => _expanded.add(task.phaseId ?? '_none'));
    widget.onChanged();
  }

  /// « Planifier » : un bloc sur le prochain jour de la semaine non plein
  /// (même règle que « Tout caser » de Cette semaine).
  Future<void> _planTask(ProjectTask t) async {
    final wt = WeekTask(task: t, project: _p, overdue: _overdue(t), plannedBlocks: 0);
    final r = autoPlace(
      toPlace: [wt],
      days: _weekDays,
      scheduledByDay: _byDay,
      capacity: _capacity,
      today: _today,
    );
    if (r.blocks.isEmpty) {
      _snack('Plus de place cette semaine — passe par Cette semaine pour la suivante.');
      return;
    }
    final e = r.blocks.entries.first;
    final block = e.value.first;
    setState(() => (_byDay[e.key] ??= []).add(block));
    await widget.sync.addScheduleBlock(e.key, block);
    final day = DateTime.parse(e.key);
    _snack('Bloc ajouté ${_kDayShort[day.weekday - 1]} ${day.day} · ${_clock(blockStartMin(block))}');
  }

  void _openDocument(Map<String, dynamic> doc) {
    final docs = List.of(widget.documents);
    final i = docs.indexOf(doc);
    if (i > 0) {
      docs.removeAt(i);
      docs.insert(0, doc);
    }
    showDialog<void>(
      context: context,
      builder: (_) => DocumentViewerDialog(
        projectTitle: _p.title,
        documents: docs,
        sync: widget.sync,
        onDeleted: widget.onChanged,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _initExpanded();
    return Container(
      color: kBBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: [
              _plan(),
              GanttScreen(
                key: ValueKey('gantt/${_p.id}/${widget.targetTaskId}'),
                project: _p,
                targetTaskId: widget.targetTaskId,
                domains: widget.domains,
                onClose: () => setState(() => _tab = ProjectPlanTab.plan),
              ),
              ProjectDocView(
                key: ValueKey('doc/${_p.id}'),
                project: _p,
                sync: widget.sync,
                accentColor: _accent,
                onProjectChanged: widget.onChanged,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _header() {
    final end = _p.endDate;
    final range = end == null
        ? 'depuis le ${_dm(_p.startDate)}'
        : '${_dm(_p.startDate)} → ${_dm(end)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBLine))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: widget.onClose,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('‹ Projets',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _accent, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Flexible(
                child: InkWell(
                  onTap: _editProject,
                  borderRadius: BorderRadius.circular(6),
                  child: Text(_p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: kBText,
                          letterSpacing: -.2)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Modifier le projet (titre, domaine, dates, phases)',
                icon: const Icon(Icons.edit_outlined, size: 17, color: kBText3),
                visualDensity: VisualDensity.compact,
                onPressed: _editProject,
              ),
            ]),
            const SizedBox(height: 3),
            Text('${_domain?.name ?? 'Sans domaine'} · $range',
                style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular)),
          ]),
        ),
        const SizedBox(width: 20),
        _segmented(),
        const SizedBox(width: 12),
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une tâche'),
            style: FilledButton.styleFrom(
              backgroundColor: kBPrimary,
              foregroundColor: kBBg,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _segmented() {
    const labels = {
      ProjectPlanTab.plan: "Plan d'action",
      ProjectPlanTab.gantt: 'Gantt',
      ProjectPlanTab.document: 'Document',
    };
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final t in ProjectPlanTab.values)
          InkWell(
            onTap: () => setState(() => _tab = t),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == t ? kBActive : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: _tab == t ? kBPrimary.withOpacity(.35) : Colors.transparent),
              ),
              child: Text(labels[t]!,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _tab == t ? kBText : kBText2)),
            ),
          ),
      ]),
    );
  }

  // ── Plan d'action ───────────────────────────────────────────────────────────

  Widget _plan() {
    return LayoutBuilder(builder: (ctx, box) {
      final narrow = box.maxWidth < 1000;
      final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tiles(),
        const SizedBox(height: 18),
        _planCard(),
      ]);
      final side = _sideColumn();
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
        children: [
          if (narrow) ...[main, const SizedBox(height: 18), side]
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main),
              const SizedBox(width: 24),
              SizedBox(width: 360, child: side),
            ]),
        ],
      );
    });
  }

  Widget _tiles() {
    final now = DateTime.now();
    final prog = taskProgress(_p);
    final pct = prog.total == 0 ? 0 : (prog.done * 100 / prog.total).round();
    final overdue = overdueTasks(_p, now)
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    final sessions = sessionsLast7Days(_p, widget.recentSessions, now);
    final minutes = minutesLast7Days(_p, widget.recentSessions, now);
    final milestone = nextMilestone(_p, now);
    final msDays = milestone == null
        ? null
        : dateOnly(milestone.endDate ?? milestone.startDate).difference(_today).inDays;

    return LayoutBuilder(builder: (ctx, box) {
      final tiles = [
        _tile('AVANCEMENT',
            value: '${prog.done} / ${prog.total}',
            unit: prog.total == 0 ? 'aucune tâche' : '$pct %'),
        _tile('EN RETARD',
            value: '${overdue.length}',
            unit: overdue.isEmpty
                ? 'rien en retard'
                : 'la plus vieille le ${_ddmm(overdue.first.endDate!)}',
            color: overdue.isEmpty ? null : kBAlert),
        _tile('TEMPS · 7 JOURS',
            value: minutes == 0 ? '—' : _fmtHm(minutes),
            unit: sessions.isEmpty
                ? 'aucune session'
                : 'sur ${sessions.length} session${sessions.length > 1 ? 's' : ''}'),
        _tile('PROCHAIN JALON',
            value: milestone == null ? '—' : 'J-$msDays',
            unit: milestone?.title ?? 'aucun jalon à venir',
            color: msDays != null && msDays <= 7 ? kBAttention : null,
            border: msDays != null && msDays <= 7),
      ];
      final two = box.maxWidth < 760;
      if (two) {
        return Column(children: [
          Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 12), Expanded(child: tiles[1])]),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 12), Expanded(child: tiles[3])]),
        ]);
      }
      return Row(children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ]);
    });
  }

  Widget _tile(String label, {required String value, required String unit, Color? color, bool border = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border ? kBAttention.withOpacity(.6) : kBLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label),
        const SizedBox(height: 10),
        Text(value,
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: color ?? kBText,
                letterSpacing: -.5,
                fontFeatures: _tabular)),
        const SizedBox(height: 4),
        Text(unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
      ]),
    );
  }

  Widget _planCard() {
    final sections = _sections;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label("PLAN D'ACTION")),
          _textLink(_hideDone ? 'Afficher le fait' : 'Masquer le fait',
              () => setState(() => _hideDone = !_hideDone)),
        ]),
        const SizedBox(height: 8),
        if (_p.tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(children: [
              const Text('Aucune tâche pour l\'instant.',
                  style: TextStyle(fontSize: 13, color: kBText3)),
              const SizedBox(height: 12),
              _pillButton('Ajouter une tâche', onTap: _addTask),
            ]),
          )
        else
          for (final s in sections) _phaseSection(s.phase, s.tasks),
      ]),
    );
  }

  Widget _phaseSection(ProjectPhase? phase, List<ProjectTask> tasks) {
    final id = phase?.id ?? '_none';
    final open = _expanded.contains(id);
    final now = DateTime.now();
    final total = tasks.where((t) => t.status != 'skipped').length;
    final done = tasks.where((t) => t.status == 'done').length;
    final late = tasks.where(_overdue).length;
    final isCurrent = phase != null && currentPhase(_p, now)?.id == phase.id;
    final finished = phase != null && dateOnly(phase.endDate).isBefore(_today);

    final String meta;
    if (phase == null) {
      meta = '$done / $total';
    } else if (total > 0 && done == total) {
      meta = '$done / $total · terminée';
    } else if (late > 0) {
      meta = '$done / $total · $late en retard';
    } else {
      meta = '$done / $total · ${_dm(phase.startDate)} → ${_dm(phase.endDate)}';
    }

    final visible = _hideDone ? tasks.where(_taskOpen).toList() : tasks;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => open ? _expanded.remove(id) : _expanded.add(id)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: kBText3),
            const SizedBox(width: 6),
            Text(phase?.label ?? 'Sans phase',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: finished && !isCurrent ? kBText3 : kBText)),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              _badge('en cours', kBPrimary),
            ],
            const Spacer(),
            Text(meta,
                style: TextStyle(
                    fontSize: 12,
                    color: late > 0 && !(total > 0 && done == total) ? kBAlert : kBText3,
                    fontFeatures: _tabular)),
          ]),
        ),
      ),
      if (open) ...[
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 2, 0, 12),
            child: Text('Rien à afficher.', style: TextStyle(fontSize: 12.5, color: kBText4)),
          )
        else
          for (final t in visible) _taskCard(t),
        const SizedBox(height: 6),
      ],
      const Divider(height: 1, color: kBLine),
    ]);
  }

  Widget _taskCard(ProjectTask t) {
    final open = _taskOpen(t);
    final overdue = _overdue(t);
    final todayBlock = _todayBlockFor(t.id);
    final actions = _hideDone ? t.actions.where((a) => !a.done).toList() : t.actions;

    String due;
    Color dueColor = kBText3;
    if (todayBlock != null) {
      due = 'aujourd\'hui · ${_clock(blockStartMin(todayBlock))}';
      dueColor = kBPrimary;
    } else if (t.isMilestone) {
      due = 'jalon · ${_ddmm(t.endDate ?? t.startDate)}';
    } else if (t.endDate != null) {
      due = overdue ? 'échéance ${_ddmm(t.endDate!)}' : 'pour le ${_ddmm(t.endDate!)}';
      if (overdue) dueColor = kBAlert;
    } else {
      due = 'sans échéance';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 2, 0, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: open ? kBRaised : kBRaised.withOpacity(.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleTask(t),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(
                open
                    ? (t.isMilestone ? Icons.flag_outlined : Icons.radio_button_unchecked)
                    : Icons.check_circle,
                size: 18,
                color: open ? kBText3 : kBPrimaryDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: open ? kBText : kBText3,
                      decoration: open ? null : TextDecoration.lineThrough,
                      decorationColor: kBText3)),
              const SizedBox(height: 3),
              Row(children: [
                Text(due,
                    style: TextStyle(fontSize: 12, color: dueColor, fontFeatures: _tabular)),
                if (overdue) ...[
                  const SizedBox(width: 8),
                  _badge('retard', kBAlert),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _rescheduleDeadline(t),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      child: Text('Reporter',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600, color: kBAttention)),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
          if (open && !t.isMilestone && !_plannedThisWeek(t.id)) ...[
            const SizedBox(width: 10),
            _pillButton('Planifier', icon: Icons.event_available_outlined, onTap: () => _planTask(t)),
          ],
        ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _toggleAction(a),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: a.done ? kBPrimaryDark : kBText3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.title,
                        style: TextStyle(
                            fontSize: 13,
                            color: a.done ? kBText4 : kBText2,
                            decoration: a.done ? TextDecoration.lineThrough : null,
                            decorationColor: kBText4)),
                  ),
                  if (checklistBadge(a) != null) ...[
                    const SizedBox(width: 8),
                    checklistBadge(a)!,
                  ],
                  for (final c in a.allContexts.take(3)) ...[
                    const SizedBox(width: 6),
                    _badge(c, kBText3),
                  ],
                ]),
                // Micro-actions : cochables ici comme pendant un bloc du programme.
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 2),
                  child: ChecklistEditor(
                    items: _hideDone ? a.checklist.where((c) => !c.done).toList() : a.checklist,
                    dense: true,
                    onToggle: (c, v) => _toggleChecklist(a, c, v),
                    onAdd: (t) => _addChecklist(a, t),
                    onDelete: (c) => _removeChecklist(a, c),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  // ── Colonne droite ──────────────────────────────────────────────────────────

  Widget _sideColumn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _weekCard(),
      const SizedBox(height: 18),
      _milestonesCard(),
      const SizedBox(height: 18),
      _documentsCard(),
    ]);
  }

  Widget _weekCard() {
    final blocks = _weekBlocks;
    final plannedTasks = {for (final e in blocks) if (e.block.taskId != null) e.block.taskId!};
    final unplanned = _p.tasks
        .where((t) => _taskOpen(t) && !t.isMilestone && !plannedTasks.contains(t.id))
        .length;
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('CETTE SEMAINE DANS MON PROGRAMME'),
        const SizedBox(height: 12),
        if (blocks.isEmpty)
          const Text('Aucun bloc de ce projet cette semaine.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final e in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(
                      '${_kDayShort[e.day.weekday - 1]} ${e.block.startTime}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: e.day == _today ? kBPrimary : kBText2,
                          fontFeatures: _tabular)),
                ),
                Expanded(
                  child: Text(e.block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: e.block.status == 'done' ? kBText4 : kBText,
                          decoration:
                              e.block.status == 'done' ? TextDecoration.lineThrough : null,
                          decorationColor: kBText4)),
                ),
                const SizedBox(width: 8),
                Text(_fmtHm(e.block.durationMin),
                    style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
              ]),
            ),
        if (unplanned > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$unplanned tâche${unplanned > 1 ? 's' : ''} du projet '
            '${unplanned > 1 ? 'ne sont' : 'n\'est'} pas encore planifiée${unplanned > 1 ? 's' : ''}.',
            style: const TextStyle(fontSize: 12, color: kBAttention),
          ),
        ],
      ]),
    );
  }

  Widget _milestonesCard() {
    final ms = _p.tasks.where((t) => t.isMilestone && t.status != 'skipped').toList()
      ..sort((a, b) => (a.endDate ?? a.startDate).compareTo(b.endDate ?? b.startDate));
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('JALONS'),
        const SizedBox(height: 12),
        if (ms.isEmpty)
          const Text('Aucun jalon.', style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final m in ms)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Builder(builder: (_) {
                final when = dateOnly(m.endDate ?? m.startDate);
                final done = m.status == 'done';
                final days = when.difference(_today).inDays;
                final soon = !done && days >= 0 && days <= 7;
                final color = done ? kBPrimaryDark : (soon ? kBAttention : kBText3);
                return Row(children: [
                  Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: done ? color : Colors.transparent,
                          border: Border.all(color: color, width: 1.5),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: done ? kBText3 : kBText,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: kBText3)),
                  ),
                  const SizedBox(width: 8),
                  Text(_ddmm(when),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: soon ? FontWeight.w600 : FontWeight.w400,
                          color: soon ? kBAttention : kBText3,
                          fontFeatures: _tabular)),
                ]);
              }),
            ),
      ]),
    );
  }

  Widget _documentsCard() {
    final docs = List.of(widget.documents)
      ..sort((a, b) => _docTime(b).compareTo(_docTime(a)));
    final shown = docs.take(3).toList();
    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _label('DOCUMENTS')),
          if (docs.isNotEmpty) _textLink('Tout voir', () => widget.onOpenLibrary(_p.id)),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Text('Aucun document pour ce projet.',
              style: TextStyle(fontSize: 13, color: kBText3))
        else
          for (final d in shown)
            InkWell(
              onTap: () => _openDocument(d),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.description_outlined, size: 15, color: kBText3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text((d['title'] as String?) ?? 'Document',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: kBText)),
                  ),
                  const SizedBox(width: 8),
                  _badge((d['category'] as String?) ?? 'notes', kBText3),
                ]),
              ),
            ),
      ]),
    );
  }

  /// Date d'un document (updatedAt puis createdAt ; Timestamp ou ISO), sinon 0.
  static int _docTime(Map<String, dynamic> d) {
    for (final k in const ['updatedAt', 'createdAt']) {
      final v = d[k];
      if (v == null) continue;
      try {
        if (v is DateTime) return v.millisecondsSinceEpoch;
        if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
        final dt = (v as dynamic).toDate();
        if (dt is DateTime) return dt.millisecondsSinceEpoch;
      } catch (_) {}
    }
    return 0;
  }

  // ── Briques ─────────────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBLine),
        ),
        child: child,
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3));

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
      );

  Widget _textLink(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
        ),
      );

  Widget _pillButton(String label, {IconData? icon, VoidCallback? onTap}) => SizedBox(
        height: 34,
        child: TextButton.icon(
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15, color: kBText),
          label: Text(label),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0x12FFFFFF),
            foregroundColor: kBText,
            shape: const StadiumBorder(),
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      );
}
