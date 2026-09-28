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
  required int proposedStartMin,
  required bool dayFull,
  required int durationMin,
  required void Function(int startMin) onPlace,
  required VoidCallback onOpen,
  required VoidCallback onDone,
  bool taskDone = false,
  // Tâche en retard : report VOLONTAIRE de l'échéance au jour cliqué (jamais
  // automatique — le retard est une information, pas une gêne à effacer).
  VoidCallback? onRescheduleDeadline,
}) {
  final size = MediaQuery.of(context).size;
  const w = 260.0;
  final h = onRescheduleDeadline == null ? 190.0 : 222.0;
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
    builder: (ctx) => Stack(children: [
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
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            onPlace(proposedStartMin);
                          },
                          style: FilledButton.styleFrom(
                              backgroundColor: kBPrimary,
                              foregroundColor: kBBg,
                              shape: const StadiumBorder(),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              textStyle: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                          child: Text('Caser ${_fmtHm(durationMin)}'),
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
                          onPlace(t.hour * 60 + t.minute);
                        },
                        style: TextButton.styleFrom(
                            backgroundColor: const Color(0x14FFFFFF),
                            foregroundColor: kBText,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
    ]),
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
