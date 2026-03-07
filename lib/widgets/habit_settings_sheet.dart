import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';


class HabitSettingsResult {
  final HabitFreq freq;
  final int target;
  final bool isAuto;
  HabitSettingsResult({
    required this.freq,
    required this.target,
    required this.isAuto,
  });
}

String freqLabel(HabitFreq f) {
  switch (f) {
    case HabitFreq.daily:
      return "Quotidienne";
    case HabitFreq.weekly:
      return "Hebdomadaire";
    case HabitFreq.monthly:
      return "Mensuelle";
  }
}



Future<HabitSettingsResult?> showHabitSettingsSheet(
  BuildContext context, {
  required Activity act,
  Future<void> Function(VoidCallback refresh)? onRename, // ✅ refresh hook
  VoidCallback? onSaved, // ✅ pour le parent sheet (Dashboard)
  bool applyDirectly = true, // ✅ par défaut on mute act (simple)
}) async {
  final res = await showModalBottomSheet<HabitSettingsResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      HabitFreq freq = act.habitFreq ?? HabitFreq.daily;
      int target = (act.habitTarget ?? 1);
      bool isAuto = act.autoTune && !act.manualTarget;

      if (target <= 0) target = 1;

      return StatefulBuilder(
        builder: (ctx, setSB) {
          void refresh() => setSB(() {});

          void applyToAct() {
            act.habitFreq = freq;
            act.habitTarget = target;

            if (isAuto) {
              act.manualTarget = false;
              act.autoTune = true;
            } else {
              act.autoTune = false;
              act.manualTarget = true;
              if ((act.habitTarget ?? 0) <= 0) act.habitTarget = 1;
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    if (onRename == null) return;
                    await onRename(refresh);
                    refresh();
                  },
                  child: Text(
                    act.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor:
                          Theme.of(ctx).colorScheme.primary.withOpacity(0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    const Text("Mode",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    ChoiceChip(
                      label: const Text("Auto"),
                      selected: isAuto,
                      onSelected: (_) => setSB(() => isAuto = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text("Manuel"),
                      selected: !isAuto,
                      onSelected: (_) => setSB(() => isAuto = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    const Text("Fréquence",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    DropdownButton<HabitFreq>(
                      value: freq,
                      items: HabitFreq.values
                          .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(freqLabel(f)),
                              ))
                          .toList(),
                      onChanged: (v) => setSB(() {
                        if (v == null) return;
                        freq = v;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    const Text("Cible",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          setSB(() => target = (target - 1).clamp(1, 999)),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text("$target",
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      onPressed: () =>
                          setSB(() => target = (target + 1).clamp(1, 999)),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Annuler"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          // on ferme en renvoyant le résultat
                          Navigator.pop(
                            ctx,
                            HabitSettingsResult(
                              freq: freq,
                              target: target,
                              isAuto: isAuto,
                            ),
                          );
                        },
                        child: const Text("Enregistrer"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (res == null) return null;

  // ✅ option 1 (recommandé): appliquer ici => tout le monde bénéficie
  if (applyDirectly) {
    act.habitFreq = res.freq;
    act.habitTarget = res.target;

    if (res.isAuto) {
      act.manualTarget = false;
      act.autoTune = true;
    } else {
      act.autoTune = false;
      act.manualTarget = true;
      if ((act.habitTarget ?? 0) <= 0) act.habitTarget = 1;
    }
  }

  // ✅ si appel depuis un sheet parent => refresh parent
  onSaved?.call();

  return res;
}


class RoutineCatchupSummary {
  final int achieved;
  final int remaining;

  const RoutineCatchupSummary({
    required this.achieved,
    required this.remaining,
  });

  int get total => achieved + remaining;

  double get progress {
    if (total == 0) return 0;
    return achieved / total;
  }

  bool get allDone => remaining == 0 && total > 0;
}


class RoutineCatchupChip extends StatelessWidget {
  final RoutineCatchupSummary summary;
  final VoidCallback? onTap;

  const RoutineCatchupChip({
    super.key,
    required this.summary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: cs.surfaceContainerHighest,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.emoji_events_rounded,
              size: 16,
              color: summary.allDone ? cs.primary : cs.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              '${summary.achieved} / ${summary.remaining}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: LinearProgressIndicator(
                value: summary.progress,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}