import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart' show elanBucket;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/mode_colors.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Mode du jour côté web (Modes et coups lot 5) : même donnée que le mobile —
/// poser un mode écrit un pointage d'élan (2 / 3 / 4) sur le créneau courant de
/// la journée vécue ; le mode courant = dernier pointage du jour vécu.
MoodMark moodMarkForMode(DayMode m, {required int dayStartMin, DateTime? now}) {
  final t = now ?? DateTime.now();
  return MoodMark(
    at: t,
    ymd: livedProgramYmd(t, dayStartMin),
    kind: kMoodElan,
    value: modeElanValue(m),
    moment: elanBucket(livedNowMin(t, dayStartMin)),
  );
}

Color webModeColor(DayMode m) => modeAccentOverride(m, dark: true) ?? kBPrimary;

/// Dialog « Mode du jour » du menu ⋯.
Future<DayMode?> showWebModeDialog(BuildContext context, DayMode current) {
  return showDialog<DayMode>(
    context: context,
    builder: (c) => SimpleDialog(
      backgroundColor: kBSurface,
      title: const Text('Mode du jour', style: TextStyle(color: kBText, fontSize: 17, fontWeight: FontWeight.w700)),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Une posture, changeable à tout moment. Elle pointe ton élan et repart en Normal demain.',
              style: TextStyle(fontSize: 12.5, color: kBText3)),
        ),
        for (final m in DayMode.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, m),
            child: Row(children: [
              Icon(modeIcon(m), size: 18, color: webModeColor(m)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kModeLabels[m]!, style: const TextStyle(color: kBText, fontWeight: FontWeight.w700)),
                  Text(modeDescription(m), style: const TextStyle(fontSize: 12, color: kBText3)),
                ]),
              ),
              if (m == current) Icon(Icons.check_rounded, size: 18, color: webModeColor(m)),
            ]),
          ),
      ],
    ),
  );
}

/// Pilule « Flemme » / « En forme » de la barre du haut (rien en Normal).
class WebModePill extends StatelessWidget {
  final DayMode mode;
  final VoidCallback onTap;
  const WebModePill({super.key, required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (mode == DayMode.normal) return const SizedBox.shrink();
    final c = webModeColor(mode);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(modeIcon(mode), size: 13, color: c),
            const SizedBox(width: 5),
            Text(kModeLabels[mode]!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: c)),
          ]),
        ),
      ),
    );
  }
}

/// Chip « malgré tout » / « à fond » d'une chose faite à [doneAt] (null en Normal).
Widget? webModeChip(List<MoodMark> marks, DateTime? doneAt, int dayStartMin) {
  if (doneAt == null) return null;
  final m = modeAt(marks, doneAt, dayStartMin);
  if (m == DayMode.normal) return null;
  final c = webModeColor(m);
  return Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
    child: Text(m == DayMode.low ? 'malgré tout' : 'à fond', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c)),
  );
}
