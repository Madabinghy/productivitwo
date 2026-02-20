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
  Future<void> Function()? onRename, // callback UI (optionnel)
}) async {
  return showModalBottomSheet<HabitSettingsResult>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      HabitFreq freq = act.habitFreq ?? HabitFreq.daily;
      int target = (act.habitTarget ?? 1);
      bool isAuto = act.autoTune && !act.manualTarget;

      if (target <= 0) target = 1;

      return StatefulBuilder(
        builder: (ctx, setSB) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onRename == null
                    ? null
                    : () async {
                        await onRename();
                        // on ne ferme pas le sheet: le nom se rafraîchit
                        setSB(() {});
                      },
                child: Text(
                  act.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration:
                        onRename == null ? TextDecoration.none : TextDecoration.underline,
                    decorationColor:
                        Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ---- Auto / Manuel
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

              // ---- Fréquence
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

              // ---- Cible
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
                      onPressed: () => Navigator.pop(
                        ctx,
                        HabitSettingsResult(
                          freq: freq,
                          target: target,
                          isAuto: isAuto,
                        ),
                      ),
                      child: const Text("Enregistrer"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}