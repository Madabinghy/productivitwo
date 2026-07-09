import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';

/// Renégociation tactique (maquette 12a) — entrée : « Renégocier » de la carte
/// dérive. Trois issues GÉNÉRÉES DEPUIS LE RÉEL, chacune avec sa conséquence
/// affichée — on choisit en connaissance de cause. « Abandonner » reste
/// possible et compte comme sauté. 0 LLM.
Future<void> showRenegotiateSheet(
  BuildContext context, {
  required AppLogic logic,
  required ScheduleBlock block,
  required String date,
  void Function(ScheduleBlock block)? onLaunch,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RenegotiateSheet(
        logic: logic, block: block, date: date, onLaunch: onLaunch),
  );
}

enum _Issue { reduce, move, report }

class _RenegotiateSheet extends StatefulWidget {
  final AppLogic logic;
  final ScheduleBlock block;
  final String date;
  final void Function(ScheduleBlock block)? onLaunch;

  const _RenegotiateSheet(
      {required this.logic,
      required this.block,
      required this.date,
      this.onLaunch});

  @override
  State<_RenegotiateSheet> createState() => _RenegotiateSheetState();
}

class _RenegotiateSheetState extends State<_RenegotiateSheet> {
  final _sync = FirestoreSync();
  _Issue _chosen = _Issue.reduce;
  bool _saving = false;
  String? _moveSlot; // dernier créneau libre du jour ("HH:mm")
  int _reportCount = 1; // ce report inclus

  ScheduleBlock get b => widget.block;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _moveSlot = findLastFreeSlot(
        now, widget.logic.todayBlocks, b.durationMin,
        excludeBlockId: b.id);
    _countReports(now);
  }

  /// « 2ᵉ report cette semaine » — compté depuis les faits des 7 derniers jours.
  Future<void> _countReports(DateTime now) async {
    final week = <ScheduleBlock>[];
    for (var i = 1; i <= 7; i++) {
      final d = now.subtract(Duration(days: i));
      final ymd =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      try {
        final s = await _sync.fetchDailySchedule(ymd);
        week.addAll(
            (s?.blocks ?? const []).where((x) => x.status != 'deleted'));
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _reportCount = weeklyReportCount(b, week) + 1);
    }
  }

  /// Minutes réellement logguées sur le bloc (même croisement que la dérive).
  int _loggedMin() {
    final now = DateTime.now();
    var total = 0;
    for (final s in widget.logic.state.sessions) {
      if (s.startAt.year != now.year ||
          s.startAt.month != now.month ||
          s.startAt.day != now.day) continue;
      final matches = (b.activityId != null && s.activityId == b.activityId) ||
          (b.taskId != null && s.taskId == b.taskId);
      if (!matches) continue;
      total += (s.endAt ?? now).difference(s.startAt).inMinutes;
    }
    return total;
  }

  Future<void> _validate() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = TimeOfDay.now();
    final nowHm =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    try {
      switch (_chosen) {
        case _Issue.reduce:
          // 25 min maintenant — 1 relance vaut mieux que 0 ; chrono à la validation.
          await _sync.updateScheduleBlockTime(widget.date, b.id,
              startTime: nowHm, durationMin: 25);
          b.startTime = nowHm;
          b.durationMin = 25;
          if (mounted) Navigator.pop(context);
          if (b.projectId != null || b.activityId != null) {
            widget.onLaunch?.call(b);
          }
          return;
        case _Issue.move:
          await _sync.updateScheduleBlockTime(widget.date, b.id,
              startTime: _moveSlot!);
          break;
        case _Issue.report:
          // Fait tracké : sauté + cause « reporte » → demain la proposition le
          // pose EN PREMIER (règle serveur), marqué reproposé, refusable.
          await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
          await _sync.updateBlockSkipReason(widget.date, b.id, 'reporte');
          break;
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
  }

  /// « Abandonner pour aujourd'hui » — compte comme sauté (le check-in du soir
  /// demandera le pourquoi), aucune pénalité cachée.
  Future<void> _abandon() async {
    await _sync.updateBlockStatus(widget.date, b.id, 'skipped');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logged = _loggedMin();
    final left = usefulMinutesLeft(DateTime.now());
    final leftLabel = left >= 60
        ? '${left ~/ 60} h ${(left % 60).toString().padLeft(2, '0')}'
        : '$left min';

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Renégocier — ${b.title}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(
            'POSÉ À ${_hFr(b.startTime)} · $logged MIN LOGGUÉE${logged > 1 ? 'S' : ''}',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: cs.tertiary),
          ),
          const SizedBox(height: 12),
          Text(
            'Il reste $leftLabel utiles aujourd\'hui. Trois issues — choisis en connaissance de cause.',
            style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: cs.onSurface.withOpacity(.85)),
          ),
          const SizedBox(height: 14),
          _option(
            cs,
            _Issue.reduce,
            'Réduire : 25 min, maintenant',
            'L\'essentiel vaut mieux que 0 — le chrono démarre à la validation',
          ),
          if (_moveSlot != null)
            _option(
              cs,
              _Issue.move,
              'Déplacer à ${_hFr(_moveSlot!)}',
              'Dernier créneau libre du jour${(int.tryParse(_moveSlot!.split(':').first) ?? 0) >= 19 ? ' — mord sur la soirée' : ''}',
            ),
          _option(
            cs,
            _Issue.report,
            'Reporter à demain',
            _reportCount > 1
                ? '$_reportCountᵉ report cette semaine — demain il passe en premier, avant tout'
                : 'Demain il passe en premier, avant tout',
            amber: _reportCount > 1,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _validate,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: Text(
                _saving ? 'Enregistrement…' : 'Valider — Orion repose le bloc'),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _saving ? null : _abandon,
              child: Text(
                'Abandonner pour aujourd\'hui (compte comme sauté)',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurface.withOpacity(.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(
      ColorScheme cs, _Issue issue, String title, String consequence,
      {bool amber = false}) {
    final selected = _chosen == issue;
    final accent = amber ? cs.tertiary : cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _chosen = issue),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accent.withOpacity(.7)
                : cs.onSurface.withOpacity(.15),
            width: selected ? 1.4 : 1,
          ),
          color: selected ? accent.withOpacity(.06) : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? accent : cs.onSurface.withOpacity(.3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(consequence,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: amber
                              ? cs.tertiary.withOpacity(.9)
                              : cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hFr(String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? p[1] : '00';
    return m == '00' ? '$h h' : '$h h $m';
  }
}
