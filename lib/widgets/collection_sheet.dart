import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/widgets/expedition_map_game.dart';

/// Mes cartes : hub des cartes d'expédition. En tête, la carte en cours (qu'on
/// peut explorer/chasser) ; en dessous, sa collection (animaux + trésors), les
/// non-obtenus en silhouette. La chasse par carte (farming) viendra enrichir ça.
Future<void> showCollectionSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CollectionSheet(logic: logic, sync: sync),
  );
}

class _CollectionSheet extends StatelessWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _CollectionSheet({required this.logic, required this.sync});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final found = logic.state.collection.toSet();
    final meta = logic.state.collectionMeta;
    final catalog = overworldCollectibles;
    final foundCount = catalog.where((c) => found.contains(c.id)).length;
    final mapLevel = logic.effectiveLevel();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(children: [
            const Text('🗺️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            const Text('Mes cartes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$foundCount / ${catalog.length}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface.withOpacity(.6))),
          ]),
          const SizedBox(height: 12),
          // Carte en cours : on peut aller l'explorer / la chasser.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFFD4A017).withOpacity(.18),
                cs.surfaceContainerHighest.withOpacity(.35),
              ]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD4A017).withOpacity(.4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Carte en cours · Niveau $mapLevel',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('Explore, affronte ses nuisibles, ramasse son butin.',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(.6))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    foregroundColor: Colors.white),
                icon: const Text('🗺️', style: TextStyle(fontSize: 15)),
                label: const Text('Explorer'),
                onPressed: () {
                  Navigator.pop(context);
                  showExpeditionGame(context, logic, sync);
                },
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Text('Collection de la carte',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface.withOpacity(.7))),
          const SizedBox(height: 4),
          Text('Animaux et trésors trouvés en explorant. Les manquants sont en silhouette.',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .9,
            children: [
              for (final c in catalog)
                _CollectibleCell(
                  found: found.contains(c.id),
                  emoji: c.emoji,
                  name: c.name,
                  rare: c.rare,
                  provenance: found.contains(c.id) ? meta[c.id] : null,
                  cs: cs,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmtProvenance(String raw) {
  const mois = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'août', 'sep', 'oct', 'nov', 'déc'];
  final parts = raw.split('|');
  final ymd = parts[0];
  final text = parts.length > 1 ? parts[1] : '';
  String date = '';
  if (ymd.length == 8) {
    final m = int.tryParse(ymd.substring(4, 6)) ?? 1;
    final d = int.tryParse(ymd.substring(6, 8)) ?? 1;
    date = 'le $d ${mois[(m - 1).clamp(0, 11)]}';
  }
  return 'Obtenu $date · $text';
}

class _CollectibleCell extends StatelessWidget {
  final bool found, rare;
  final String emoji, name;
  final String? provenance;
  final ColorScheme cs;
  const _CollectibleCell({
    required this.found,
    required this.rare,
    required this.emoji,
    required this.name,
    required this.provenance,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFD4A017);
    return GestureDetector(
      onTap: (found && provenance != null)
          ? () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Row(children: [
                    Text(emoji, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name)),
                  ]),
                  content: Text(_fmtProvenance(provenance!)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK')),
                  ],
                ),
              )
          : null,
      child: Container(
      decoration: BoxDecoration(
        color: found
            ? (rare ? gold.withOpacity(.12) : cs.surfaceContainerHighest.withOpacity(.45))
            : cs.surfaceContainerHighest.withOpacity(.25),
        borderRadius: BorderRadius.circular(12),
        border: rare && found ? Border.all(color: gold.withOpacity(.5)) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(found ? emoji : '❓',
              style: TextStyle(
                  fontSize: 30, color: found ? null : cs.onSurface.withOpacity(.3))),
          const SizedBox(height: 6),
          Text(found ? name : '???',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: found ? FontWeight.w600 : FontWeight.normal,
                  color: cs.onSurface.withOpacity(found ? .8 : .4))),
          if (rare)
            Text('rare',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: gold.withOpacity(found ? 1 : .4))),
        ],
      ),
    ));
  }
}
