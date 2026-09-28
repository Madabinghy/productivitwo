import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/gantt_screen.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/views/week_task_popover.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vue « Cette semaine » (handoff cette-semaine-2026-09) : le Gantt 7 / 14 jours
// des tâches par domaine, en pleine page, où l'on organise la semaine sans
// quitter la grille — blocs du programme dans les barres, « à caser » en
// pointillé, clic sur un jour = caser, glisser = déplacer, tirer = étendre.

const _kDayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _kDayLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _kMonthLong = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
const _kMonthShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
const _tabular = [FontFeature.tabularFigures()];
const _kLeftCol = 320.0;
const _kRowH = 40.0;
const _kDomainH = 24.0;
const _kBarH = 24.0;
const _kBarTop = 8.0;
const _kPrefHideDone = 'week_hide_done';
const _kPrefCollapsed = 'week_collapsed_domains';
const _kPrefDays = 'week_window_days';

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _clock(int min) => '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

Color? _hex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.replaceFirst('#', '').replaceFirst(RegExp(r'^0[xX]'), '');
  try {
    if (s.length == 6) return Color(int.parse('FF$s', radix: 16));
    if (s.length == 8) return Color(int.parse(s, radix: 16));
  } catch (_) {}
  return null;
}

String _toHex(Color c) =>
    '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class WeekView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final FirestoreSync sync;
  final void Function(Project project, {String? taskId}) onOpenProject;

  const WeekView({
    super.key,
    required this.projects,
    required this.domains,
    required this.sync,
    required this.onOpenProject,
  });

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  int _days = 7;
  late DateTime _start; // lundi (7 j) ou jour de départ (14 j)
  final Map<String, List<ScheduleBlock>> _byDay = {};
  final List<StreamSubscription<DailySchedule?>> _subs = [];
  Map<String, int> _capacity = defaultWeekCapacity();
  bool _hideDone = false;
  final Set<String> _collapsed = {};
  bool _busy = false;

  // Glisser une barre (déplacer) / tirer sa poignée (étendre), en pixels.
  String? _dragTaskId;
  bool _dragResize = false;
  double _dragDx = 0;

  DateTime get _today => dateOnly(DateTime.now());
  List<DateTime> get _dates => windowDates(_start, _days);
  List<ScheduleBlock> get _allBlocks => [for (final l in _byDay.values) ...l];

  @override
  void initState() {
    super.initState();
    _start = weekStart(DateTime.now());
    _loadPrefs();
    _subscribe();
    widget.sync.fetchWeekCapacity().then((c) {
      if (mounted) setState(() => _capacity = c);
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      final days = p.getInt(_kPrefDays);
      setState(() {
        _hideDone = p.getBool(_kPrefHideDone) ?? false;
        _collapsed
          ..clear()
          ..addAll(p.getStringList(_kPrefCollapsed) ?? const []);
        if (days == 14) {
          _days = 14;
          _start = _today;
        }
      });
      if (days == 14) _subscribe();
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kPrefHideDone, _hideDone);
      await p.setStringList(_kPrefCollapsed, _collapsed.toList());
      await p.setInt(_kPrefDays, _days);
    } catch (_) {}
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _byDay.clear();
    for (final d in _dates) {
      final key = ymdOf(d);
      _subs.add(widget.sync.streamDailySchedule(key).listen((s) {
        if (!mounted) return;
        setState(() {
          _byDay[key] = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
            ..sort((a, b) => blockStartMin(a).compareTo(blockStartMin(b)));
        });
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _setWindow({int? days, DateTime? start}) {
    setState(() {
      if (days != null) _days = days;
      _start = start ?? (_days == 7 ? weekStart(_today) : _today);
    });
    _subscribe();
    _savePrefs();
  }

  void _shift(int dir) => _setWindow(start: _start.add(Duration(days: _days * dir)));

  // ── Données dérivées ────────────────────────────────────────────────────────

  List<WeekTask> get _tasks => windowTasks(
        projects: widget.projects,
        start: _start,
        days: _days,
        scheduled: _allBlocks,
        today: _today,
      );

  List<ScheduleBlock> _blocksOfTask(String taskId) =>
      [for (final e in _byDay.entries) for (final b in e.value) if (b.taskId == taskId) b];

  String? _dateOfBlock(ScheduleBlock b) {
    for (final e in _byDay.entries) {
      if (e.value.contains(b)) return e.key;
    }
    return null;
  }

  Color _taskColor(WeekTask wt) {
    final own = _hex(wt.task.color);
    if (own != null) return own;
    final phase = wt.project.phases.where((p) => p.id == wt.task.phaseId).firstOrNull;
    final ph = _hex(phase?.color);
    if (ph != null) return ph;
    return domainColor(wt.project.domainId, widget.domains) ?? kBPrimary;
  }

  /// Colonnes [s, e] de la barre dans la fenêtre, null si hors fenêtre.
  ({int s, int e})? _span(ProjectTask t) {
    final first = _dates.first, last = _dates.last;
    final start = dateOnly(t.startDate);
    final end = dateOnly(t.endDate ?? t.startDate);
    if (start.isAfter(last) || end.isBefore(first)) return null;
    final s = start.isBefore(first) ? 0 : start.difference(first).inDays;
    final e = end.isAfter(last) ? _days - 1 : end.difference(first).inDays;
    return (s: s, e: e);
  }

  int? _dayIndex(DateTime d) {
    final i = dateOnly(d).difference(_dates.first).inDays;
    return i < 0 || i >= _days ? null : i;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

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

  Future<void> _saveTasks(Project p) => widget.sync.saveProjectTasks(p.id, p.tasks);

  Future<void> _placeAt(WeekTask wt, DateTime day, int startMin) async {
    final key = ymdOf(day);
    final dur = remainingToPlaceMin(wt.task, _allBlocks);
    final block = ScheduleBlock(
      startTime: minToClock(startMin),
      durationMin: dur == 0 ? wt.task.plannedMin : dur,
      title: wt.task.title,
      category: 'project',
      projectId: wt.project.id,
      taskId: wt.task.id,
    );
    setState(() => (_byDay[key] ??= []).add(block));
    await widget.sync.addScheduleBlock(key, block);
    _snack('Bloc ajouté ${_kDayLong[day.weekday - 1]} ${_clock(startMin)}',
        actionLabel: 'Retirer', onAction: () => _removeBlock(key, block));
  }

  Future<void> _removeBlock(String date, ScheduleBlock b) async {
    setState(() => _byDay[date]?.remove(b));
    await widget.sync.updateBlockStatus(date, b.id, 'deleted');
  }

  Future<void> _blockToTomorrow(String date, ScheduleBlock b) async {
    setState(() => _byDay[date]?.remove(b));
    await widget.sync.reportBlockToTomorrow(date, b);
    _snack('Bloc déplacé à demain');
  }

  Future<void> _toggleDone(WeekTask wt) async {
    setState(() => wt.task.status = wt.task.status == 'done' ? 'pending' : 'done');
    await _saveTasks(wt.project);
  }

  Future<void> _shiftTask(WeekTask wt, int deltaDays) async {
    if (deltaDays == 0) return;
    final t = wt.task;
    setState(() {
      t.startDate = t.startDate.add(Duration(days: deltaDays));
      if (t.endDate != null) t.endDate = t.endDate!.add(Duration(days: deltaDays));
    });
    await _saveTasks(wt.project);
    final n = wt.plannedBlocks;
    _snack(
      'Tâche déplacée de ${deltaDays.abs()} jour${deltaDays.abs() > 1 ? 's' : ''}'
      '${n > 0 ? ' · $n bloc${n > 1 ? 's' : ''} reste${n > 1 ? 'nt' : ''} à ${n > 1 ? 'leur' : 'sa'} date' : ''}',
    );
  }

  /// Report volontaire de l'échéance d'une tâche en retard au jour [day]
  /// (le début est avancé si besoin). Annulable.
  Future<void> _rescheduleDeadline(WeekTask wt, DateTime day) async {
    final t = wt.task;
    final oldStart = t.startDate, oldEnd = t.endDate;
    setState(() {
      t.endDate = day;
      if (dateOnly(t.startDate).isAfter(day)) t.startDate = day;
    });
    await _saveTasks(wt.project);
    _snack('Échéance reportée au ${_kDayLong[day.weekday - 1]} ${day.day}',
        actionLabel: 'Annuler', onAction: () async {
      setState(() {
        t.startDate = oldStart;
        t.endDate = oldEnd;
      });
      await _saveTasks(wt.project);
    });
  }

  Future<void> _resizeTask(WeekTask wt, int deltaDays) async {
    if (deltaDays == 0) return;
    final t = wt.task;
    final base = dateOnly(t.endDate ?? t.startDate);
    var end = base.add(Duration(days: deltaDays));
    if (end.isBefore(dateOnly(t.startDate))) end = dateOnly(t.startDate);
    setState(() => t.endDate = end);
    await _saveTasks(wt.project);
  }

  Future<void> _pickColor(WeekTask wt) async {
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Couleur de la barre'),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kColorPickerOptions)
              InkWell(
                onTap: () => Navigator.pop(ctx, _toHex(c)),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _hex(wt.task.color) == c ? Colors.white : Colors.transparent, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Couleur du domaine (par défaut)')),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => wt.task.color = picked.isEmpty ? null : picked);
    await _saveTasks(wt.project);
  }

  void _openTask(WeekTask wt) => showGanttTaskDetailDialog(context,
      project: wt.project,
      task: wt.task,
      sync: widget.sync,
      onProjectUpdated: (_) => setState(() {}));

  void _openPopover(WeekTask wt, int dayIdx, Offset global) {
    final day = _dates[dayIdx];
    if (day.isBefore(_today)) {
      _snack('${_kDayLong[day.weekday - 1]} est passé — choisis un jour à venir.');
      return;
    }
    final dur = remainingToPlaceMin(wt.task, _allBlocks);
    final duration = dur == 0 ? wt.task.plannedMin : dur;
    final now = DateTime.now();
    final slot = proposedSlot(_byDay[ymdOf(day)] ?? const [], duration,
        isToday: day == _today, nowMin: now.hour * 60 + now.minute);
    showWeekTaskPopover(
      context,
      anchor: global,
      title: wt.task.title,
      day: day,
      proposedStartMin: slot.start,
      dayFull: slot.full,
      durationMin: duration,
      taskDone: wt.done,
      onPlace: (startMin) => _placeAt(wt, day, startMin),
      onOpen: () => _openTask(wt),
      onDone: () => _toggleDone(wt),
      onRescheduleDeadline:
          wt.overdue && !wt.done ? () => _rescheduleDeadline(wt, day) : null,
    );
  }

  Future<void> _openDotMenu(ScheduleBlock b, Offset global) async {
    final date = _dateOfBlock(b);
    if (date == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
            enabled: false,
            child: Text('${b.startTime} · ${_fmtHm(b.durationMin)}',
                style: const TextStyle(fontWeight: FontWeight.w600))),
        const PopupMenuItem(value: 'tomorrow', child: Text('Déplacer à demain')),
        const PopupMenuItem(value: 'remove', child: Text('Retirer du programme')),
      ],
    );
    if (choice == 'tomorrow') await _blockToTomorrow(date, b);
    if (choice == 'remove') await _removeBlock(date, b);
  }

  Future<void> _editCapacity() async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _CapacityDialog(capacity: _capacity),
    );
    if (result == null) return;
    setState(() => _capacity = result);
    await widget.sync.saveWeekCapacity(result);
  }

  Future<void> _planWithOrion() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.sync.triggerOrionCycle();
    if (mounted) setState(() => _busy = false);
    _snack(ok
        ? 'ORION planifie ta semaine — le programme arrive dans Aujourd\'hui.'
        : 'ORION indisponible pour l\'instant.');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final active = tasks.where((t) => !t.task.isMilestone).toList();
    final done = active.where((t) => t.done).length;
    final late = tasks.where((t) => t.overdue).length;
    final toPlace = tasksToPlace(tasks).where((t) => !t.task.isMilestone).length;

    return Container(
      color: kBBg,
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _pageHeader(active: active.length, done: done, late: late, toPlace: toPlace),
        const SizedBox(height: 14),
        Expanded(child: _ganttCard(tasks)),
      ]),
    );
  }

  Widget _pageHeader({required int active, required int done, required int late, required int toPlace}) {
    final title = _days == 7
        ? 'Semaine du ${_start.day} ${_kMonthLong[_start.month - 1]}'
        : '14 jours à partir du ${_start.day} ${_kMonthShort[_start.month - 1]}';
    final isCurrent = _days == 7 ? _start == weekStart(_today) : _start == _today;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _iconBtn(Icons.chevron_left, _days == 7 ? 'Semaine précédente' : '14 jours avant', () => _shift(-1)),
      _iconBtn(Icons.chevron_right, _days == 7 ? 'Semaine suivante' : '14 jours après', () => _shift(1)),
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
            if (!isCurrent) ...[
              const SizedBox(width: 8),
              _textLink(_days == 7 ? 'Cette semaine' : "Aujourd'hui", () => _setWindow()),
            ],
          ]),
          const SizedBox(height: 2),
          Text(
            '$done / $active tâche${active > 1 ? 's' : ''} active${active > 1 ? 's' : ''} faite${done > 1 ? 's' : ''}'
            ' · $late en retard · $toPlace à caser',
            style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular),
          ),
        ]),
      ),
      _segmented(),
      const SizedBox(width: 8),
      _pillButton(_hideDone ? 'Afficher le fait' : 'Masquer le fait',
          icon: _hideDone ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          onTap: () {
            setState(() => _hideDone = !_hideDone);
            _savePrefs();
          }),
      const SizedBox(width: 4),
      _iconBtn(Icons.tune_outlined, 'Capacité par jour', _editCapacity),
      const SizedBox(width: 4),
      _pillButton('Planifier avec ORION',
          primary: true, icon: Icons.auto_awesome, onTap: _busy ? null : _planWithOrion),
    ]);
  }

  Widget _segmented() {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x12FFFFFF), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (n, lbl) in const [(7, '7 jours'), (14, '14 jours')])
          InkWell(
            onTap: () => _setWindow(days: n),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _days == n ? kBActive : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _days == n ? kBPrimary.withOpacity(.35) : Colors.transparent),
              ),
              child: Text(lbl,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _days == n ? kBText : kBText2)),
            ),
          ),
      ]),
    );
  }

  // ── Carte Gantt ─────────────────────────────────────────────────────────────

  Widget _ganttCard(List<WeekTask> tasks) {
    // Groupes par domaine (ordre des domaines, puis sans domaine), tâches par
    // date de début.
    final byDomain = <String?, List<WeekTask>>{};
    for (final t in tasks) {
      if (_hideDone && t.done) continue;
      byDomain.putIfAbsent(t.project.domainId, () => []).add(t);
    }
    for (final l in byDomain.values) {
      l.sort((a, b) {
        final c = a.task.startDate.compareTo(b.task.startDate);
        return c != 0 ? c : a.task.title.compareTo(b.task.title);
      });
    }
    final order = <String?>[
      for (final d in widget.domains)
        if (byDomain.containsKey(d.id)) d.id,
      for (final k in byDomain.keys)
        if (k != null && !widget.domains.any((d) => d.id == k)) k,
      if (byDomain.containsKey(null)) null,
    ];

    return Container(
      decoration: BoxDecoration(
        color: kBSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _dayHeaderRow(),
        const Divider(height: 1, color: kBLine),
        Expanded(
          child: tasks.isEmpty
              ? const Center(
                  child: Text('Aucune tâche sur cette période.',
                      style: TextStyle(fontSize: 13, color: kBText3)))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final did in order) ...[
                      _domainHeader(did, byDomain[did]!),
                      if (!_collapsed.contains(did ?? '_none'))
                        for (final wt in byDomain[did]!) _taskRow(wt),
                    ],
                  ],
                ),
        ),
        const Divider(height: 1, color: kBLine),
        _legend(),
      ]),
    );
  }

  Widget _dayHeaderRow() {
    return SizedBox(
      height: 58,
      child: Row(children: [
        const SizedBox(
          width: _kLeftCol,
          child: Padding(
            padding: EdgeInsets.only(left: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('TÂCHES PAR DOMAINE',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
            ),
          ),
        ),
        for (final d in _dates) Expanded(child: _dayHeader(d)),
      ]),
    );
  }

  Widget _dayHeader(DateTime d) {
    final key = ymdOf(d);
    final blocks = _byDay[key] ?? const <ScheduleBlock>[];
    final cap = capacityMinFor(_capacity, d);
    final planned = plannedMin(blocks);
    final blocked = isBlockedDay(blocks);
    final isToday = d == _today;
    final weekend = d.weekday >= 6;
    final v = cap == 0 ? 0.0 : (planned / cap).clamp(0.0, 1.0);
    final gaugeColor = blocked ? kBAttention : (v >= 1 ? kBAlert : kBPrimary);
    return Container(
      color: isToday ? kBPrimary.withOpacity(.10) : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_kDayShort[d.weekday - 1]} ${d.day}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isToday ? kBPrimary : (weekend ? kBText4 : kBText2),
                fontFeatures: _tabular)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 4,
            child: Stack(children: [
              Container(color: const Color(0x14FFFFFF)),
              FractionallySizedBox(widthFactor: blocked ? 1 : v, child: Container(color: gaugeColor)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          cap == 0
              ? 'repos'
              : blocked
                  ? 'journée bloquée'
                  : '${_fmtHm(planned)} / ${_fmtHm(cap)} · ${blocks.length} bloc${blocks.length > 1 ? 's' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, color: blocked ? kBAttention : kBText4, fontFeatures: _tabular),
        ),
      ]),
    );
  }

  Widget _domainHeader(String? domainId, List<WeekTask> tasks) {
    final d = widget.domains.where((x) => x.id == domainId).firstOrNull;
    final color = domainColor(domainId, widget.domains) ?? kBText4;
    final key = domainId ?? '_none';
    final collapsed = _collapsed.contains(key);
    final real = tasks.where((t) => !t.task.isMilestone).toList();
    final done = real.where((t) => t.done).length;
    var planned = 0;
    for (final t in tasks) {
      planned += plannedMinForTask(t.task, _allBlocks);
    }
    return InkWell(
      onTap: () {
        setState(() => collapsed ? _collapsed.remove(key) : _collapsed.add(key));
        _savePrefs();
      },
      child: Container(
        height: _kDomainH,
        color: color.withOpacity(.10),
        padding: const EdgeInsets.only(left: 18),
        child: Row(children: [
          Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 15, color: kBText3),
          const SizedBox(width: 6),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text((d?.name ?? 'Sans domaine').toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: color)),
          const SizedBox(width: 6),
          Text(
            ' · $done / ${real.length} faite${done > 1 ? 's' : ''}'
            '${planned > 0 ? ' · ${_fmtHm(planned)} planifiées' : ''}',
            style: const TextStyle(fontSize: 11, color: kBText3, fontFeatures: _tabular),
          ),
        ]),
      ),
    );
  }

  Widget _taskRow(WeekTask wt) {
    final t = wt.task;
    final color = _taskColor(wt);
    final blocks = _blocksOfTask(t.id);
    final remaining = remainingToPlaceMin(t, _allBlocks);
    final openActions = t.actions.where((a) => !a.done).length;
    final overdueDays = wt.overdue ? _today.difference(dateOnly(t.endDate ?? t.startDate)).inDays : 0;

    return SizedBox(
      height: _kRowH,
      child: Row(children: [
        SizedBox(
          width: _kLeftCol,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 12),
            child: Row(children: [
              if (wt.done) ...[
                const Icon(Icons.check_circle, size: 15, color: kBPrimaryDark),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Tooltip(
                  message: wt.project.title,
                  waitDuration: const Duration(milliseconds: 600),
                  child: InkWell(
                    onTap: () => _openTask(wt),
                    child: Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w500,
                            color: wt.done ? kBText3 : kBText,
                            decoration: wt.done ? TextDecoration.lineThrough : null,
                            decorationColor: kBText3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (t.isMilestone)
                _badge('jalon', kBAttention)
              else if (wt.overdue && !wt.done)
                _badge('−$overdueDays j', kBAlert)
              else if (t.actions.isNotEmpty)
                Text('${t.actions.length - openActions}/${t.actions.length}',
                    style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular)),
            ]),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            final colW = box.maxWidth / _days;
            return Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    days: _days,
                    todayIdx: _dayIndex(_today),
                    weekend: [for (var i = 0; i < _days; i++) _dates[i].weekday >= 6],
                  ),
                ),
              ),
              // Cellules : clic = popover « caser » ; « + » au survol.
              Positioned.fill(
                child: Row(children: [
                  for (var i = 0; i < _days; i++) Expanded(child: _cell(wt, i)),
                ]),
              ),
              if (t.isMilestone)
                ..._milestone(wt, colW)
              else if (blocks.isEmpty && !wt.done)
                _toPlaceBar(wt, colW, color, remaining)
              else
                ..._bar(wt, colW, color, blocks, remaining),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _cell(WeekTask wt, int i) {
    final past = _dates[i].isBefore(_today);
    return _HoverCell(
      enabled: !past && !wt.done && !wt.task.isMilestone,
      onTapUp: (d) => _openPopover(wt, i, d.globalPosition),
    );
  }

  List<Widget> _milestone(WeekTask wt, double colW) {
    final span = _span(wt.task);
    if (span == null) return const [];
    final c = wt.done ? kBPrimaryDark : kBAttention;
    return [
      Positioned(
        left: colW * span.e + colW / 2 - 6,
        top: _kRowH / 2 - 6,
        child: GestureDetector(
          onTap: () => _openTask(wt),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2), border: Border.all(color: c, width: 1.5)),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _toPlaceBar(WeekTask wt, double colW, Color color, int remaining) {
    var start = dateOnly(wt.task.startDate);
    if (start.isBefore(_today)) start = _today;
    final idx = _dayIndex(start) ?? 0;
    final c = wt.overdue ? kBAlert : color;
    return Positioned(
      left: colW * idx + 3,
      width: colW - 6,
      top: _kBarTop,
      height: _kBarH,
      child: GestureDetector(
        onTapUp: (d) => _openPopover(wt, idx, d.globalPosition),
        onSecondaryTapUp: (_) => _pickColor(wt),
        child: CustomPaint(
          painter: _DashedRectPainter(color: c, radius: 6, strokeWidth: 1.5),
          child: Center(
            child: Text('à caser · ${_fmtHm(remaining == 0 ? wt.task.plannedMin : remaining)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c, fontFeatures: _tabular)),
          ),
        ),
      ),
    );
  }

  /// Colonne du jour d'un bloc de la fenêtre (null si introuvable).
  int? _blockDayIdx(ScheduleBlock b) {
    final date = _dateOfBlock(b);
    return date == null ? null : _dayIndex(DateTime.parse(date));
  }

  List<Widget> _bar(WeekTask wt, double colW, Color color, List<ScheduleBlock> blocks, int remaining) {
    // La barre couvre les dates de la tâche ET les jours de ses blocs : une
    // tâche en retard (dates avant la fenêtre) planifiée mardi reste visible,
    // avec son point, sur mardi.
    var span = _span(wt.task);
    final idx = blocks.map(_blockDayIdx).whereType<int>().toList();
    if (idx.isNotEmpty) {
      final mn = idx.reduce(math.min), mx = idx.reduce(math.max);
      span = span == null ? (s: mn, e: mx) : (s: math.min(span.s, mn), e: math.max(span.e, mx));
    }
    if (span == null) return const [];
    final dragging = _dragTaskId == wt.task.id;
    final deltaDays = dragging ? (_dragDx / colW).round() : 0;
    final s = span.s + (dragging && !_dragResize ? deltaDays : 0);
    final e = span.e + (dragging ? deltaDays : 0);
    final left = colW * s + 3;
    final width = math.max(colW * (e - s + 1) - 6, 18.0);
    final fill = color.withOpacity(wt.done ? .35 : .75);
    return [
      Positioned(
        left: left,
        width: width,
        top: _kBarTop,
        height: _kBarH,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _openPopover(
              wt, (s + (d.localPosition.dx / colW).floor()).clamp(0, _days - 1), d.globalPosition),
          onSecondaryTapUp: (_) => _pickColor(wt),
          onHorizontalDragStart: (_) => setState(() {
            _dragTaskId = wt.task.id;
            _dragResize = false;
            _dragDx = 0;
          }),
          onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
          onHorizontalDragEnd: (_) {
            final delta = (_dragDx / colW).round();
            setState(() => _dragTaskId = null);
            _shiftTask(wt, delta);
          },
          onHorizontalDragCancel: () => setState(() => _dragTaskId = null),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: dragging ? Border.all(color: Colors.white.withOpacity(.6)) : null,
            ),
            padding: const EdgeInsets.only(left: 8, right: 10),
            child: ClipRect(
              child: Row(children: [
                for (final b in blocks) ...[
                  InkWell(
                    onTapDown: (d) => _openDotMenu(b, d.globalPosition),
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: kBBg, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(_fmtHm(b.durationMin),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: kBBg, fontFeatures: _tabular)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (remaining > 0 && !wt.done)
                  Flexible(
                    child: Text('reste ${_fmtHm(remaining)} à caser',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: kBBg.withOpacity(.6), fontFeatures: _tabular)),
                  ),
              ]),
            ),
          ),
        ),
      ),
      // Poignée droite : étendre / réduire l'échéance.
      Positioned(
        left: left + width - 6,
        width: 8,
        top: _kBarTop,
        height: _kBarH,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() {
              _dragTaskId = wt.task.id;
              _dragResize = true;
              _dragDx = 0;
            }),
            onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
            onHorizontalDragEnd: (_) {
              final delta = (_dragDx / colW).round();
              setState(() => _dragTaskId = null);
              _resizeTask(wt, delta);
            },
            onHorizontalDragCancel: () => setState(() => _dragTaskId = null),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.55), borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _legend() {
    Widget item(Widget swatch, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          swatch,
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11.5, color: kBText3)),
        ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(children: [
        item(
            Container(
                width: 18,
                height: 8,
                decoration: BoxDecoration(
                    color: kBPrimary.withOpacity(.75), borderRadius: BorderRadius.circular(3))),
            'tâche prévue'),
        const SizedBox(width: 16),
        item(Container(width: 6, height: 6, decoration: const BoxDecoration(color: kBText, shape: BoxShape.circle)),
            'bloc dans le programme'),
        const SizedBox(width: 16),
        item(
            SizedBox(
                width: 18,
                height: 8,
                child: CustomPaint(painter: _DashedRectPainter(color: kBText3, radius: 3, strokeWidth: 1.2))),
            'à caser'),
        const SizedBox(width: 16),
        item(
            Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: kBAttention, borderRadius: BorderRadius.circular(1)))),
            'jalon'),
        const Spacer(),
        const Flexible(
          child: Text(
            'Clic sur un jour = caser · glisser une barre = déplacer · tirer le bord = étendre · clic droit = couleur',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: kBText4),
          ),
        ),
      ]),
    );
  }

  // ── Briques ─────────────────────────────────────────────────────────────────

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(.18), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
      );

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: kBText2),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  Widget _textLink(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
        ),
      );

  Widget _pillButton(String label, {bool primary = false, IconData? icon, VoidCallback? onTap}) {
    final fg = primary ? kBBg : kBText;
    return SizedBox(
      height: 36,
      child: TextButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 15, color: fg),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: primary ? kBPrimary : const Color(0x12FFFFFF),
          disabledBackgroundColor: primary ? kBPrimary.withOpacity(.4) : const Color(0x0AFFFFFF),
          foregroundColor: fg,
          disabledForegroundColor: fg.withOpacity(.5),
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 12),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Cellule survolable (« + » discret) ───────────────────────────────────────

