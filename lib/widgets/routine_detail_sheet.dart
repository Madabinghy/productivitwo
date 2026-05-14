// ignore_for_file: deprecated_member_use

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/now_habit_tile_full.dart';

/// Ouvre le sheet unifié pour une routine (progression + réglages).
Future<void> showRoutineSheet(
  BuildContext context, {
  required AppLogic logic,
  required String habitId,
  required DateTime day,
  Future<void> Function(VoidCallback refresh)? onRename,
  VoidCallback? onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => RoutineDetailSheet(
      logic: logic,
      st: logic.state,
      habitId: habitId,
      day: day,
      onRename: onRename,
      onSaved: onSaved,
    ),
  );
}

class RoutineDetailSheet extends StatefulWidget {
  final AppLogic logic;
  final AppState st;
  final String habitId;
  final DateTime day;
  final Future<void> Function(VoidCallback refresh)? onRename;
  final VoidCallback? onSaved;

  const RoutineDetailSheet({
    super.key,
    required this.logic,
    required this.st,
    required this.habitId,
    required this.day,
    this.onRename,
    this.onSaved,
  });

  @override
  State<RoutineDetailSheet> createState() => _RoutineDetailSheetState();
}

class _RoutineDetailSheetState extends State<RoutineDetailSheet> {
  int _ringToken = 0;

  AppLogic get logic => widget.logic;
  AppState get st => widget.st;
  String get habitId => widget.habitId;

  Activity get act => st.activities.firstWhere((a) => a.id == habitId);

  void _applySetting() {
    logic.onChange();
    widget.onSaved?.call();
    setState(() {});
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: act.name);
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: act.name.length);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la routine'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => act.name = result);
    _applySetting();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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

    final currentStreak = logic.habitCurrentStreak(habitId);
    final bestStreak = logic.habitBestStreak(habitId);

    final dColor = domainColor(act.domainId, st.domains);
    final domain = st.domains.firstWhereOrNull((d) => d.id == act.domainId);

    // Réglages (état local miroir de act, appliqué immédiatement)
    final freq = act.habitFreq ?? HabitFreq.daily;
    final target = act.habitTarget ?? 1;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                if (dColor != null)
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: dColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        act.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (domain != null)
                        Text(
                          domain.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: dColor ?? cs.onSurface.withOpacity(.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _rename,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ── Tuile interactive ────────────────────────────────────────────
            NowHabitTileFull(
              logic: logic,
              st: st,
              habitId: habitId,
              day: today,
              ringToken: _ringToken,
              onRingBump: () => setState(() => _ringToken++),
            ),

            // ── Streak ──────────────────────────────────────────────────────
            if (currentStreak > 0 || bestStreak > 1) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (currentStreak > 0) ...[
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      '$currentStreak jour${currentStreak > 1 ? 's' : ''} d\'affilée',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                  const Spacer(),
                  if (bestStreak > 1)
                    Text(
                      'Record : $bestStreak j',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.45),
                      ),
                    ),
                ],
              ),
            ],

            // ── Paliers ──────────────────────────────────────────────────────
            if (logic.effectiveHabitFreq(act) == HabitFreq.daily) ...[
              const SizedBox(height: 10),
              Text(
                'Paliers',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.5),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  MapEntry(3, BadgeId.streak3),
                  MapEntry(7, BadgeId.streak7),
                  MapEntry(21, BadgeId.streak21),
                  MapEntry(66, BadgeId.streak66),
                  MapEntry(100, BadgeId.streak100),
                ].map<Widget>((e) {
                  final days = e.key;
                  final id = e.value;
                  final isEarned = logic.state.earnedBadges
                      .any((b) => b.id == id && b.habitId == habitId);
                  final meta = badgeMeta(id);
                  if (isEarned) {
                    return Chip(
                      backgroundColor: cs.primaryContainer,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text(
                        '${meta.emoji} ${meta.label}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    );
                  }
                  final progress = currentStreak.clamp(0, days);
                  return Chip(
                    backgroundColor:
                        cs.surfaceContainerHighest.withOpacity(.35),
                    side: BorderSide(color: cs.outlineVariant.withOpacity(.4)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    label: Text(
                      '${meta.emoji} $progress / ${days}j',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(.45),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Activité liée ────────────────────────────────────────────────
            if (hasLinked) ...[
              const SizedBox(height: 12),
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
            ],

            // ── Checklist ────────────────────────────────────────────────────
            if (checkItems.isNotEmpty) ...[
              const SizedBox(height: 12),
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

            // ── Réglages ─────────────────────────────────────────────────────
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Réglages',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withOpacity(.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),

            // Fréquence
            Row(
              children: [
                const Text('Fréquence',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                DropdownButton<HabitFreq>(
                  value: freq,
                  items: HabitFreq.values
                      .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(freqLabel(f)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    act.habitFreq = v;
                    _applySetting();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Cible
            Row(
              children: [
                const Text('Cible',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    act.habitTarget = (target - 1).clamp(1, 999);
                    _applySetting();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$target',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  onPressed: () {
                    act.habitTarget = (target + 1).clamp(1, 999);
                    _applySetting();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
