import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

/// Saisie directe d'une routine COMPTÉE (Pompes, Tractions… palier > 1).
///
/// Le ✓ d'une routine à cible 1 coche ; une routine comptée mérite mieux :
/// le sheet propose la CIBLE restante du jour préremplie (palier − déjà fait),
/// boutons − / + pour ajuster au réel, validation = un seul incrément.
/// Retourne le nombre loggué (null si annulé). 0 LLM.
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Proposition = ce qui reste pour tenir le palier du jour (au moins 1).
    final remaining = widget.target - widget.done;
    _count = remaining >= 1 ? remaining : 1;
  }

  void _bump(int delta) {
    setState(() => _count = (_count + delta).clamp(1, 9999));
  }

  Future<void> _validate() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    widget.logic
        .incHabit(widget.activity.id, _count, DateTime(now.year, now.month, now.day));
    if (mounted) Navigator.pop(context, _count);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = widget.activity;
    final after = widget.done + _count;
    final reached = widget.target > 0 && after >= widget.target;

    Widget stepBtn(IconData icon, VoidCallback? onTap) => SizedBox(
          width: 56,
          height: 56,
          child: FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
                padding: EdgeInsets.zero, shape: const CircleBorder()),
            child: Icon(icon, size: 26),
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
                ? 'AUJOURD\'HUI : ${widget.done}/${widget.target}'
                    '${a.finalTarget != null && a.finalTarget! > widget.target ? ' · CAP ${a.finalTarget}' : ''}'
                : 'AUJOURD\'HUI : ${widget.done}',
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
              stepBtn(Icons.remove_rounded, _count > 1 ? () => _bump(-1) : null),
              SizedBox(
                width: 110,
                child: Text(
                  '$_count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 44, fontWeight: FontWeight.w800, height: 1),
                ),
              ),
              stepBtn(Icons.add_rounded, () => _bump(1)),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              reached
                  ? '→ ${after}/${widget.target} — palier tenu ✓'
                  : widget.target > 0
                      ? '→ ${after}/${widget.target} aujourd\'hui'
                      : '→ $after aujourd\'hui',
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
              label: Text('Valider +$_count'),
            ),
          ),
        ],
      ),
    );
  }
}
