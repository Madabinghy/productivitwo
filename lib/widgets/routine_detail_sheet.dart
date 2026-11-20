// ignore_for_file: deprecated_member_use

import 'package:productivitwo_v1/utils/duration_fmt.dart' show pickDurationMin;
import 'package:productivitwo_v1/widgets/freeze_sheet.dart';
import 'package:productivitwo_v1/widgets/gains_section.dart';
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/widgets/badge_lines.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/auto_target.dart';
import 'package:productivitwo_v1/utils/progression.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart' show chronoHitMin;
import 'package:productivitwo_v1/utils/routine_context.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart' show momentOf, pickedMomentsOf, splitMomentsOf, toggleMoment;
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
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
  await showFiche<void>(
    context,
    builder: (_, scroll) => RoutineDetailSheet(
      scroll: scroll,
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
  final ScrollController? scroll;

  const RoutineDetailSheet({
    super.key,
    this.scroll,
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
    if (await pickLinkedActivity(context, st: st, act: act)) _applySetting();
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

  // Saisie d'une étape de checklist (ajout / renommage).
  Future<String?> _promptChecklistText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: initial.length);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Décris l\'étape…'),
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
    final v = result?.trim();
    return (v == null || v.isEmpty) ? null : v;
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
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                      ScaffoldMessenger.of(context).showClosingSnackBar(
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
            // Cible, durée et gel en tête (retour user 2026-11-02 : cachés dans les réglages). La durée d'une fois
            // est le SEUL réglage de temps (2026-11-19) : le ⏱ de la ligne et, si le chrono coche, une coche.
            Wrap(spacing: 8, runSpacing: 6, children: [
              ActionChip(
                avatar: const Icon(Icons.flag_outlined, size: 16),
                label: Text('Cible · ${act.habitTarget ?? 1} ${switch (logic.effectiveHabitFreq(act)) { HabitFreq.weekly => '/ sem.', HabitFreq.monthly => '/ mois', _ => '/ jour' }}'),
                onPressed: () async {
                  final v = await _pickCount(context, act.habitTarget ?? 1);
                  if (v == null) return;
                  logic.setRoutineTarget(act, v);
                  _applySetting();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16),
                key: const ValueKey('routine-once-min'),
                label: Text(act.onceMin != null ? 'Durée · ${act.onceMin} min' : 'Durée'),
                onPressed: _pickOnceMin,
              ),
              FreezeChip(logic: logic, activity: act, onChanged: () => setState(() {})),
            ]),
            const SizedBox(height: 8),

            // ── Tuile interactive ────────────────────────────────────────────
            NowHabitTileFull(
              logic: logic,
              st: st,
              habitId: habitId,
              day: today,
              ringToken: _ringToken,
              onRingBump: () => setState(() => _ringToken++),
            ),

            // ── Série et paliers (badges, lot 3) ───────────────────────────
            // Routine quotidienne : la ligne de paliers du système de badges
            // (série en cours, record, chevrons 3 / 7 / 21 / 66 / 100, élan).
            if (logic.effectiveHabitFreq(act) == HabitFreq.daily) ...[
              const SizedBox(height: 10),
              RoutineTiersLine(
                activity: act,
                hits: logic.state.habitHits,
                marks: logic.state.moodMarks,
                dayStartMin: logic.dayStartMin,
                accent: accentColor,
                bridged: logic.bridgedOf(act.id),
                frozen: logic.frozenOf(act.id),
              ),
              const SizedBox(height: 4),
            ],
            // Ce que la routine fait avancer : sa série et son compteur, avec leurs jauges.
            GainsSection(
              activityId: act.id,
              time: false,
              state: logic.state,
              title: (c) => Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text('CE QUE ÇA FAIT AVANCER',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Theme.of(c).colorScheme.onSurface.withValues(alpha: .55))),
              ),
            ),
            if (logic.effectiveHabitFreq(act) == HabitFreq.daily) ...[
              // Routine acquise (2026-10-30) : hors journée parfaite et enjeux, toujours dans le contrat.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: logic.acquired.containsKey(act.id),
                title: const Text('Routine acquise'),
                subtitle: const Text('Hors journée parfaite et enjeux · reste cochable et compte dans ton objectif'),
                onChanged: (v) async {
                  if (v) {
                    await logic.acquireRoutine(act.id);
                  } else {
                    await logic.releaseRoutine(act.id);
                  }
                  setState(() {});
                },
              ),
            ] else ...[
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
              // Une seule durée (2026-11-19) : le chrono de l'activité liée coche à la durée d'une fois.
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                key: const ValueKey('routine-chrono-hits'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: chronoHitMin(act, logic.state.activities) != null,
                title: Text('Le chrono de « ${linkedAct.name} » coche tout seul', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(_chronoHitsHint(linkedAct),
                    key: const ValueKey('routine-chrono-hits-hint'),
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.5))),
                onChanged: _setChronoHits,
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                act.onceMin != null
                    ? 'Le ⏱ lance un décompte de ${act.onceMin} min et coche la routine à la fin. Lie une activité temps pour que ce temps soit compté quelque part.'
                    : 'Règle une durée (en haut) pour lancer la routine au minuteur. Lie une activité temps pour que ce temps soit compté quelque part.',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.45)),
              ),
            ],

            // ── Checklist ────────────────────────────────────────────────────
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
                    child: Row(
                      children: [
                        Text('Checklist',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        if (checkItems.isNotEmpty)
                          Text(
                            '${doneSet.length} / ${checkItems.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.55),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'Ajouter une étape',
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            final label = await _promptChecklistText(
                                'Nouvelle étape', '');
                            if (label == null) return;
                            logic.addChecklistItem(habitId, label);
                            logic.onChange();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  if (checkItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Aucune étape — touche + pour en ajouter une.',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.45)),
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < checkItems.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 14,
                            color: cs.onSurface.withOpacity(.07)),
                      CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.only(left: 14, right: 4),
                        value: doneSet.contains(i),
                        title: Text(
                          checkItems[i],
                          style: TextStyle(
                            decoration: doneSet.contains(i)
                                ? TextDecoration.lineThrough
                                : null,
                            color: doneSet.contains(i)
                                ? cs.onSurface.withOpacity(.45)
                                : null,
                          ),
                        ),
                        secondary: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert,
                              size: 18, color: cs.onSurface.withOpacity(.5)),
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final label = await _promptChecklistText(
                                  'Renommer l\'étape', checkItems[i]);
                              if (label == null) return;
                              logic.renameChecklistItem(habitId, i, label);
                              logic.onChange();
                              setState(() {});
                            } else if (v == 'delete') {
                              logic.removeChecklistItemAndFixDone(
                                  habitId, today, i);
                              logic.onChange();
                              setState(() {});
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'rename', child: Text('Renommer')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Supprimer')),
                          ],
                        ),
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
                          logic.setRoutineTarget(act, target - 1);
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
                          logic.setRoutineTarget(act, target + 1);
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

            // Progression par paliers : cap déclaré, la cible devient le
            // palier courant — évalué chaque lundi sur les hits réels.
            if (freq == HabitFreq.daily) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Objectif final (cap)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(.75),
                      )),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _askFinalTarget(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        act.finalTarget?.toString() ?? '—',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: act.finalTarget != null
                              ? accentColor
                              : cs.onSurface.withOpacity(.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (act.finalTarget != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${palierLabel(act)} · évalué chaque lundi : '
                    'tenu ≥ 5 j/7 → palier suivant, ≤ 1 j/7 → on redescend.',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(.55)),
                  ),
                ),
            ],

            // Cible automatique (2026-11-20) : elle suit ce qui est vraiment fait. Pas avec un cap (les paliers
            // la pilotent déjà).
            if (freq == HabitFreq.daily && act.finalTarget == null) ...[
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                key: const ValueKey('routine-auto-target'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: act.autoTarget,
                activeColor: accentColor,
                title: Text('Cible automatique',
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(.75))),
                subtitle: Text(
                  act.autoTarget
                      ? 'Tu fais 120 % sur 7 jours : un cran de plus. Moins de 50 % : un cran de moins. '
                          'Une fois par semaine au plus, et une hausse ne casse jamais ta série.'
                          '${lastTargetChangeLabel(act) == null ? '' : '\nDernier changement : ${lastTargetChangeLabel(act)}'}'
                      : 'La cible suit ce que tu fais vraiment : elle monte quand tu la dépasses, redescend si elle est trop haute.',
                  key: const ValueKey('routine-auto-target-hint'),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55)),
                ),
                onChanged: (v) {
                  act.autoTarget = v;
                  _applySetting();
                },
              ),
            ],

            // Rythme (2026-11-19) : chaque jour · rattrapable (un jour raté se rattrape dans les 7 jours,
            // sans avance) · sur 7 jours (rattrapage et avance).
            if (act.habitFreq == HabitFreq.daily) ...[
              const SizedBox(height: 14),
              Text('Rythme',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(.75),
                  )),
              const SizedBox(height: 4),
              Text(
                  act.rolling
                      ? 'Ce que tu fais en plus rattrape d\'abord un jour raté, puis te couvre les jours suivants, 7 jours au plus.'
                      : act.catchUp
                          ? 'Un jour raté se rattrape dans les 7 jours en faisant plus un autre jour : la série recolle. Pas d\'avance sur demain.'
                          : 'La cible se refait chaque jour : un jour raté reste raté, ce que tu fais en plus ne compte pas demain.',
                  key: const ValueKey('routine-rhythm-hint'),
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  key: const ValueKey('routine-rhythm-daily'),
                  label: const Text('Chaque jour'),
                  selected: !act.rolling && !act.catchUp,
                  onSelected: (_) => _setRhythm(rolling: false, catchUp: false),
                ),
                ChoiceChip(
                  key: const ValueKey('routine-rhythm-catchup'),
                  label: const Text('Rattrapable'),
                  selected: !act.rolling && act.catchUp,
                  onSelected: (_) => _setRhythm(rolling: false, catchUp: true),
                ),
                ChoiceChip(
                  key: const ValueKey('routine-rhythm-rolling'),
                  label: const Text('Sur 7 jours'),
                  selected: act.rolling,
                  onSelected: (_) => _setRhythm(rolling: true, catchUp: false),
                ),
              ]),
            ],

            // Moments (2026-10-30, fusion « Contexte horaire » + « Répartir ») :
            // un moment = la fenêtre naturelle de la routine ; plusieurs (routine
            // quotidienne) = la cible du jour se partage entre eux. Auto,
            // Toute la journée et Libre sont exclusifs.
            const SizedBox(height: 14),
            Text('Moments',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(.75),
                )),
            const SizedBox(height: 4),
            Text(_momentsHint(),
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.55))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: Text(() {
                  final arch = routineArchetype(act.name);
                  final derived = arch != null ? kTimeContexts[arch.contextKey] : null;
                  return derived != null ? 'Auto · ${derived.label}' : 'Auto';
                }()),
                selected: act.timeContext == null && act.splitMoments.length < 2,
                onSelected: (_) => _setMoments(null, const []),
              ),
              for (final m in logic.moments)
                FilterChip(
                  label: Text(m.label),
                  selected: pickedMomentsOf(act).contains(m.key),
                  onSelected: (_) => _toggleMoment(m.key),
                ),
              ChoiceChip(
                label: const Text('Toute la journée'),
                selected: act.splitMoments.length < 2 && (act.timeContext == 'allday' || act.timeContext == 'day'),
                onSelected: (_) => _setMoments('allday', const []),
              ),
              ChoiceChip(
                label: const Text('Libre'),
                selected: act.splitMoments.length < 2 && act.timeContext == 'any',
                onSelected: (_) => _setMoments('any', const []),
              ),
            ]),

            // Contextes GTD (@maison…) : où la routine est réalisable —
            // filtre « je suis » de Maintenant + CTA d'enchaînement
            // (« tu viens de finir X @maison — Y l'est aussi »).
            const SizedBox(height: 14),
            Text('Contextes (@)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(.75),
                )),
            const SizedBox(height: 8),
            ContextPicker(
              values: act.contexts,
              sync: FirestoreSync(),
              onValuesChanged: (list) {
                act.contexts = List.of(list);
                _applySetting();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Ce que dit l'interrupteur « le chrono coche tout seul » : réglé à la main, allumé d'office (seule routine
  /// de son activité), éteint, ou plusieurs routines sur la même activité (la question à l'arrêt du chrono).
  String _chronoHitsHint(Activity linked) {
    final per = chronoHitMin(act, logic.state.activities);
    if (per != null) {
      final auto = (act.minPerHit ?? 0) <= 0;
      return '${auto ? 'Allumé d\'office : c\'est la seule routine liée à « ${linked.name} ». ' : ''}'
          '$per min = 1 fois · ${per * 2} min = 2 fois, en plus de ce que tu coches à la main.';
    }
    if (act.onceMin == null) return 'Règle d\'abord la durée d\'une fois.';
    final shared = logic.state.activities.where((x) => x.isHabit && !x.deleted && x.linkedActivityId == linked.id).length > 1;
    if (shared && !act.chronoOff) {
      return 'Plusieurs routines sont liées à « ${linked.name} » : à l\'arrêt du chrono, l\'app te demande pour laquelle c\'était.';
    }
    return 'Éteint : le ⏱ de ${act.onceMin} min coche la routine à la fin, le chrono seul ne coche rien.';
  }

  /// La durée d'une fois : le ⏱ de la ligne et, si le chrono coche, le temps d'une coche.
  Future<void> _pickOnceMin() async {
    final v = await pickDurationMin(context, initial: act.onceMin ?? 0, title: 'Durée d\'une fois', allowZero: true);
    if (v == null || !mounted) return;
    act.setOnceMin(v);
    _applySetting();
    if (chronoHitMin(act, logic.state.activities) != null) logic.checkTimeHits();
  }

  Future<void> _setChronoHits(bool on) async {
    if (on && act.onceMin == null) {
      final v = await pickDurationMin(context, initial: 10, title: 'Durée d\'une fois');
      if (v == null || v <= 0 || !mounted) return;
      act.setOnceMin(v);
    }
    act.setChronoHits(on);
    _applySetting();
    if (on) logic.checkTimeHits();
  }

  void _setRhythm({required bool rolling, required bool catchUp}) {
    if (act.rolling == rolling && act.catchUp == catchUp) return;
    act.rolling = rolling;
    act.catchUp = catchUp;
    _applySetting();
  }

  void _setMoments(String? timeContext, List<String> split) {
    act.timeContext = timeContext;
    act.splitMoments = split;
    _applySetting();
  }

  void _toggleMoment(String key) {
    final r = toggleMoment(act, key);
    _setMoments(r.timeContext, r.split);
  }

  /// Ce que donnent les moments cochés : « 10 ce matin · 10 ce soir », la
  /// fenêtre d'un seul moment, ou l'aide.
  String _momentsHint() {
    final keys = splitMomentsOf(act);
    if (keys.isNotEmpty) {
      final n = logic.activeHabitTarget(act);
      final base = n ~/ keys.length, extra = n % keys.length;
      return 'Répartie : ${[
        for (var i = 0; i < keys.length; i++)
          if (base + (i < extra ? 1 : 0) > 0) '${base + (i < extra ? 1 : 0)} ${momentOf(keys[i]).thisOne}',
      ].join(' · ')}';
    }
    final picked = pickedMomentsOf(act);
    final daily = act.habitFreq == HabitFreq.daily;
    if (picked.length == 1) {
      return 'À faire ${momentOf(picked.first).thisOne}${daily ? ' · touche un autre moment pour la répartir' : ''}';
    }
    return switch (act.timeContext) {
      'allday' || 'day' => 'Disponible toute la journée, sans découpage.',
      'any' => 'Sans moment : à faire quand tu veux.',
      _ => daily ? 'Touche un moment pour la placer, plusieurs pour la répartir.' : 'Touche un moment pour la placer.',
    };
  }

  /// Cap de progression : saisie libre (vider = retirer la progression, la
  /// cible du jour redevient fixe).
  Future<void> _askFinalTarget(BuildContext context) async {
    final ctrl =
        TextEditingController(text: act.finalTarget?.toString() ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objectif final'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ex : 50 (vide = pas de progression)',
          ),
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
    if (res == null) return;
    final v = int.tryParse(res);
    act.finalTarget = (v != null && v > 0) ? v : null;
    // Nouveau cap = nouveau départ : la prochaine évaluation attend une
    // semaine pleine (le fait `stepUpdatedWeek` repart de cette semaine).
    act.stepUpdatedWeek = null;
    _applySetting();
  }
}

