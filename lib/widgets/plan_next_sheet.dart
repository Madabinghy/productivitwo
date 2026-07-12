import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';

/// « Planifions » : la prochaine exécution d'une routine devient un bloc posé
/// — date/heure proposées depuis le réel (créneaux libres, fenêtre d'indispo
/// respectée via [notBefore]), modifiables, un tap pour confirmer. 0 LLM.
Future<bool> showPlanNextSheet(
  BuildContext context, {
  required AppLogic logic,
  required Activity routine,
  DateTime? notBefore,
}) async {
  final posed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) =>
        _PlanNextSheet(logic: logic, routine: routine, notBefore: notBefore),
  );
  return posed == true;
}

class _PlanNextSheet extends StatefulWidget {
  final AppLogic logic;
  final Activity routine;
  final DateTime? notBefore;
  const _PlanNextSheet(
      {required this.logic, required this.routine, this.notBefore});

  @override
  State<_PlanNextSheet> createState() => _PlanNextSheetState();
}

class _PlanNextSheetState extends State<_PlanNextSheet> {
  final _sync = FirestoreSync();
  bool _saving = false;

  int get _durationMin =>
      (widget.routine.timerMin ?? 0) > 0 ? widget.routine.timerMin! : 20;

  /// Candidats déterministes : premier créneau libre après [notBefore]
  /// aujourd'hui, ce soir, demain matin / demain soir.
  List<({String label, DateTime at})> _candidates() {
    final now = DateTime.now();
    final from = widget.notBefore != null && widget.notBefore!.isAfter(now)
        ? widget.notBefore!
        : now;
    final out = <({String label, DateTime at})>[];

    // Aujourd'hui : premier trou libre réel après la fenêtre.
    if (from.day == now.day && from.hour < 21) {
      final slots =
          freeDaySlots(from, widget.logic.todayBlocks, minMinutes: _durationMin);
      if (slots.isNotEmpty) {
        final p = slots.first.start.split(':');
        final at = DateTime(now.year, now.month, now.day, int.parse(p[0]),
            int.parse(p[1]));
        out.add((label: 'Aujourd\'hui ${_hFr(at)}', at: at));
      }
    }
    final tomorrow = now.add(const Duration(days: 1));
    out.add((
      label: 'Demain matin 7 h 30',
      at: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 30)
    ));
    out.add((
      label: 'Demain soir 19 h',
      at: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0)
    ));
    return out;
  }

  Future<void> _pose(DateTime at) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ymd =
          '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
      await _sync.addScheduleBlock(
        ymd,
        ScheduleBlock(
          startTime:
              '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
          durationMin: _durationMin,
          title: widget.routine.name,
          category: 'routine',
          activityId: widget.routine.id,
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${widget.routine.name} posée ${at.day == DateTime.now().day ? 'aujourd\'hui' : 'demain'} à ${_hFr(at)} — elle t\'attendra.'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a été posé, réessaie.')));
      }
    }
  }

  Future<void> _custom() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (day == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null || !mounted) return;
    await _pose(DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prochaine exécution — ${widget.routine.name}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '$_durationMin min · posée comme un vrai bloc — visible du check-in.',
            style: TextStyle(
                fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
          ),
          const SizedBox(height: 14),
          for (final c in _candidates())
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _saving ? null : () => _pose(c.at),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_available_outlined,
                        size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Text(c.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          Center(
            child: TextButton(
              onPressed: _saving ? null : _custom,
              child: const Text('Autre date / heure…',
                  style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  String _hFr(DateTime d) => d.minute == 0
      ? '${d.hour} h'
      : '${d.hour} h ${d.minute.toString().padLeft(2, '0')}';
}
