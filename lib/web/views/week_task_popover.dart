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
  required DateTime initialDay,
  // Choix du jour (« Planifier » depuis la fiche projet) : les jours à venir
  // avec leur charge ; [initialDay] est le jour présélectionné. Null = jour fixe
  // (clic sur une cellule de Cette semaine).
  List<({DateTime day, int loadMin, int capMin})>? dayChoices,
  // Charge d'un jour pour une durée (grise les jours pleins quand la durée change).
  bool Function(DateTime day, int durationMin)? fits,
  // Créneau proposé pour un jour et une durée (recalculé à chaque changement).
  required ({int start, bool full}) Function(DateTime day, int durationMin) propose,
  // Charge du jour (lot 2 de l'audit) : affichée sous le jour, et « journée
  // pleine » quand la durée ne tient plus dans la capacité. Null = pas de
  // notion de capacité.
  ({int loadMin, int capMin, bool fits}) Function(DateTime day, int durationMin)? load,
  // Premier jour à venir où la durée tient (proposé quand le jour est plein).
  DateTime? Function(int durationMin)? firstFitting,
  required int durationMin, // durée par défaut (reste à caser, sinon 45 min)
  // Estimation de la tâche : valeur actuelle (null = défaut 45 min) et
  // sauvegarde de la durée sélectionnée comme estimation.
  int? estimatedMin,
  void Function(int min)? onEstimate,
  required void Function(DateTime day, int startMin, int durationMin) onPlace,
  required VoidCallback onOpen,
  // Fiche projet (Plan d'action) — lot 3 de l'audit ; null = pas de lien.
  VoidCallback? onOpenProject,
  required VoidCallback onDone,
  bool taskDone = false,
  // Report VOLONTAIRE de l'échéance au jour choisi (jamais automatique — le
  // retard est une information, pas une gêne à effacer). Avec [deadline], le
  // lien n'apparaît que si le jour choisi dépasse l'échéance.
  void Function(DateTime day)? onRescheduleDeadline,
  DateTime? deadline,
}) {
  final size = MediaQuery.of(context).size;
  final w = dayChoices == null ? 272.0 : 300.0;
  final h = (onRescheduleDeadline == null ? 226.0 : 258.0) +
      (dayChoices == null ? 0 : 56) +
      (load == null ? 0 : 18) +
      (onEstimate == null ? 0 : 24);
  final left = (anchor.dx - w / 2).clamp(12.0, size.width - w - 12);
  final top =
      (anchor.dy + 12 + h > size.height ? anchor.dy - h - 12 : anchor.dy + 12)
          .clamp(12.0, size.height - h - 12);

  // État du popover, hors du builder : il survit aux setLocal (un `var` dans
  // le builder repartirait du défaut à chaque clic sur une chip).
  var duration = durationMin;
  var day = initialDay;

  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final slot = propose(day, duration);
      final proposedStartMin = slot.start;
      final dayFull = slot.full;
      final dayLoad = load?.call(day, duration);
      final overCap = dayLoad != null && dayLoad.capMin > 0 && !dayLoad.fits && !dayFull;
      final nextFit = (dayFull || overCap) ? firstFitting?.call(duration) : null;
      final sameDay = nextFit != null &&
          nextFit.year == day.year && nextFit.month == day.month && nextFit.day == day.day;
      final dayLabel = _kDayLong[day.weekday - 1];
      final dayCap =
          '${dayLabel[0].toUpperCase()}${dayLabel.substring(1)} ${day.day}';
      final d0 = DateTime(day.year, day.month, day.day);
      final showReschedule = onRescheduleDeadline != null &&
          (deadline == null ||
              d0.isAfter(DateTime(deadline.year, deadline.month, deadline.day)));
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
                    if (dayChoices != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final c in dayChoices)
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: _DayChip(
                                  day: c.day,
                                  loadMin: c.loadMin,
                                  capMin: c.capMin,
                                  fits: fits?.call(c.day, duration) ?? true,
                                  selected: c.day.year == day.year &&
                                      c.day.month == day.month &&
                                      c.day.day == day.day,
                                  onTap: () => setLocal(() => day = c.day),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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
                    if (dayLoad != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        Expanded(
                          child: Text(
                            dayLoad.capMin == 0
                                ? 'Jour de repos (capacité 0)'
                                : overCap
                                    ? 'Journée pleine : ${_fmtHm(dayLoad.loadMin)} + ${_fmtHm(duration)} > ${_fmtHm(dayLoad.capMin)}'
                                    : 'Charge ${_fmtHm(dayLoad.loadMin)} / ${_fmtHm(dayLoad.capMin)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: overCap || dayLoad.capMin == 0 ? kBAttention : kBText4,
                                fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                        if (nextFit != null && !sameDay)
                          InkWell(
                            onTap: () => setLocal(() => day = nextFit),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                  '${_kDayShort[nextFit.weekday - 1]} ${nextFit.day} tient →',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: kBPrimary)),
                            ),
                          ),
                      ]),
                    ],
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
                    if (onEstimate != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(
                            estimatedMin == null
                                ? 'Tâche non estimée (45 min par défaut)'
                                : 'Tâche estimée ${_fmtHm(estimatedMin)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: kBText4,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                        if (estimatedMin != duration)
                          InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              onEstimate(duration);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text('Estimer à ${_fmtHm(duration)}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: kBPrimary)),
                            ),
                          ),
                      ]),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              onPlace(day, proposedStartMin, duration);
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
                            onPlace(day, t.hour * 60 + t.minute, duration);
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
                      if (onOpenProject != null) _link(ctx, 'Fiche projet', onOpenProject),
                      const Spacer(),
                      if (!taskDone) _link(ctx, 'Marquer faite', onDone),
                    ]),
                    if (showReschedule)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          const Icon(Icons.event_repeat_outlined,
                              size: 13, color: kBAttention),
                          const SizedBox(width: 4),
                          _link(
                              ctx,
                              'Reporter l\'échéance au $dayLabel ${day.day}',
                              () => onRescheduleDeadline(day),
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

const _kDayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Jour proposable : « Mar 30 » + charge « 2h/7h » (« plein » si ça ne tient
/// pas, « repos » sans capacité). Sélectionné = bordure primaire.
class _DayChip extends StatelessWidget {
  final DateTime day;
  final int loadMin, capMin;
  final bool fits, selected;
  final VoidCallback onTap;
  const _DayChip(
      {required this.day,
      required this.loadMin,
      required this.capMin,
      required this.fits,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sub = capMin == 0
        ? 'repos'
        : !fits
            ? 'plein'
            : '${_fmtHm(loadMin).replaceAll(' ', '')}/${_fmtHm(capMin).replaceAll(' ', '')}';
    final dim = !fits;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: selected ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? kBPrimary.withOpacity(.6) : kBLine),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${_kDayShort[day.weekday - 1]} ${day.day}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: dim ? kBText4 : kBText,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(
                  fontSize: 10,
                  color: !fits && capMin > 0 ? kBAttention : kBText3,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
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
