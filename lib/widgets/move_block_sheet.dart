import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/challenge_reminders.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';

/// Déplacer un bloc à la main (maquette 23a) : les cibles sont les créneaux
/// libres RÉELS du jour — les protectedSlots des domaines et les offSlots des
/// artefacts ne sont JAMAIS des cibles. Un déplacement = update de l'heure du
/// bloc, zéro effet sur le reste, non compté comme sauté (≠ report 12a).
/// Retourne true si le bloc a été déplacé. 0 LLM.
Future<bool> showMoveBlockSheet(
  BuildContext context, {
  required AppLogic logic,
  required ScheduleBlock block,
  required String date,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) => _MoveSheet(logic: logic, block: block, date: date),
  );
  return moved == true;
}

class _MoveSheet extends StatefulWidget {
  final AppLogic logic;
  final ScheduleBlock block;
  final String date;
  const _MoveSheet(
      {required this.logic, required this.block, required this.date});

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final _sync = FirestoreSync();
  List<({String start, int minutes})> _slots = const [];
  bool _eveningProtected = false;
  bool _saving = false;

  ScheduleBlock get b => widget.block;

  @override
  void initState() {
    super.initState();
    _computeSlots(protected: _domainProtected());
    _loadArtifactOffSlots(); // complète avec les soirées off du menu (async)
  }

  Set<String> _domainProtected() {
    final protected = <String>{};
    for (final d in widget.logic.state.domains) {
      if (d.deleted) continue;
      protected.addAll(d.protectedSlots);
    }
    return protected;
  }

  Future<void> _loadArtifactOffSlots() async {
    try {
      final artifacts = await _sync.streamArtifacts().first;
      final protected = _domainProtected();
      for (final a in artifacts) {
        if (a.deleted) continue;
        protected.addAll(a.offSlots);
      }
      if (mounted) setState(() => _computeSlots(protected: protected));
    } catch (_) {}
  }

  void _computeSlots({required Set<String> protected}) {
    final now = DateTime.now();
    // Soirée protégée → la journée utile s'arrête à 18 h (jamais une cible).
    _eveningProtected = slotIsProtected('19:00', now.weekday, protected);
    _slots = freeDaySlots(
      now,
      widget.logic.todayBlocks,
      dayEndHour: _eveningProtected ? 18 : 22,
      minMinutes: b.durationMin < 25 ? b.durationMin : 25,
      excludeBlockId: b.id,
    )
        .where((s) => !slotIsProtected(s.start, now.weekday, protected))
        .toList();
  }

  Future<void> _moveTo(String startTime) async {
    if (_saving) return;
    setState(() => _saving = true);
    final oldStart = b.startTime;
    try {
      await _sync.updateScheduleBlockTime(widget.date, b.id,
          startTime: startTime);
      b.startTime = startTime;
      // Bloc-défi : l'alarme et les rappels suivent la nouvelle heure.
      await rescheduleChallengeNotifications(
          block: b,
          date: widget.date,
          oldStartTime: oldStart,
          alarmSoundKey: widget.logic.state.alarmSound);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Déplacé à ${_hFr(startTime)} — rien d\'autre ne bouge, pas compté comme sauté.'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Échec réseau — rien n\'a changé, réessaie.')));
      }
    }
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
          Text('Déplacer — ${b.title}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(
            'CRÉNEAUX LIBRES RÉELS · RIEN D\'AUTRE NE BOUGE',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: cs.tertiary),
          ),
          const SizedBox(height: 14),
          if (_slots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Plus aucun créneau libre aujourd\'hui — reporter à demain est plus honnête (le bloc passera en premier).',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: cs.onSurface.withOpacity(.7)),
              ),
            ),
          for (final s in _slots)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _saving ? null : () => _moveTo(s.start),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(.4)),
                ),
                child: Row(
                  children: [
                    Text(_hFr(s.start),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cs.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Créneau libre — ${_durFr(s.minutes)}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('POSER ICI',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: cs.primary)),
                  ],
                ),
              ),
            ),
          if (_eveningProtected)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withOpacity(.12)),
              ),
              child: Row(
                children: [
                  Text('Soirée off',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withOpacity(.4))),
                  const SizedBox(width: 10),
                  Text('protégée — pas une cible',
                      style: TextStyle(fontSize: 11.5, color: cs.error)),
                ],
              ),
            ),
          // Heure LIBRE : les créneaux proposés sont des suggestions, jamais
          // une contrainte — le user reste maître de son programme.
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _saving
                ? null
                : () async {
                    final p = b.startTime.split(':');
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                          hour: int.tryParse(p.first) ?? 9,
                          minute:
                              p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0),
                    );
                    if (t == null) return;
                    await _moveTo(
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  },
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.onSurface.withOpacity(.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 18, color: cs.onSurface.withOpacity(.7)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Choisir l\'heure moi-même…',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'C\'est un déplacement, pas un report — pas compté comme sauté.',
            style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: cs.onSurface.withOpacity(.5)),
          ),
        ],
      ),
    );
  }

  String _hFr(String hm) {
    final p = hm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? p[1] : '00';
    return m == '00' ? '$h h' : '$h h $m';
  }

  String _durFr(int min) =>
      min >= 60 ? '${min ~/ 60} h${min % 60 > 0 ? ' ${(min % 60).toString().padLeft(2, '0')}' : ''}' : '$min min';
}
