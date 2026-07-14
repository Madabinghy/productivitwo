import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Saisie directe d'une routine COMPTÉE (Pompes, Tractions, verres d'eau…
/// palier > 1).
///
/// Compteur ABSOLU du jour : le gros chiffre = ce qui est déjà fait
/// aujourd'hui, le user ajuste avec − / + en fonction de ce qu'il vient de
/// faire (appui long = défilement rapide), la cible du palier reste affichée.
/// Validation = un seul incrément du delta (corrections à la baisse permises).
/// Retourne le nouveau total du jour (null si annulé ou inchangé). 0 LLM.
Future<int?> showHabitCountSheet(
  BuildContext context, {
  required AppLogic logic,
  required Activity activity,
}) {
  final target = logic.activeHabitTarget(activity);
  final done = logic.habitValueOn(activity.id, DateTime.now());
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (_) => _HabitCountSheet(
        logic: logic, activity: activity, target: target, done: done),
  );
}

class _HabitCountSheet extends StatefulWidget {
  final AppLogic logic;
  final Activity activity;
  final int target;
  final int done;
  const _HabitCountSheet(
      {required this.logic,
      required this.activity,
      required this.target,
      required this.done});

  @override
  State<_HabitCountSheet> createState() => _HabitCountSheetState();
}

class _HabitCountSheetState extends State<_HabitCountSheet> {
  late int _count;
  Timer? _repeat;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _count = widget.done; // le réel du jour — le user ajuste depuis là
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _bump(int delta) {
    setState(() => _count = (_count + delta).clamp(0, 9999));
  }

  // Appui long : défilement rapide (utile pour poser une série de 12 pompes).
  void _startRepeat(int delta) {
    _repeat?.cancel();
    _repeat = Timer.periodic(
        const Duration(milliseconds: 110), (_) => _bump(delta));
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Future<void> _validate() async {
    if (_saving) return;
    final delta = _count - widget.done;
    if (delta == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    widget.logic
        .incHabit(widget.activity.id, delta, DateTime(now.year, now.month, now.day));
    if (mounted) Navigator.pop(context, _count);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.activity;
    final reached = widget.target > 0 && _count >= widget.target;

    Widget stepBtn(IconData icon, int delta, {bool enabled = true}) =>
        GestureDetector(
          onLongPressStart: enabled ? (_) => _startRepeat(delta) : null,
          onLongPressEnd: (_) => _stopRepeat(),
          onLongPressCancel: _stopRepeat,
          child: SizedBox(
            width: 56,
            height: 56,
            child: FilledButton.tonal(
              onPressed: enabled ? () => _bump(delta) : null,
              style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero, shape: const CircleBorder()),
              child: Icon(icon, size: 26),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.name,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(
            widget.target > 0
                ? 'CIBLE DU JOUR : ${widget.target}'
                    '${a.finalTarget != null && a.finalTarget! > widget.target ? ' · CAP ${a.finalTarget}' : ''}'
                : 'AUJOURD\'HUI',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: cs.tertiary),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              stepBtn(Icons.remove_rounded, -1, enabled: _count > 0),
              SizedBox(
                width: 110,
                child: Text(
                  '$_count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: reached ? cs.primary : cs.onSurface),
                ),
              ),
              stepBtn(Icons.add_rounded, 1),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              reached
                  ? '$_count/${widget.target} — palier tenu ✓'
                  : widget.target > 0
                      ? '$_count/${widget.target} aujourd\'hui'
                      : '$_count aujourd\'hui',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.6)),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _validate,
              icon: const Icon(Icons.check_rounded),
              label: Text(_count == widget.done
                  ? 'Fermer'
                  : 'Valider ${_count - widget.done > 0 ? '+' : ''}${_count - widget.done}'),
            ),
          ),
        ],
      ),
    );
  }
}
