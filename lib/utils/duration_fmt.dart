import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Formate une durée en minutes de façon lisible : 45 min, 1h, 1h30, 4h.
String fmtMin(int min) {
  if (min <= 0) return '0 min';
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

const _presets = [15, 30, 45, 60, 90, 120, 180, 240];

/// Sélecteur de durée heures/minutes (roue Cupertino + presets rapides).
/// Retourne la durée en minutes, ou null si annulé.
/// [allowZero] ajoute un choix « Pas de cible » qui retourne 0.
Future<int?> pickDurationMin(
  BuildContext context, {
  required int initial,
  String title = 'Durée',
  bool allowZero = false,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _DurationPickerSheet(
        initial: initial, title: title, allowZero: allowZero),
  );
}

class _DurationPickerSheet extends StatefulWidget {
  final int initial;
  final String title;
  final bool allowZero;

  const _DurationPickerSheet(
      {required this.initial, required this.title, required this.allowZero});

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _minutes;
  // Incrémenté quand un preset est tapé → recrée la roue à la nouvelle valeur
  // (sans ça, la roue ignorerait le preset ; avec une key sur _minutes, elle
  // serait recréée à chaque cran de scroll).
  int _wheelEpoch = 0;

  // La roue impose initialTimerDuration multiple de minuteInterval.
  static const _step = 5;

  @override
  void initState() {
    super.initState();
    final rounded = ((widget.initial / _step).round() * _step).clamp(0, 23 * 60 + 55);
    _minutes = rounded == 0 ? 30 : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    selected: _minutes == p,
                    onSelected: (_) => setState(() {
                      _minutes = p;
                      _wheelEpoch++;
                    }),
                    showCheckmark: false,
                    label: Text(fmtMin(p)),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          _minutes == p ? FontWeight.w600 : FontWeight.w500,
                      color: _minutes == p
                          ? cs.primary
                          : cs.onSurface.withOpacity(.7),
                    ),
                    selectedColor: cs.primary.withOpacity(.14),
                    backgroundColor: cs.surfaceVariant.withOpacity(.35),
                    side: BorderSide(
                      color: _minutes == p
                          ? cs.primary.withOpacity(.55)
                          : Colors.transparent,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
              ],
            ),
            SizedBox(
              height: 160,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(context).brightness,
                ),
                child: CupertinoTimerPicker(
                  key: ValueKey(_wheelEpoch),
                  mode: CupertinoTimerPickerMode.hm,
                  minuteInterval: _step,
                  initialTimerDuration: Duration(minutes: _minutes),
                  onTimerDurationChanged: (d) =>
                      setState(() => _minutes = d.inMinutes),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _minutes <= 0 ? null : _minutes),
              child: const Text('Valider'),
            ),
            if (widget.allowZero)
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text('Pas de cible',
                    style: TextStyle(color: cs.onSurface.withOpacity(.55))),
              ),
          ],
        ),
      ),
    );
  }
}
