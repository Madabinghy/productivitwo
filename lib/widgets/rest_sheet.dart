import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/coups.dart' show dayMonthFr;

/// Veille de domaines (Modes et coups § 2.3) : cases cochables, « jusqu'au … »
/// (fin du coup, ou ce soir pour un deep work). Un domaine en veille : ses
/// minimums ne comptent plus, ses actions sortent de la carte du moment,
/// `plan_day` ne programme rien dessus. Se lève d'un tap. Retourne le nombre
/// de domaines mis en veille.
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
  final selected = <String>{for (final d in domains) if (logic.isDomainResting(d.id)) d.id};
  final picked = await showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, setSt) {
      final cs = Theme.of(c).colorScheme;
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(title ?? 'Mettre en veille${until == null ? '' : ' jusqu\'au ${dayMonthFr(until)}'} ?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Un domaine en veille ne compte plus dans Ma semaine, sort de la carte du moment et n\'est pas programmé. Les routines « toute la journée » restent.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
          ),
          for (final d in domains)
            CheckboxListTile(
              dense: true,
              value: selected.contains(d.id),
              title: Text(d.name),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setSt(() => v == true ? selected.add(d.id) : selected.remove(d.id)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Pas de veille')),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(c, selected),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: Text(selected.isEmpty ? 'Valider' : 'Mettre en veille · ${selected.length}'),
              ),
            ]),
          ),
        ]),
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
      n++;
    } else if (was) {
      await sync.setRestDomain(d.id, null);
      logic.restDomains = {...logic.restDomains}..remove(d.id);
    }
  }
  logic.onChange();
  return n;
}

/// Lever la veille d'un domaine (un tap).
Future<void> liftRest(AppLogic logic, FirestoreSync sync, String domainId) async {
  await sync.setRestDomain(domainId, null);
  logic.restDomains = {...logic.restDomains}..remove(domainId);
  logic.onChange();
}
