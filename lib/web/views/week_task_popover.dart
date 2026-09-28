import 'package:flutter/material.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

// Popover « caser » de Cette semaine (handoff cette-semaine-2026-09, § 3) :
// ouvert au clic sur une cellule jour d'une ligne de tâche.

const _kDayLong = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche'
];

String _clock(int min) =>
    '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Affiche le popover ancré à [anchor] (position globale du clic). Les
/// callbacks ferment le popover eux-mêmes via le `Navigator`.
Future<void> showWeekTaskPopover(
  BuildContext context, {
  required Offset anchor,
  required String title,
  required DateTime day,
  // Créneau proposé pour une durée donnée (recalculé quand la durée change).
  required ({int start, bool full}) Function(int durationMin) propose,
  required int durationMin, // durée par défaut (reste à caser, sinon 45 min)
  required void Function(int startMin, int durationMin) onPlace,
  required VoidCallback onOpen,
  required VoidCallback onDone,
  bool taskDone = false,
  // Tâche en retard : report VOLONTAIRE de l'échéance au jour cliqué (jamais
  // automatique — le retard est une information, pas une gêne à effacer).
  VoidCallback? onRescheduleDeadline,
}) {
  final size = MediaQuery.of(context).size;
  const w = 260.0;
  final h = onRescheduleDeadline == null ? 226.0 : 258.0;
  final left = (anchor.dx - w / 2).clamp(12.0, size.width - w - 12);
  final top =
      (anchor.dy + 12 + h > size.height ? anchor.dy - h - 12 : anchor.dy + 12)
          .clamp(12.0, size.height - h - 12);
  final dayLabel = _kDayLong[day.weekday - 1];
  final dayCap =
      '${dayLabel[0].toUpperCase()}${dayLabel.substring(1)} ${day.day}';

  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      var duration = durationMin;
      final slot = propose(duration);
      final proposedStartMin = slot.start;
      final dayFull = slot.full;
      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          child: Material(
            color: kBRaised,
            elevation: 12,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kBPrimary.withOpacity(.55)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: kBText)),
                    const SizedBox(height: 4),
                    Text(
                      dayFull
                          ? '$dayCap · journée pleine, 8 h 00 proposé'
                          : '$dayCap · premier créneau libre ${_clock(proposedStartMin)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: dayFull ? kBAttention : kBText3,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: 8),
                    // Durée : le défaut est le reste à caser (45 min sans
                    // estimation) ; les autres valeurs sont à un clic.
                    Wrap(spacing: 5, runSpacing: 4, children: [
                      for (final d in _durationChoices(durationMin))
                        _DurationChip(
                          label: _fmtHm(d),
                          selected: d == duration,
                          onTap: () => setLocal(() => duration = d),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              onPlace(proposedStartMin, duration);
                            },
                            style: FilledButton.styleFrom(
                                backgroundColor: kBPrimary,
                                foregroundColor: kBBg,
                                shape: const StadiumBorder(),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                textStyle: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            child: Text('Caser ${_fmtHm(duration)}'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: TextButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay(
                                  hour: proposedStartMin ~/ 60,
                                  minute: proposedStartMin % 60),
                            );
                            if (t == null || !ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            onPlace(t.hour * 60 + t.minute, duration);
                          },
                          style: TextButton.styleFrom(
                              backgroundColor: const Color(0x14FFFFFF),
                              foregroundColor: kBText,
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              textStyle: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                          child: const Text("Choisir l'heure"),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      _link(ctx, 'Ouvrir la tâche', onOpen),
                      const Spacer(),
                      if (!taskDone) _link(ctx, 'Marquer faite', onDone),
                    ]),
                    if (onRescheduleDeadline != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          const Icon(Icons.event_repeat_outlined,
                              size: 13, color: kBAttention),
                          const SizedBox(width: 4),
                          _link(
                              ctx,
                              'Reporter l\'échéance au ${dayLabel} ${day.day}',
                              onRescheduleDeadline,
                              color: kBAttention),
                        ]),
                      ),
                  ]),
            ),
          ),
        ),
      ]);
    }),
  );
}

/// 30 · 45 · 60 · 90 · 120, plus la durée par défaut si elle n'y est pas.
List<int> _durationChoices(int defaultMin) {
  final base = [30, 45, 60, 90, 120];
  if (!base.contains(defaultMin)) base.add(defaultMin);
  base.sort();
  return base;
}

class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DurationChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected ? kBActive : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? kBPrimary.withOpacity(.5) : kBLine),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? kBText : kBText2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
      );
}

Widget _link(BuildContext ctx, String label, VoidCallback onTap,
        {Color color = kBPrimary}) =>
    InkWell(
      onTap: () {
        Navigator.of(ctx).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    );
