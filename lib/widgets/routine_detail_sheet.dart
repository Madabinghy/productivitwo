// ignore_for_file: deprecated_member_use

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/now_habit_tile_full.dart';

class RoutineDetailSheet extends StatefulWidget {
  final AppLogic logic;
  final AppState st;
  final String habitId;
  final DateTime day;

  const RoutineDetailSheet({
    super.key,
    required this.logic,
    required this.st,
    required this.habitId,
    required this.day,
  });

  @override
  State<RoutineDetailSheet> createState() => _RoutineDetailSheetState();
}

class _RoutineDetailSheetState extends State<RoutineDetailSheet> {
  int _ringToken = 0;

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic;
    final st = widget.st;
    final habitId = widget.habitId;
    final today = DateTime(widget.day.year, widget.day.month, widget.day.day);

    final act = st.activities.firstWhere((a) => a.id == habitId);

    final linkedId = (act.linkedActivityId ?? '').trim();
    final linkedAct = linkedId.isEmpty
        ? null
        : st.activities.firstWhereOrNull((a) => a.id == linkedId);

    final hasLinked = linkedAct != null;
    final running = logic.runningActivity();
    final isRunningThis =
        hasLinked && running != null && running.id == linkedAct.id;

    final checkItems = logic.checklistForHabit(habitId);
    final doneSet = logic.checklistDoneSet(habitId, today);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    act.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            NowHabitTileFull(
              logic: logic,
              st: st,
              habitId: habitId,
              day: today,
              ringToken: _ringToken,
              onRingBump: () => setState(() => _ringToken++),
            ),

            const SizedBox(height: 12),

            if (hasLinked)
              FilledButton.icon(
                icon: Icon(
                  isRunningThis ? Icons.stop : Icons.play_arrow,
                  size: 20,
                ),
                label: Text(
                  isRunningThis ? 'Stop' : linkedAct.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: isRunningThis
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.85),
                        foregroundColor: Colors.white,
                      )
                    : null,
                onPressed: () {
                  if (isRunningThis) {
                    logic.stopActive();
                  } else {
                    if (running != null) logic.stopActive();
                    logic.start(linkedAct.id);
                    logic.rev.value++;
                  }
                  logic.onChange();
                  setState(() {});
                },
              ),

            if (hasLinked) const SizedBox(height: 16),

            if (checkItems.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Checklist',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${doneSet.length} / ${checkItems.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      for (int i = 0; i < checkItems.length; i++)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: doneSet.contains(i),
                          title: Text(checkItems[i]),
                          onChanged: (_) {
                            logic.toggleChecklistItem(habitId, today, i);
                            logic.onChange();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
