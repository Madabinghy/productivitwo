import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';

/// Réglage des moments de la journée (Matin · Midi · Après-midi · Soir) :
/// début et fin de chacun, le Soir pouvant finir après minuit (par défaut au
/// début de la journée vécue). Un cinquième moment, Miracle Morning, s'allume
/// ici (2026-11-21) : il commence quand la journée commence, seule sa fin se
/// règle, et le matin commence quand il finit. Ouvert depuis la pastille « Soir ·
/// 19 h → 5 h » de la carte « Routine du moment » et depuis Paramètres.
/// Écrit `data/meta.momentWindows` ; « Par défaut » efface le réglage.
Future<void> showMomentsEditor(BuildContext context, {required AppLogic logic, required FirestoreSync sync}) async {
  final result = await showModalBottomSheet<Map<String, (int, int)>?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MomentsEditor(logic: logic),
  );
  if (result == null) return;
  // Retour immédiat à l'écran, le flux meta confirme ensuite.
  logic.momentWindows = result;
  logic.onChange();
  await sync.saveMomentWindows(result);
}

class _MomentsEditor extends StatefulWidget {
  final AppLogic logic;
  const _MomentsEditor({required this.logic});

  @override
  State<_MomentsEditor> createState() => _MomentsEditorState();
}

class _MomentsEditorState extends State<_MomentsEditor> {
  late Map<String, (int, int)> _w;

  @override
  void initState() {
    super.initState();
    _w = {for (final m in widget.logic.moments) m.key: (m.startMin, m.endMin)};
  }

  List<Moment> get _timed => timedMomentsWith(_w, dayStartMin: widget.logic.dayStartMin);

  String _hm(int min) {
    final m = min % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _pick(Moment m, {required bool end}) async {
    final cur = end ? m.endMin : m.startMin;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (cur % (24 * 60)) ~/ 60, minute: cur % 60),
      helpText: end ? 'Fin · ${m.label}' : 'Début · ${m.label}',
    );
    if (t == null) return;
    var v = t.hour * 60 + t.minute;
    // Une fin « plus tôt » que le début = le lendemain (Soir 19 h → 5 h).
    if (end && v <= m.startMin) v += 24 * 60;
    setState(() {
      final old = m.endMin;
      _w = {..._w, m.key: end ? (m.startMin, v) : (v, m.endMin < v ? v + 60 : m.endMin)};
      // Le matin suit la fin du Miracle Morning tant qu'il lui était collé.
      if (end && m.key == kMomentMiracle) _stickMorning(old, v);
    });
  }

  bool get _miracle => _w.containsKey(kMomentMiracle);

  (int, int) get _morning => _w[kMomentMorning] ?? (kTimedMoments.first.startMin, kTimedMoments.first.endMin);

  void _stickMorning(int oldEnd, int newEnd) {
    final mo = _morning;
    if ((mo.$1 == oldEnd || mo.$1 < newEnd) && newEnd < mo.$2) _w = {..._w, kMomentMorning: (newEnd, mo.$2)};
  }

  void _toggleMiracle(bool on) {
    final start = widget.logic.dayStartMin;
    setState(() {
      if (on) {
        final end = start + kMiracleDefaultMin;
        _w = {..._w, kMomentMiracle: (start, end)};
        _stickMorning(-1, end);
      } else {
        final end = _w[kMomentMiracle]!.$2;
        final mo = _morning;
        _w = {..._w}..remove(kMomentMiracle);
        // Le matin reprend là où la journée commence, s'il était collé au Miracle Morning.
        final back = start > kTimedMoments.first.startMin ? start : kTimedMoments.first.startMin;
        if (mo.$1 == end && back < mo.$2) _w = {..._w, kMomentMorning: (back, mo.$2)};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timed = _timed;
    final error = validateMoments(timed);
    final isDefault = _w.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Moments de la journée', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Les routines se rangent par moment. La journée commence à ${dayStartLabel(widget.logic.dayStartMin)} '
              '(Paramètres) : sans réglage, le soir court jusque-là.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
          const SizedBox(height: 6),
          SwitchListTile(
            key: const Key('moments-miracle'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Miracle Morning', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            subtitle: Text('Un moment avant le matin, pour ton rituel du réveil. Il commence quand ta journée commence.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            value: _miracle,
            onChanged: _toggleMiracle,
          ),
          const SizedBox(height: 8),
          for (final m in timed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 96,
                  child: Text(m.label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: OutlinedButton(
                    // Le Miracle Morning commence avec la journée : son début ne se règle pas ici.
                    onPressed: m.key == kMomentMiracle ? null : () => _pick(m, end: false),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(_hm(m.startMin), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: cs.onSurface.withOpacity(.45)),
                ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(m, end: true),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(m.endMin >= 24 * 60 ? '${_hm(m.endMin)} +1' : _hm(m.endMin),
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ]),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(error, style: TextStyle(fontSize: 12.5, color: cs.error, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(
              onPressed: isDefault ? null : () => setState(() => _w = const {}),
              child: const Text('Par défaut'),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: error == null ? () => Navigator.pop(context, _w) : null,
              child: const Text('Enregistrer'),
            ),
          ]),
        ]),
      ),
    );
  }
}
