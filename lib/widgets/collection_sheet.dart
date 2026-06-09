import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';

/// Collection (Phase 1) : tout ce que le user a trouvé en explorant les cartes
/// d'expédition (animaux communs + butins rares). Les non-trouvés en silhouette.
Future<void> showCollectionSheet(BuildContext context, AppLogic logic) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CollectionSheet(logic: logic),
  );
}

class _CollectionSheet extends StatelessWidget {
  final AppLogic logic;
  const _CollectionSheet({required this.logic});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final found = logic.state.collection.toSet();
    final catalog = overworldCollectibles;
    final foundCount = catalog.where((c) => found.contains(c.id)).length;

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
            const Text('Collection',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$foundCount / ${catalog.length}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface.withOpacity(.6))),
          ]),
          const SizedBox(height: 4),
          Text('Trouve animaux et trésors en explorant les cartes d\'expédition.',
              style:
                  TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5))),
          const SizedBox(height: 16),
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
                  cs: cs,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectibleCell extends StatelessWidget {
  final bool found, rare;
  final String emoji, name;
  final ColorScheme cs;
  const _CollectibleCell({
    required this.found,
    required this.rare,
    required this.emoji,
    required this.name,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final gold = const Color(0xFFD4A017);
    return Container(
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
    );
  }
}
