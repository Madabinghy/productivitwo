// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/new_action_sheet.dart';

class WeeklyView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;

  const WeeklyView({super.key, required this.logic, required this.state});

  @override
  State<WeeklyView> createState() => _WeeklyViewState();
}

class _WeeklyViewState extends State<WeeklyView> {
  late DateTime _weekStart;
  late Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _expanded = {yyyymmdd(today)};
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
          !it.archived)
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
                  final isExpanded = _expanded.contains(ymd);
                  final actions = _actionsFor(ymd);
                  final done = actions.where((a) => a.done).length;
                  final total = actions.length;

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
                          if (actions.isEmpty)
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
                          else
                            ...actions.map((it) => Dismissible(
                                  key: ValueKey('week:${it.id}'),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    color: Colors.red.withOpacity(.15),
                                    child: const Icon(Icons.delete, color: Colors.red),
                                  ),
                                  onDismissed: (_) {
                                    widget.logic.state.dayPlan
                                        .removeWhere((e) => e.id == it.id);
                                    widget.logic.onChange();
                                    setState(() {});
                                  },
                                  child: _ActionTile(
                                    action: it,
                                    isPast: isPast,
                                    cs: cs,
                                    onToggle: () {
                                      HapticFeedback.lightImpact();
                                      if (it.toPlan == true && !it.done) {
                                        widget.logic.archiveAction(it);
                                        setState(() {});
                                      } else {
                                        setState(() => it.done = !it.done);
                                        widget.logic.onChange();
                                      }
                                    },
                                  ),
                                )),
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

class _ActionTile extends StatelessWidget {
  final DayPlanItem action;
  final bool isPast;
  final ColorScheme cs;
  final VoidCallback onToggle;

  const _ActionTile({
    required this.action,
    required this.isPast,
    required this.cs,
    required this.onToggle,
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
