import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/web/wide_gantt_dialog.dart';

// Vue « Cette semaine » (refonte web § 3) : Gantt 7 jours des tâches (haut) +
// organisation de la semaine (à caser → jours, capacité, ORION) en bas.

const _kDayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const _kDayLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _kMonthShort = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
];
const _tabular = [FontFeature.tabularFigures()];
const _kLeftCol = 250.0;

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _clock(int min) => '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

/// Charge utile d'un glisser-déposer : une tâche à caser OU un bloc déplacé.
class _DragTask {
  final WeekTask task;
  const _DragTask(this.task);
}

class _DragBlock {
  final String fromDate;
  final ScheduleBlock block;
  const _DragBlock(this.fromDate, this.block);
}

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
  late DateTime _monday;
  final Map<String, List<ScheduleBlock>> _byDay = {};
  final List<StreamSubscription<DailySchedule?>> _subs = [];
  Map<String, int> _capacity = defaultWeekCapacity();
  bool _busy = false;

  DateTime get _today => dateOnly(DateTime.now());
  List<DateTime> get _days => weekDates(_monday);
  List<ScheduleBlock> get _allBlocks => [for (final l in _byDay.values) ...l];

  @override
  void initState() {
    super.initState();
    _monday = weekStart(DateTime.now());
    _subscribe();
    widget.sync.fetchWeekCapacity().then((c) {
      if (mounted) setState(() => _capacity = c);
    });
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _byDay.clear();
    for (final d in _days) {
      final key = ymdOf(d);
      _subs.add(widget.sync.streamDailySchedule(key).listen((s) {
        if (!mounted) return;
        setState(() {
          _byDay[key] = (s?.blocks.where((b) => b.status != 'deleted').toList() ?? [])
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
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

  void _shiftWeek(int weeks) {
    setState(() => _monday = _monday.add(Duration(days: 7 * weeks)));
    _subscribe();
  }

  // ── Données dérivées ────────────────────────────────────────────────────────

  List<WeekTask> get _tasks => weekTasks(
        projects: widget.projects,
        monday: _monday,
        scheduled: _allBlocks,
        today: _today,
      );

  // ── Actions ─────────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1800),
    ));
  }

  Future<void> _placeTask(WeekTask wt, DateTime day) async {
    final key = ymdOf(day);
    final blocks = _byDay[key] ?? [];
    final start = firstFreeSlot(blocks, wt.task.plannedMin);
    if (start == null) {
      _snack('Pas de créneau libre ${_kDayLong[day.weekday - 1]} pour ${_fmtHm(wt.task.plannedMin)}.');
      return;
    }
    final block = taskBlock(wt, start);
    setState(() => (_byDay[key] ??= []).add(block));
    await widget.sync.addScheduleBlock(key, block);
    _snack('Bloc ajouté ${_kDayLong[day.weekday - 1]} ${_clock(start)}');
  }

  Future<void> _moveBlock(_DragBlock drag, DateTime day) async {
    final to = ymdOf(day);
    if (to == drag.fromDate) return;
    final b = drag.block;
    final copy = ScheduleBlock(
      startTime: b.startTime,
      durationMin: b.durationMin,
      title: b.title,
      category: b.category,
      projectId: b.projectId,
      taskId: b.taskId,
      activityId: b.activityId,
      actionId: b.actionId,
    );
    setState(() {
      _byDay[drag.fromDate]?.remove(b);
      (_byDay[to] ??= []).add(copy);
    });
    await widget.sync.updateBlockStatus(drag.fromDate, b.id, 'deleted');
    await widget.sync.addScheduleBlock(to, copy);
    _snack('Bloc déplacé ${_kDayLong[day.weekday - 1]} ${b.startTime}');
  }

  Future<void> _autoPlace() async {
    if (_busy) return;
    final toPlace = tasksToPlace(_tasks);
    if (toPlace.isEmpty) return;
    final r = autoPlace(
      toPlace: toPlace,
      days: _days,
      scheduledByDay: _byDay,
      capacity: _capacity,
      today: _today,
    );
    var n = 0;
    setState(() {
      _busy = true;
      for (final e in r.blocks.entries) {
        (_byDay[e.key] ??= []).addAll(e.value);
        n += e.value.length;
      }
    });
    try {
      for (final e in r.blocks.entries) {
        for (final b in e.value) {
          await widget.sync.addScheduleBlock(e.key, b);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _snack(n == 0
        ? 'Aucune place cette semaine : ajuste la capacité ou passe à la semaine suivante.'
        : '$n bloc${n > 1 ? 's' : ''} ajouté${n > 1 ? 's' : ''}'
            '${r.left.isEmpty ? '' : ' · ${r.left.length} sans place'}');
  }

  Future<void> _toggleTask(WeekTask wt) async {
    setState(() => wt.task.status = wt.task.status == 'done' ? 'pending' : 'done');
    await widget.sync.saveProjectTasks(wt.project.id, wt.project.tasks);
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
    final toPlace = tasksToPlace(tasks);
    final active = tasks.where((t) => !t.done).length;
    final done = tasks.where((t) => t.done).length;
    final planned = plannedMin(_allBlocks);
    final capacity = _days.fold<int>(0, (s, d) => s + capacityMinFor(_capacity, d));

    return Container(
      color: kBBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
        children: [
          _header(active: active, done: done, toPlace: toPlace.length,
              planned: planned, capacity: capacity),
          const SizedBox(height: 18),
          _ganttCard(tasks),
          const SizedBox(height: 18),
          _organizeSection(toPlace),
        ],
      ),
    );
  }

  Widget _header({
    required int active,
    required int done,
    required int toPlace,
    required int planned,
    required int capacity,
  }) {
    final sunday = _days.last;
    final sameMonth = _monday.month == sunday.month;
    final title = 'Semaine du ${_monday.day}'
        '${sameMonth ? '' : ' ${_kMonthShort[_monday.month - 1]}'}'
        ' au ${sunday.day} ${_kMonthShort[sunday.month - 1]}';
    final isCurrent = _monday == weekStart(_today);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
          const SizedBox(width: 10),
          _iconBtn(Icons.chevron_left, 'Semaine précédente', () => _shiftWeek(-1)),
          _iconBtn(Icons.chevron_right, 'Semaine suivante', () => _shiftWeek(1)),
          if (!isCurrent) ...[
            const SizedBox(width: 4),
            _textLink('Cette semaine', () {
              setState(() => _monday = weekStart(_today));
              _subscribe();
            }),
          ],
        ]),
        const SizedBox(height: 3),
        Text(
          '$active tâche${active > 1 ? 's' : ''} active${active > 1 ? 's' : ''} · '
          '$done faite${done > 1 ? 's' : ''} · $toPlace à caser · '
          '${_fmtHm(planned)} planifiées sur ${_fmtHm(capacity)}',
          style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular),
        ),
      ]),
      const Spacer(),
      _iconBtn(Icons.tune_outlined, 'Capacité par jour', _editCapacity),
      const SizedBox(width: 6),
      _pillButton('Vue 14 jours',
          onTap: () => showWideGanttDialog(context,
              projects: widget.projects, domains: widget.domains)),
      const SizedBox(width: 8),
      _pillButton('Planifier la semaine avec ORION',
          primary: true, icon: Icons.auto_awesome, onTap: _busy ? null : _planWithOrion),
    ]);
  }

  // ── TÂCHES DE LA SEMAINE ────────────────────────────────────────────────────

  Widget _ganttCard(List<WeekTask> tasks) {
    final byDomain = <String?, List<WeekTask>>{};
    for (final t in tasks) {
      byDomain.putIfAbsent(t.project.domainId, () => []).add(t);
    }
    final domainOrder = [
      for (final d in widget.domains)
        if (byDomain.containsKey(d.id)) d.id,
      if (byDomain.containsKey(null)) null,
      for (final k in byDomain.keys)
        if (k != null && !widget.domains.any((d) => d.id == k)) k,
    ];

    return _card(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('TÂCHES DE LA SEMAINE'),
        const SizedBox(height: 12),
        _dayHeaderRow(),
        const Divider(height: 1, color: kBLine),
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('Aucune tâche cette semaine.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kBText3)),
          )
        else
          for (final did in domainOrder) ...[
            _domainHeader(did),
            for (final t in byDomain[did]!) _taskRow(t),
          ],
      ]),
    );
  }

  Widget _dayHeaderRow() {
    return Row(children: [
      const SizedBox(width: _kLeftCol),
      for (final d in _days)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Text(_kDayShort[d.weekday - 1],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: d == _today
                          ? kBPrimary
                          : d.weekday >= 6
                              ? kBText4
                              : kBText3)),
              const SizedBox(height: 2),
              Text('${d.day}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: d == _today ? FontWeight.w700 : FontWeight.w500,
                      color: d == _today ? kBPrimary : kBText2,
                      fontFeatures: _tabular)),
            ]),
          ),
        ),
    ]);
  }

  Widget _domainHeader(String? domainId) {
    final d = widget.domains.where((x) => x.id == domainId).firstOrNull;
    final color = domainColor(domainId, widget.domains) ?? kBText4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(d?.name ?? 'Sans domaine',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: kBText3)),
      ]),
    );
  }

  Widget _taskRow(WeekTask wt) {
    final t = wt.task;
    final color = domainColor(wt.project.domainId, widget.domains) ?? kBPrimaryDark;
    final start = dateOnly(t.startDate);
    final end = dateOnly(t.endDate ?? t.startDate);
    final sunday = _days.last;
    // Indices de colonne, tronqués à la semaine (-1 = hors semaine).
    final s = start.isBefore(_monday) ? 0 : start.difference(_monday).inDays;
    final e = end.isAfter(sunday) ? 6 : end.difference(_monday).inDays;
    final inWeek = s <= 6 && e >= 0;

    final titleStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: wt.done ? kBText3 : kBText,
      decoration: wt.done ? TextDecoration.lineThrough : null,
      decorationColor: kBText3,
    );

    return SizedBox(
      height: 40,
      child: Row(children: [
        SizedBox(
          width: _kLeftCol,
          child: Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _toggleTask(wt),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  wt.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 17,
                  color: wt.done ? kBPrimaryDark : kBText3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () => widget.onOpenProject(wt.project, taskId: t.id),
                child: Text(t.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
              ),
            ),
            if (wt.overdue && !wt.done) ...[
              const SizedBox(width: 6),
              _badge('retard', kBAlert),
            ],
            const SizedBox(width: 10),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, box) {
            final colW = box.maxWidth / 7;
            if (!inWeek) {
              // Tâche en retard hors semaine : rappel discret à gauche.
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    'échéance ${t.endDate != null ? '${t.endDate!.day} ${_kMonthShort[t.endDate!.month - 1]}' : '—'} · à caser',
                    style: const TextStyle(fontSize: 11.5, color: kBAlert, fontFeatures: _tabular),
                  ),
                ),
              );
            }
            if (t.isMilestone) {
              return Stack(children: [
                Positioned(
                  left: colW * e + colW / 2 - 7,
                  top: 13,
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: wt.done ? kBAttention : Colors.transparent,
                          border: Border.all(color: kBAttention, width: 1.5),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
                Positioned(
                  left: colW * e + colW / 2 + 12,
                  top: 9,
                  child: _badge('${_kDayShort[end.weekday - 1]} ${end.day}', kBAttention),
                ),
              ]);
            }
            final label = wt.done
                ? null
                : wt.planned
                    ? '${wt.project.title} · ${wt.plannedBlocks} bloc${wt.plannedBlocks > 1 ? 's' : ''} planifié${wt.plannedBlocks > 1 ? 's' : ''}'
                    : 'à caser';
            return Stack(children: [
              Positioned(
                left: colW * s + 3,
                width: colW * (e - s + 1) - 6,
                top: 8,
                height: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: wt.done
                        ? color.withOpacity(.25)
                        : wt.planned
                            ? color
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: wt.planned || wt.done
                        ? null
                        : Border.all(
                            color: wt.overdue ? kBAlert : color.withOpacity(.7),
                            width: 1.2,
                            strokeAlign: BorderSide.strokeAlignInside),
                  ),
                  child: label == null
                      ? null
                      : Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: wt.planned
                                  ? kBBg
                                  : wt.overdue
                                      ? kBAlert
                                      : kBText2)),
                ),
              ),
            ]);
          }),
        ),
      ]),
    );
  }

  // ── ORGANISER LA SEMAINE ────────────────────────────────────────────────────

  Widget _organizeSection(List<WeekTask> toPlace) {
    return LayoutBuilder(builder: (ctx, box) {
      final narrow = box.maxWidth < 1000;
      final left = _toPlaceCard(toPlace);
      final right = _daysBoard();
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          left,
          const SizedBox(height: 18),
          right,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: _kLeftCol + 20, child: left),
        const SizedBox(width: 18),
        Expanded(child: right),
      ]);
    });
  }

  Widget _toPlaceCard(List<WeekTask> toPlace) {
    return _card(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label(toPlace.isEmpty ? 'À CASER' : 'À CASER · ${toPlace.length}',
            color: toPlace.any((t) => t.overdue) ? kBAlert : kBText3),
        const SizedBox(height: 12),
        if (toPlace.isEmpty)
          const Text('Tout est planifié.', style: TextStyle(fontSize: 13, color: kBText3))
        else ...[
          for (final wt in toPlace)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Draggable<Object>(
                data: _DragTask(wt),
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(width: _kLeftCol, child: _toPlaceTile(wt, dragging: true)),
                ),
                childWhenDragging: Opacity(opacity: .35, child: _toPlaceTile(wt)),
                child: _toPlaceTile(wt),
              ),
            ),
          const SizedBox(height: 6),
          _pillButton('Tout caser automatiquement',
              icon: Icons.auto_fix_high_outlined, onTap: _busy ? null : _autoPlace),
          const SizedBox(height: 8),
          const Text('Glisse une tâche sur un jour, ou laisse-moi caser au premier créneau libre.',
              style: TextStyle(fontSize: 11.5, color: kBText4, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _toPlaceTile(WeekTask wt, {bool dragging = false}) {
    final t = wt.task;
    final sub = wt.overdue
        ? 'en retard · ${_fmtHm(t.plannedMin)} estimées'
        : 'reste ${_fmtHm(t.plannedMin)} · ${wt.project.title}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: dragging ? kBActive : kBRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dragging ? kBPrimary.withOpacity(.5) : kBLine),
      ),
      child: Row(children: [
        const Icon(Icons.drag_indicator, size: 16, color: kBText4),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kBText)),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    color: wt.overdue ? kBAlert : kBText3,
                    fontFeatures: _tabular)),
          ]),
        ),
      ]),
    );
  }

  Widget _daysBoard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: SizedBox(
        height: 360,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _dayColumn(_days[i])),
          ],
        ]),
      ),
    );
  }

  Widget _dayColumn(DateTime day) {
    final key = ymdOf(day);
    final blocks = _byDay[key] ?? [];
    final cap = capacityMinFor(_capacity, day);
    final planned = plannedMin(blocks);
    final blocked = isBlockedDay(blocks);
    final past = day.isBefore(_today);
    final isToday = day == _today;
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;

    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => !past && (d.data is _DragTask || d.data is _DragBlock),
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is _DragTask) _placeTask(data.task, day);
        if (data is _DragBlock) _moveBlock(data, day);
      },
      builder: (ctx, candidates, _) {
        final hover = candidates.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: hover ? kBActive : (isToday ? kBSurface : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hover
                    ? kBPrimary.withOpacity(.6)
                    : isToday
                        ? kBPrimary.withOpacity(.25)
                        : kBLine),
          ),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(_kDayShort[day.weekday - 1],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: isToday ? kBPrimary : (day.weekday >= 6 ? kBText4 : kBText3))),
              const SizedBox(width: 4),
              Text('${day.day}',
                  style: TextStyle(
                      fontSize: 12,
                      color: isToday ? kBPrimary : kBText2,
                      fontFeatures: _tabular)),
            ]),
            const SizedBox(height: 6),
            _gauge(planned, cap, blocked: blocked),
            const SizedBox(height: 3),
            Text(
              cap == 0
                  ? 'repos'
                  : blocked
                      ? 'journée bloquée'
                      : '${_fmtHm(planned)} / ${_fmtHm(cap)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  color: blocked ? kBAttention : kBText4,
                  fontFeatures: _tabular),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final b in blocks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: past
                        ? _chip(b, key, current: false)
                        : Draggable<Object>(
                            data: _DragBlock(key, b),
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(width: 140, child: _chip(b, key, current: false)),
                            ),
                            childWhenDragging: Opacity(opacity: .3, child: _chip(b, key, current: false)),
                            child: _chip(b, key,
                                current: isToday &&
                                    b.status == 'pending' &&
                                    blockStartMin(b) <= nowMin &&
                                    nowMin < blockEndMin(b)),
                          ),
                  ),
              ]),
            ),
            if (!past)
              Container(
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: hover ? kBPrimary.withOpacity(.6) : kBLine,
                      width: 1),
                ),
                child: Text(hover ? 'déposer' : 'déposer ici',
                    style: TextStyle(
                        fontSize: 11, color: hover ? kBPrimary : kBText4)),
              ),
          ]),
        );
      },
    );
  }

  Widget _chip(ScheduleBlock b, String date, {required bool current}) {
    final color = kBCategoryColor[b.category] ?? const Color(0xFF8E9AAF);
    final done = b.status == 'done';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(done ? .08 : .16),
        borderRadius: BorderRadius.circular(6),
        border: current ? Border.all(color: kBPrimary.withOpacity(.7)) : null,
      ),
      child: Row(children: [
        Text(b.startTime,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: done ? kBText4 : color,
                fontFeatures: _tabular)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(b.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5,
                  color: done ? kBText3 : kBText,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: kBText3)),
        ),
      ]),
    );
  }

  Widget _gauge(int planned, int cap, {required bool blocked}) {
    final v = cap == 0 ? 0.0 : (planned / cap).clamp(0.0, 1.0);
    final color = blocked ? kBAttention : (v >= 1 ? kBAlert : kBPrimary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
        child: Stack(children: [
          Container(color: const Color(0x14FFFFFF)),
          FractionallySizedBox(
              widthFactor: blocked ? 1 : v, child: Container(color: color)),
        ]),
      ),
    );
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

  Widget _label(String text, {Color color = kBText3}) => Text(text,
      style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: color));

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
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
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: kBPrimary)),
        ),
      );

  Widget _pillButton(String label,
      {bool primary = false, IconData? icon, VoidCallback? onTap}) {
    final fg = primary ? kBBg : kBText;
    return SizedBox(
      height: 40,
      child: TextButton.icon(
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16, color: fg),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: primary ? kBPrimary : const Color(0x12FFFFFF),
          disabledBackgroundColor: primary ? kBPrimary.withOpacity(.4) : const Color(0x0AFFFFFF),
          foregroundColor: fg,
          disabledForegroundColor: fg.withOpacity(.5),
          shape: const StadiumBorder(),
          padding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 14),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
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
      for (final k in kWeekDayKeys)
        k: TextEditingController(text: _fmtHours(widget.capacity[k] ?? 0)),
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
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler')),
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
