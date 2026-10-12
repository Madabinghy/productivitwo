import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';

const kDurationPresets = [15, 30, 45, 60, 90, 120, 180, 240];

/// Pas du − / + : 5 min sous l'heure, 15 min au-delà.
int durationStepUp(int? v) {
  if (v == null) return 15;
  return v < 60 ? v + 5 : v + 15;
}

int? durationStepDown(int? v, {int min = 5}) {
  if (v == null || v <= min) return null;
  final next = v <= 60 ? v - 5 : v - 15;
  return next < min ? min : next;
}

/// Sélecteur de durée web (remplace la saisie des minutes au clavier) :
/// − valeur + et durées toutes faites. [allowNone] = « Aucune » possible
/// (estimation facultative). Couleurs du thème ambiant.
class DurationChooser extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool allowNone;
  final String noneLabel;
  final int max;

  const DurationChooser({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
    this.noneLabel = 'Aucune',
    this.max = 12 * 60,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value;
    final down = durationStepDown(v);
    final up = durationStepUp(v);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Moins',
          onPressed: down == null && !(allowNone && v != null) ? null : () => onChanged(down),
          icon: const Icon(Icons.remove_rounded, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 72,
          child: Text(v == null ? noneLabel : fmtMin(v),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: v == null ? cs.onSurface.withOpacity(.5) : cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        IconButton(
          tooltip: 'Plus',
          onPressed: up > max ? null : () => onChanged(up),
          icon: const Icon(Icons.add_rounded, size: 18),
          visualDensity: VisualDensity.compact,
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (allowNone)
          ChoiceChip(
            label: Text(noneLabel),
            selected: v == null,
            onSelected: (_) => onChanged(null),
            visualDensity: VisualDensity.compact,
          ),
        for (final p in kDurationPresets.where((p) => p <= max))
          ChoiceChip(
            label: Text(fmtMin(p)),
            selected: v == p,
            onSelected: (_) => onChanged(p),
            visualDensity: VisualDensity.compact,
          ),
      ]),
    ]);
  }
}
