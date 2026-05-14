// ignore_for_file: deprecated_member_use

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/new_action_sheet.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';

class WeeklyView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final String? highlightYmd;

  const WeeklyView({
    super.key,
    required this.logic,
    required this.state,
    this.highlightYmd,
  });

  @override
  State<WeeklyView> createState() => _WeeklyViewState();
}

class _WeeklyViewState extends State<WeeklyView> {
  late DateTime _weekStart;
  late Set<String> _expanded;
  Set<String> _routinesExpanded = {};
  Set<String> _doneExpanded = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _expanded = {yyyymmdd(today)};
    _routinesExpanded = {yyyymmdd(today)};
  }

  @override
  void didUpdateWidget(WeeklyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ymd = widget.highlightYmd;
    if (ymd != null && ymd != oldWidget.highlightYmd) {
      final year = int.parse(ymd.substring(0, 4));
      final month = int.parse(ymd.substring(4, 6));
      final day = int.parse(ymd.substring(6, 8));
      final d = DateTime(year, month, day);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      setState(() {
        _weekStart = monday;
        _expanded.add(ymd);
      });
    }
  }

  static const _dayNames = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _monthNames = [
    '', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
    'juil', 'aoû', 'sep', 'oct', 'nov', 'déc',
  ];

  String _fmtDay(DateTime d) =>
      '${_dayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month]}';

  String _fmtWeekRange() {
    final end = _weekStart.add(const Duration(days: 6));
    if (_weekStart.month == end.month) {
      return '${_weekStart.day} – ${end.day} ${_monthNames[end.month]}';
    }
    return '${_weekStart.day} ${_monthNames[_weekStart.month]} – ${end.day} ${_monthNames[end.month]}';
  }

  List<DayPlanItem> _actionsFor(String ymd) => widget.logic.state.dayPlan
      .where((it) =>
          it.yyyymmdd == ymd &&
          it.kind == PlanKind.action &&
          !it.archived &&
          !it.done)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  List<DayPlanItem> _doneActionsFor(String ymd) => widget.logic.state.dayPlan
      .where((it) =>
          it.yyyymmdd == ymd &&
          it.kind == PlanKind.action &&
          !it.archived &&
          it.done)
      .toList();

  List<Activity> _dailyRoutines() => widget.logic.state.activities
      .where((a) =>
          a.isHabit &&
          widget.logic.effectiveHabitFreq(a) == HabitFreq.daily)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  Future<void> _addAction(BuildContext context, String ymd) async {
    final result = await showNewActionSheet(context, logic: widget.logic);
    if (result == null) return;
    await widget.logic.addPlanAction(
      ymd: ymd,
      title: result.title,
      domainId: result.domainId,
      activityId: result.activityId,
      blockId: result.blockId,
      goalId: result.goalId,
    );
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayYmd = yyyymmdd(today);

    return ValueListenableBuilder<int>(
      valueListenable: widget.logic.rev,
      builder: (context, _, __) {
        final dailyRoutines = _dailyRoutines();

        return Column(
          children: [
            // ── En-tête navigation semaine ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _weekStart =
                          _weekStart.subtract(const Duration(days: 7));
                    }),
                  ),
                  Expanded(
                    child: Text(
                      'Semaine du ${_fmtWeekRange()}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                      _weekStart = _weekStart.add(const Duration(days: 7));
                    }),
                  ),
                ],
              ),
            ),

            // ── 7 jours ─────────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: 7,
                itemBuilder: (context, i) {
                  final day = _weekStart.add(Duration(days: i));
                  final ymd = yyyymmdd(day);
                  final isToday = ymd == todayYmd;
                  final isPast = day.isBefore(today);
                  final isFuture = day.isAfter(today);
                  final isExpanded = _expanded.contains(ymd);

                  final actions = _actionsFor(ymd);       // non-faites
                  final doneActions = _doneActionsFor(ymd); // faites
                  // Routines : passé et aujourd'hui seulement
                  final routineItems = isFuture ? <Activity>[] : dailyRoutines;

                  final routinesDone = routineItems.where((r) {
                    final v = widget.logic.habitValueOn(r.id, day);
                    return v >= widget.logic.effectiveHabitTarget(r);
                  }).length;
                  final done = doneActions.length + routinesDone;
                  final total = actions.length + doneActions.length + routineItems.length;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isToday
                        ? cs.primaryContainer.withOpacity(.25)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isToday
                          ? BorderSide(
                              color: cs.primary.withOpacity(.4), width: 1.5)
                          : BorderSide.none,
                    ),
                    child: Column(
                      children: [
                        // En-tête du jour
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() {
                            if (isExpanded) {
                              _expanded.remove(ymd);
                            } else {
                              _expanded.add(ymd);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                            child: Row(
                              children: [
                                Text(
                                  _fmtDay(day),
                                  style: TextStyle(
                                    fontWeight: isToday
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: 14,
                                    color: isToday ? cs.primary : null,
                                  ),
                                ),
                                if (isToday)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: cs.primary,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        'aujourd\'hui',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                if (total > 0)
                                  Text(
                                    '$done/$total',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: done == total && total > 0
                                          ? cs.primary
                                          : cs.onSurface.withOpacity(.5),
                                    ),
                                  ),
                                if (total > 0 && done == total)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(Icons.check_circle,
                                        size: 14, color: cs.primary),
                                  ),
                                const SizedBox(width: 4),
                                // Bouton +
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(Icons.add,
                                        size: 18,
                                        color: cs.onSurface.withOpacity(.5)),
                                    onPressed: () =>
                                        _addAction(context, ymd),
                                  ),
                                ),
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: cs.onSurface.withOpacity(.4),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Contenu déplié
                        if (isExpanded) ...[
                          const Divider(height: 1, indent: 14, endIndent: 14),
                          if (actions.isEmpty && routineItems.isEmpty && doneActions.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                              child: Row(
                                children: [
                                  Icon(
                                    isPast
                                        ? Icons.history
                                        : Icons.calendar_today_outlined,
                                    size: 14,
                                    color: cs.onSurface.withOpacity(.25),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isPast
                                        ? 'Rien de fait ce jour-là'
                                        : 'Rien de prévu — tape + pour ajouter',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withOpacity(.35),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            // ── Actions ──────────────────────────────────
                            if (actions.isNotEmpty || doneActions.isNotEmpty) ...[
                              if (actions.isNotEmpty)
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: actions.length,
                                  onReorder: (oldIndex, newIndex) {
                                    setState(() {
                                      widget.logic.reorderTodayBucket(
                                        yyyymmdd: ymd,
                                        bucketVisible: actions,
                                        oldIndex: oldIndex,
                                        newIndex: newIndex,
                                      );
                                    });
                                  },
                                  itemBuilder: (ctx, idx) {
                                    final it = actions[idx];
                                    final dColor = domainColor(
                                      (it.domainId ?? '').isNotEmpty
                                          ? it.domainId
                                          : widget.logic.state.activities
                                              .firstWhereOrNull((a) => a.id == it.activityId)
                                              ?.domainId,
                                      widget.logic.state.domains,
                                    );
                                    return Dismissible(
                                      key: ValueKey('week:${it.id}'),
                                      direction: DismissDirection.horizontal,
                                      background: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        color: Colors.green.withOpacity(.15),
                                        child: const Icon(Icons.check_circle_outline,
                                            color: Colors.green),
                                      ),
                                      secondaryBackground: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        color: Colors.red.withOpacity(.15),
                                        child: const Icon(Icons.delete, color: Colors.red),
                                      ),
                                      onDismissed: (direction) {
                                        HapticFeedback.lightImpact();
                                        if (direction == DismissDirection.startToEnd) {
                                          if (it.toPlan == true) {
                                            widget.logic.archiveAction(it);
                                          } else {
                                            widget.logic.completePlanItem(it, true);
                                          }
                                        } else {
                                          widget.logic.state.dayPlan
                                              .removeWhere((e) => e.id == it.id);
                                          widget.logic.onChange();
                                        }
                                        setState(() {});
                                      },
                                      child: ReorderableDragStartListener(
                                        index: idx,
                                        child: _ActionTile(
                                          action: it,
                                          isPast: isPast,
                                          cs: cs,
                                          domainColor: dColor,
                                          onToggle: () {
                                            HapticFeedback.lightImpact();
                                            if (it.toPlan == true && !it.done) {
                                              widget.logic.archiveAction(it);
                                              setState(() {});
                                            } else {
                                              widget.logic.completePlanItem(it, !it.done);
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              // ── Faites (accordéon) ───────────────────────
                              if (doneActions.isNotEmpty) ...[
                                if (actions.isNotEmpty)
                                  const Divider(height: 1, indent: 14, endIndent: 14),
                                InkWell(
                                  onTap: () => setState(() {
                                    if (_doneExpanded.contains(ymd)) {
                                      _doneExpanded.remove(ymd);
                                    } else {
                                      _doneExpanded.add(ymd);
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle,
                                            size: 13,
                                            color: cs.primary.withOpacity(.5)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Faites',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface.withOpacity(.4),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: cs.primary.withOpacity(.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '${doneActions.length}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          _doneExpanded.contains(ymd)
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 16,
                                          color: cs.onSurface.withOpacity(.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_doneExpanded.contains(ymd))
                                  ...doneActions.map((it) => _ActionTile(
                                        action: it,
                                        isPast: isPast,
                                        cs: cs,
                                        domainColor: domainColor(
                                          (it.domainId ?? '').isNotEmpty
                                              ? it.domainId
                                              : widget.logic.state.activities
                                                  .firstWhereOrNull(
                                                      (a) => a.id == it.activityId)
                                                  ?.domainId,
                                          widget.logic.state.domains,
                                        ),
                                        onToggle: () {
                                          widget.logic.completePlanItem(it, false);
                                          setState(() {});
                                        },
                                      )),
                              ],
                            ],

                            // ── Routines (accordéon) ──────────────────────
                            if (routineItems.isNotEmpty) ...[
                              if (actions.isNotEmpty)
                                const Divider(
                                    height: 1, indent: 14, endIndent: 14),
                              // Header accordéon
                              InkWell(
                                onTap: () => setState(() {
                                  if (_routinesExpanded.contains(ymd)) {
                                    _routinesExpanded.remove(ymd);
                                  } else {
                                    _routinesExpanded.add(ymd);
                                  }
                                }),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 8, 10, 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.repeat,
                                          size: 13,
                                          color:
                                              cs.onSurface.withOpacity(.35)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Routines',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurface.withOpacity(.4),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: routinesDone ==
                                                      routineItems.length &&
                                                  routineItems.isNotEmpty
                                              ? cs.primary.withOpacity(.12)
                                              : cs.onSurface.withOpacity(.07),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '$routinesDone/${routineItems.length}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: routinesDone ==
                                                        routineItems.length &&
                                                    routineItems.isNotEmpty
                                                ? cs.primary
                                                : cs.onSurface.withOpacity(.4),
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        _routinesExpanded.contains(ymd)
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 16,
                                        color: cs.onSurface.withOpacity(.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Contenu déplié
                              if (_routinesExpanded.contains(ymd)) ...[
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: routineItems.length,
                                  onReorder: (oldIndex, newIndex) {
                                    setState(() {
                                      widget.logic.reorderDailyRoutines(
                                          oldIndex, newIndex);
                                    });
                                  },
                                  itemBuilder: (ctx, idx) {
                                    final r = routineItems[idx];
                                    final value =
                                        widget.logic.habitValueOn(r.id, day);
                                    final target =
                                        widget.logic.effectiveHabitTarget(r);
                                    return ReorderableDelayedDragStartListener(
                                      key: ValueKey(r.id),
                                      index: idx,
                                      child: _RoutineTile(
                                        routine: r,
                                        value: value,
                                        target: target,
                                        isToday: isToday,
                                        cs: cs,
                                        domainColor: domainColor(r.domainId, widget.logic.state.domains),
                                        onTap: isToday
                                            ? () => showModalBottomSheet(
                                                  context: context,
                                                  showDragHandle: true,
                                                  isScrollControlled: true,
                                                  builder: (_) => RoutineDetailSheet(
                                                    logic: widget.logic,
                                                    st: widget.logic.state,
                                                    habitId: r.id,
                                                    day: DateTime.now(),
                                                  ),
                                                )
                                            : null,
                                        onIncrement: isToday
                                            ? () {
                                                HapticFeedback.lightImpact();
                                                widget.logic
                                                    .incHabitWithAssocEvent(
                                                        r.id, 1, day);
                                                widget.logic.onChange();
                                                setState(() {});
                                              }
                                            : null,
                                        onDecrement: (isToday && value > 0)
                                            ? () {
                                                HapticFeedback.lightImpact();
                                                widget.logic
                                                    .incHabitWithAssocEvent(
                                                        r.id, -1, day);
                                                widget.logic.onChange();
                                                setState(() {});
                                              }
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                              ],
                            ],
                          ],
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Tuile action ──────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final DayPlanItem action;
  final bool isPast;
  final ColorScheme cs;
  final VoidCallback onToggle;
  final Color? domainColor;

  const _ActionTile({
    required this.action,
    required this.isPast,
    required this.cs,
    required this.onToggle,
    this.domainColor,
  });

  @override
  Widget build(BuildContext context) {
    final dim = action.done;
    return InkWell(
      onTap: isPast ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            // Indicateur domaine
            if (domainColor != null) ...[
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: dim
                      ? domainColor!.withOpacity(.3)
                      : domainColor!.withOpacity(isPast ? .4 : .85),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(
              dim ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: dim
                  ? cs.primary
                  : isPast
                      ? cs.onSurface.withOpacity(.25)
                      : cs.onSurface.withOpacity(.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                action.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: dim
                      ? cs.onSurface.withOpacity(.4)
                      : cs.onSurface.withOpacity(isPast ? .5 : .9),
                  decoration: dim ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tuile routine ─────────────────────────────────────────────────────────────

class _RoutineTile extends StatelessWidget {
  final Activity routine;
  final int value;
  final int target;
  final bool isToday;
  final ColorScheme cs;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onTap;
  final Color? domainColor;

  const _RoutineTile({
    required this.routine,
    required this.value,
    required this.target,
    required this.isToday,
    required this.cs,
    this.onIncrement,
    this.onDecrement,
    this.onTap,
    this.domainColor,
  });

  @override
  Widget build(BuildContext context) {
    final reached = value >= target;
    final missed = value == 0 && !isToday;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          // Indicateur domaine
          if (domainColor != null) ...[
            Container(
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: reached
                    ? domainColor!.withOpacity(.3)
                    : missed
                        ? domainColor!.withOpacity(.2)
                        : domainColor!.withOpacity(.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            reached ? Icons.check_circle : Icons.repeat,
            size: 16,
            color: reached
                ? cs.primary
                : missed
                    ? cs.onSurface.withOpacity(.2)
                    : cs.onSurface.withOpacity(.4),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  routine.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: reached
                        ? cs.onSurface.withOpacity(.4)
                        : missed
                            ? cs.onSurface.withOpacity(.3)
                            : cs.onSurface.withOpacity(.85),
                    decoration: reached ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (_, constraints) {
                    final ratio = target > 0
                        ? (value / target).clamp(0.0, 1.0)
                        : 0.0;
                    final fillColor = reached
                        ? cs.primary
                        : value > 0
                            ? cs.primary.withOpacity(.45)
                            : cs.onSurface.withOpacity(.1);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 3,
                        width: constraints.maxWidth,
                        child: Stack(children: [
                          Container(
                            color: cs.onSurface.withOpacity(.08),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(color: fillColor),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (isToday) ...[
            // Bouton − (visible seulement si value > 0)
            if (value > 0)
              GestureDetector(
                onTap: onDecrement,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.remove,
                      size: 16, color: cs.onSurface.withOpacity(.35)),
                ),
              )
            else
              const SizedBox(width: 24),
            // Compteur
            SizedBox(
              width: 36,
              child: Text(
                target == 1
                    ? (reached ? '✓' : '—')
                    : '$value/$target',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: reached
                      ? cs.primary
                      : cs.onSurface.withOpacity(.5),
                ),
              ),
            ),
            // Bouton +
            GestureDetector(
              onTap: onIncrement,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.add,
                    size: 16, color: cs.onSurface.withOpacity(.5)),
              ),
            ),
          ] else ...[
            // Chip lecture seule
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: reached
                    ? cs.primary.withOpacity(.12)
                    : cs.onSurface.withOpacity(.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                missed
                    ? '—'
                    : target == 1
                        ? (reached ? '✓' : '$value/$target')
                        : '$value/$target',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: reached
                      ? cs.primary
                      : cs.onSurface.withOpacity(.4),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