/// Sélecteur « Activité liée » d'une routine (fiche routine, segment Routines
/// d'Aujourd'hui) : activités temps du même domaine d'abord, sinon toutes ;
/// « Aucune » délie. Mute `act.linkedActivityId` et retourne true si choisi
/// (à l'appelant de propager : `logic.onChange()`).
Future<bool> pickLinkedActivity(BuildContext context, {required AppState st, required Activity act}) async {
  final acts = st.activities
      .where((a) => !a.isHabit && !a.deleted && a.role != ActivityRole.shopping)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final currentId = (act.linkedActivityId ?? '').trim();
  final picked = await showActivityPicker(context,
      activities: acts,
      domains: st.activeDomains,
      title: 'Activité liée',
      selectedId: currentId,
      preferDomainId: act.domainId,
      extras: [ActivityPickerExtra('__none__', 'Aucune', selected: currentId.isEmpty)]);
  if (picked == null) return false; // sheet fermé sans choix
  act.linkedActivityId = picked == '__none__' ? null : picked;
  // Le minuteur survit au déliage : sans activité liée, le décompte tourne
  // sur la routine elle-même (micro-routines).
  return true;
}

/// Cible d'une routine : − n + (1 à 999).
Future<int?> _pickCount(BuildContext context, int initial) {
  var v = initial < 1 ? 1 : initial;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Cible par période'),
        content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: v > 1 ? () => set(() => v--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('$v', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
          IconButton(onPressed: v < 999 ? () => set(() => v++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, v), child: const Text('OK')),
        ],
      ),
    ),
  );
}
