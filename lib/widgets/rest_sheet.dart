import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show routineSeries;
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;
import 'package:productivitwo_v1/utils/rest_periods.dart';

/// Veille de domaines (Modes et coups § 2.3) : cases cochables, « jusqu'au … »
/// (fin du coup, ou ce soir pour un deep work). Un domaine en veille : ses
/// minimums ne comptent plus, ses actions sortent de la carte du moment,
/// `plan_day` ne programme rien dessus, et les séries de ses routines sont
/// gelées (`restPeriods`). Se lève d'un tap. Retourne le nombre de domaines
/// mis en veille.
Future<int> showRestSheet(
  BuildContext context, {
  required AppLogic logic,
  required FirestoreSync sync,
  required String untilYmd,
  Set<String> excludeDomainIds = const {},
  String? title,
}) async {
  final domains = logic.state.activeDomains.where((d) => !excludeDomainIds.contains(d.id)).toList();
  if (domains.isEmpty) return 0;
  final until = DateTime.tryParse(untilYmd);
  final selected = <String>{
    for (final d in domains)
      if (logic.isDomainResting(d.id)) d.id
  };
  final picked = await showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setSt) {
      final cs = Theme.of(c).colorScheme;
      // Liste des domaines défilante, boutons toujours visibles en bas.
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .85),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(title ?? 'Mettre en veille${until == null ? '' : ' jusqu\'au ${dayMonthFr(until)}'} ?',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                  'Un domaine en veille ne compte plus dans Ma semaine, sort de la carte du moment et n\'est pas programmé. '
                  'Ses séries de routine sont gelées : un jour en veille ne casse rien et ne compte pas ; une routine faite quand même compte.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final d in domains)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(d.id),
                    title: Text(d.name),
                    subtitle: _frozenLabel(logic, d.id) == null ? null : Text(_frozenLabel(logic, d.id)!),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setSt(() => v == true ? selected.add(d.id) : selected.remove(d.id)),
                  ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Pas de veille')),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(c, selected),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    child: Text(selected.isEmpty ? 'Valider' : 'Mettre en veille · ${selected.length}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
    }),
  );
  if (picked == null) return 0;
  var n = 0;
  for (final d in domains) {
    final was = logic.isDomainResting(d.id);
    final now = picked.contains(d.id);
    if (now) {
      await sync.setRestDomain(d.id, untilYmd);
      logic.restDomains = {...logic.restDomains, d.id: untilYmd};
      logic.restPeriods = withRestSet(logic.restPeriods, d.id, logic.livedTodayYmd, untilYmd);
      n++;
    } else if (was) {
      await sync.setRestDomain(d.id, null);
      logic.restDomains = {...logic.restDomains}..remove(d.id);
      logic.restPeriods = withRestLifted(logic.restPeriods, d.id, logic.livedTodayYmd);
    }
  }
  await sync.setRestPeriods(logic.restPeriods.map((p) => p.toJson()).toList());
  logic.onChange();
  return n;
}

/// « 3 séries gelées : Méditation 34 j, Pompes 12 j… » : les séries en cours
/// des routines quotidiennes du domaine.
String? _frozenLabel(AppLogic logic, String domainId) {
  final now = DateTime.now();
  final series = <(String, int)>[];
  for (final a in logic.state.activeActivities) {
    if (a.domainId != domainId || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    final s = routineSeries(a, logic.state.habitHits, now, dayStartMin: logic.dayStartMin, bridged: logic.bridgedOf(a.id), frozen: logic.frozenOf(a.id));
    if (s.current > 0) series.add((a.name, s.current));
  }
  if (series.isEmpty) return null;
  series.sort((a, b) => b.$2.compareTo(a.$2));
  final names = series.take(3).map((x) => '${x.$1} ${x.$2} j').join(', ');
  return '${series.length} série${series.length > 1 ? 's' : ''} gelée${series.length > 1 ? 's' : ''} : $names${series.length > 3 ? '…' : ''}';
}

/// Lever la veille d'un domaine (un tap).
Future<void> liftRest(AppLogic logic, FirestoreSync sync, String domainId) async {
  await sync.setRestDomain(domainId, null);
  logic.restDomains = {...logic.restDomains}..remove(domainId);
  logic.restPeriods = withRestLifted(logic.restPeriods, domainId, logic.livedTodayYmd);
  await sync.setRestPeriods(logic.restPeriods.map((p) => p.toJson()).toList());
  logic.onChange();
}
