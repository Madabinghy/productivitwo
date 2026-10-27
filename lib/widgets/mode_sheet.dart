import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/widgets/now_card.dart' show NowPalette;

/// Feuille « Mode du jour » (lot 1 Modes et coups) : trois postures, pas cinq.
/// Poser un mode ÉCRIT un pointage d'élan (zéro double saisie) ; il expire à
/// la bascule de journée vécue.
Future<void> showModeSheet(BuildContext context, AppLogic logic) {
  final cur = logic.mode;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final cs = Theme.of(c).colorScheme;
      final dark = cs.brightness == Brightness.dark;
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Mode du jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Une posture, changeable à tout moment. Elle pointe ton élan et repart en Normal demain.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
          ),
          for (final m in DayMode.values)
            ListTile(
              leading: Icon(modeIcon(m), color: modeChipColor(m, dark: dark)),
              title: Text(kModeLabels[m]!, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(modeDescription(m)),
              trailing: m == cur ? Icon(Icons.check_rounded, color: modeChipColor(m, dark: dark)) : null,
              onTap: () {
                Navigator.pop(c);
                if (m != cur) logic.setMode(m);
              },
            ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

/// Pilule « Mode · Flemme ▾ » de la carte MAINTENANT.
class ModePill extends StatelessWidget {
  final AppLogic logic;
  const ModePill({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final pal = NowPalette.of(context);
    final m = logic.mode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = modeAccentOverride(m, dark: dark);
    final fg = accent ?? pal.text3;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => showModeSheet(context, logic),
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 3, 6, 3),
        decoration: BoxDecoration(
          color: accent == null ? pal.chip : accent.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(modeIcon(m), size: 12, color: fg),
          const SizedBox(width: 4),
          Text(kModeLabels[m]!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4, color: fg)),
          Icon(Icons.arrow_drop_down_rounded, size: 16, color: fg),
        ]),
      ),
    );
  }
}

/// Chip « malgré tout » (fait en mode Flemme) ou « à fond » (En forme) pour une
/// chose validée à [doneAt]. Dérivé, jamais stocké. Null en Normal.
Widget? modeChipFor(BuildContext context, AppLogic logic, DateTime? doneAt) {
  if (doneAt == null) return null;
  final m = modeAt(logic.state.moodMarks, doneAt, logic.dayStartMin);
  if (m == DayMode.normal) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final c = modeChipColor(m, dark: dark);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
    child: Text(m == DayMode.low ? 'malgré tout' : 'à fond',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
  );
}