class _HoverCell extends StatefulWidget {
  final bool enabled;
  final void Function(TapUpDetails) onTapUp;
  const _HoverCell({required this.enabled, required this.onTapUp});

  @override
  State<_HoverCell> createState() => _HoverCellState();
}

class _HoverCellState extends State<_HoverCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.expand();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onTapUp,
        child: Center(
          child: _hover ? const Icon(Icons.add, size: 14, color: kBText4) : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ── Peintres ─────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final int days;
  final int? todayIdx;
  final List<bool> weekend;
  const _GridPainter({required this.days, required this.todayIdx, required this.weekend});

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / days;
    final sep = Paint()..color = const Color(0x0FFFFFFF);
    final we = Paint()..color = const Color(0x04FFFFFF);
    for (var i = 0; i < days; i++) {
      final x = colW * i;
      if (weekend[i]) canvas.drawRect(Rect.fromLTWH(x, 0, colW, size.height), we);
      if (i > 0) canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), sep);
    }
    if (todayIdx != null) {
      final r = Rect.fromLTWH(colW * todayIdx!, 0, colW, size.height);
      canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBPrimary.withOpacity(.13), kBPrimary.withOpacity(.05)],
            ).createShader(r));
      final border = Paint()..color = kBPrimary.withOpacity(.25);
      canvas.drawRect(Rect.fromLTWH(r.left, 0, 1, size.height), border);
      canvas.drawRect(Rect.fromLTWH(r.right - 1, 0, 1, size.height), border);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.days != days || old.todayIdx != todayIdx || old.weekend != weekend;
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  const _DashedRectPainter({required this.color, required this.radius, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}

// ── Dialog « Capacité » ───────────────────────────────────────────────────────

class _CapacityDialog extends StatefulWidget {
  final Map<String, int> capacity;
  const _CapacityDialog({required this.capacity});

  @override
  State<_CapacityDialog> createState() => _CapacityDialogState();
}

class _CapacityDialogState extends State<_CapacityDialog> {
  late final Map<String, TextEditingController> _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = {
      for (final k in kWeekDayKeys) k: TextEditingController(text: _fmtHours(widget.capacity[k] ?? 0)),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmtHours(int min) {
    if (min % 60 == 0) return '${min ~/ 60}';
    return (min / 60).toStringAsFixed(1).replaceAll('.', ',');
  }

  int? _parse(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    if (v == null || v < 0 || v > 16) return null;
    return (v * 60).round();
  }

  bool get _valid => _ctrl.values.every((c) => _parse(c.text) != null);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Capacité par jour',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
            const SizedBox(height: 4),
            const Text('Heures que tu peux consacrer au programme chaque jour. 0 = repos.',
                style: TextStyle(fontSize: 12.5, color: kBText3, height: 1.4)),
            const SizedBox(height: 16),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 110,
                    child: Text(_kDayLong[i][0].toUpperCase() + _kDayLong[i].substring(1),
                        style: const TextStyle(fontSize: 13.5, color: kBText)),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _ctrl[kWeekDayKeys[i]],
                      onChanged: (_) => setState(() {}),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: kBText, fontFeatures: _tabular),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: 'h',
                        errorText: _parse(_ctrl[kWeekDayKeys[i]]!.text) == null ? '0–16' : null,
                      ),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(defaultWeekCapacity()),
                child: const Text('Par défaut'),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _valid
                    ? () => Navigator.of(context).pop({
                          for (final k in kWeekDayKeys) k: _parse(_ctrl[k]!.text)!,
                        })
                    : null,
                style: FilledButton.styleFrom(backgroundColor: kBPrimary, foregroundColor: kBBg),
                child: const Text('Enregistrer'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
