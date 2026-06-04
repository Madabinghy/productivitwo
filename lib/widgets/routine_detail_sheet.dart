// ignore_for_file: deprecated_member_use

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/icon_picker_sheet.dart';
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

  /// Lier / changer / délier l'activité temps de la routine. « Aucune » délie.
  Future<void> _pickLinkedActivity() async {
    final acts = st.activities
        .where((a) =>
            !a.isHabit && !a.deleted && a.role != ActivityRole.shopping)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final sameDomain = acts.where((a) => a.domainId == act.domainId).toList();
    final list = sameDomain.isNotEmpty ? sameDomain : acts;
    final currentId = (act.linkedActivityId ?? '').trim();

    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Activité liée',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Aucune'),
              trailing:
                  currentId.isEmpty ? const Icon(Icons.check, size: 18) : null,
              onTap: () => Navigator.pop(ctx, '__none__'),
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Aucune activité temps disponible.',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            for (final a in list)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(a.name),
                trailing:
                    currentId == a.id ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.pop(ctx, a.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return; // sheet fermé sans choix
    act.linkedActivityId = picked == '__none__' ? null : picked;
    // Délier ⇒ plus de minuteur possible (minuteur ⇒ activité liée).
    if (act.linkedActivityId == null) act.timerMin = null;
    _applySetting();
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

    final accentColor = dColor ?? cs.primary;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 9, height: 9,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: accentColor, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(act.name,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (domain != null)
                        Text(domain.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            )),
                    ],
                  ),
                ),
                IconButton(
                  icon: act.iconCode != null
                      ? Icon(IconData(act.iconCode!, fontFamily: 'MaterialIcons'),
                          size: 18, color: accentColor)
                      : const Icon(Icons.emoji_emotions_outlined, size: 18),
                  tooltip: 'Choisir une icône',
                  onPressed: () async {
                    final picked = await showIconPickerSheet(context, current: act.iconCode);
                    if (picked == null) return;
                    setState(() => act.iconCode = picked == -1 ? null : picked);
                    widget.logic.onChange();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: _rename,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Supprimer',
                  onPressed: () async {
                    final name = act.name;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Text('Supprimer « $name » ?'),
                        content: const Text(
                            'Cette routine sera supprimée et retirée des plans.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('Annuler')),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('Supprimer')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    logic.deleteActivityCascade(act.id);
                    widget.onSaved?.call();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Supprimé : $name')));
                      Navigator.pop(context);
                    }
                  },
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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentColor.withOpacity(.15)),
                ),
                child: Row(
                  children: [
                    if (currentStreak > 0) ...[
                      const Text('🔥', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SÉRIE',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: cs.onSurface.withOpacity(.4),
                            ),
                          ),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '$currentStreak',
                                  style: TextStyle(
                                    fontSize: 26, fontWeight: FontWeight.w900,
                                    color: accentColor, height: 1.0,
                                  ),
                                ),
                                TextSpan(
                                  text: '  jour${currentStreak > 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withOpacity(.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    if (bestStreak > 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('RECORD',
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: cs.onSurface.withOpacity(.35),
                              )),
                          Text('$bestStreak j',
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800,
                                color: cs.onSurface.withOpacity(.55),
                              )),
                        ],
                      ),
                  ],
                ),
              ),
            ],

            // ── Paliers ──────────────────────────────────────────────────────
            if (logic.effectiveHabitFreq(act) == HabitFreq.daily) ...[
              const SizedBox(height: 12),
              Text(
                'PALIERS',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: cs.onSurface.withOpacity(.35),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
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
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accentColor.withOpacity(.3)),
                      ),
                      child: Text(
                        '${meta.emoji} ${meta.label}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12,
                          color: accentColor,
                        ),
                      ),
                    );
                  }
                  final progress = currentStreak.clamp(0, days);
                  final pct = progress / days;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.onSurface.withOpacity(.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${meta.emoji}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text(
                          '${days}j',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: cs.onSurface.withOpacity(pct >= 0.5 ? .7 : .4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 32,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor: cs.onSurface.withOpacity(.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  accentColor.withOpacity(.6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Activité liée ────────────────────────────────────────────────
            const SizedBox(height: 16),
            Row(
              children: [
                Text('ACTIVITÉ LIÉE',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 1.2, color: cs.onSurface.withOpacity(.4))),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: Icon(hasLinked ? Icons.swap_horiz : Icons.add_link, size: 16),
                  label: Text(hasLinked ? 'Changer' : 'Lier'),
                  onPressed: _pickLinkedActivity,
                ),
              ],
            ),
            if (hasLinked) ...[
              const SizedBox(height: 4),
              FilledButton.icon(
                icon: Icon(isRunningThis ? Icons.stop : Icons.play_arrow, size: 20),
                label: Text(
                  isRunningThis ? 'Stop' : linkedAct.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                style: isRunningThis
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.85),
                        foregroundColor: Colors.white,
                      )
                    : FilledButton.styleFrom(backgroundColor: accentColor),
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
              const SizedBox(height: 12),
              Text('MINUTEUR PAR DÉFAUT',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 1.1, color: cs.onSurface.withOpacity(.4))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: [
                  for (final m in const [0, 5, 10, 15, 25])
                    ChoiceChip(
                      label: Text(m == 0 ? 'Aucun' : '$m min'),
                      selected: (act.timerMin ?? 0) == m,
                      onSelected: (_) {
                        act.timerMin = m == 0 ? null : m;
                        _applySetting();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Lancée depuis le FAB, la routine démarrera « ${linkedAct.name} » '
                'pour cette durée et se cochera à la fin.',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45)),
              ),
            ] else ...[
              const SizedBox(height: 2),
              Text(
                'Lie une activité temps pour chronométrer cette routine (le temps sera loggué dessus).',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45)),
              ),
            ],

            // ── Checklist ────────────────────────────────────────────────────
            if (checkItems.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(
                        children: [
                          Text('Checklist',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(
                            '${doneSet.length} / ${checkItems.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (int i = 0; i < checkItems.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 14,
                            color: cs.onSurface.withOpacity(.07)),
                      CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        value: doneSet.contains(i),
                        title: Text(checkItems[i]),
                        onChanged: (_) {
                          logic.toggleChecklistItem(habitId, today, i);
                          logic.onChange();
                          setState(() {});
                        },
                      ),
                    ],
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],

            // ── Réglages ─────────────────────────────────────────────────────
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Text(
              'RÉGLAGES',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: cs.onSurface.withOpacity(.35),
              ),
            ),
            const SizedBox(height: 14),

            // Fréquence — chips segmentées
            Row(
              children: HabitFreq.values.map((f) {
                final selected = freq == f;
                return Expanded(
                  child: GestureDetector(
                    onTap: () { act.habitFreq = f; _applySetting(); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(
                        left: f == HabitFreq.values.first ? 0 : 4,
                        right: f == HabitFreq.values.last ? 0 : 4,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? accentColor
                            : accentColor.withOpacity(.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? Colors.transparent
                              : accentColor.withOpacity(.18),
                        ),
                      ),
                      child: Text(
                        freqLabel(f),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : accentColor.withOpacity(.8),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Cible — stepper stylisé
            Row(
              children: [
                Text('Cible par période',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(.75),
                    )),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          act.habitTarget = (target - 1).clamp(1, 999);
                          _applySetting();
                        },
                        icon: const Icon(Icons.remove_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '$target',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: accentColor,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          act.habitTarget = (target + 1).clamp(1, 999);
                          _applySetting();
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
