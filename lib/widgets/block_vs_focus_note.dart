import 'package:flutter/material.dart';

/// Ce qu'on choisit en posant un bloc ou en visant un jour (retour user
/// 2026-10-30) : un bloc est un ENGAGEMENT qui pèse sur la journée parfaite et
/// les badges tant qu'il n'est ni fait ni retiré ; un jour visé n'est qu'une
/// intention, proposée ce jour-là, sans conséquence si elle n'est pas faite.
/// Replié par défaut : une ligne, tap = la comparaison.
enum BlockVsFocusSide { block, focus }

class BlockVsFocusNote extends StatefulWidget {
  final BlockVsFocusSide side;
  const BlockVsFocusNote({super.key, required this.side});

  @override
  State<BlockVsFocusNote> createState() => _BlockVsFocusNoteState();
}

class _BlockVsFocusNoteState extends State<BlockVsFocusNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text3 = cs.onSurface.withValues(alpha: .6);
    final block = widget.side == BlockVsFocusSide.block;
    final headline = block
        ? 'Un bloc est un engagement : non fait, il compte contre ta journée.'
        : 'Une intention : proposée ce jour-là, sans conséquence si elle attend.';
    Widget part(IconData icon, String title, List<String> lines, {required bool here}) => Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: here ? cs.onSurface.withValues(alpha: .07) : null,
            border: Border.all(color: cs.onSurface.withValues(alpha: here ? .16 : .08)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: .8)),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
              if (here)
                Text('ce que tu fais', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: text3)),
            ]),
            const SizedBox(height: 4),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('· $l', style: TextStyle(fontSize: 12, height: 1.3, color: text3)),
              ),
          ]),
        );
    final blockPart = part(
      Icons.event_available_rounded,
      'Bloc dans le programme',
      const [
        'Une heure réservée : c\'est un engagement.',
        'Il compte pour la journée parfaite et pour les badges.',
        'Non fait, il pèse jusqu\'à ce que tu le fasses, le déplaces ou le supprimes.',
      ],
      here: block,
    );
    final focusPart = part(
      Icons.wb_sunny_outlined,
      'Jour visé',
      const [
        'Une intention : l\'avoir sous la main ce jour-là.',
        'Proposée en tête d\'Actions et des blocs de son activité.',
        'Pas faite ? Rien n\'est perdu : elle passe « à re-viser », jamais en retard.',
      ],
      here: !block,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: text3),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$headline '),
                  TextSpan(
                    text: _open ? 'Masquer' : (block ? 'Bloc ou jour visé ?' : 'Jour visé ou bloc ?'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ]),
                style: TextStyle(fontSize: 12, height: 1.35, color: text3),
              ),
            ),
          ]),
        ),
      ),
      if (_open) ...[
        const SizedBox(height: 4),
        block ? blockPart : focusPart,
        const SizedBox(height: 6),
        block ? focusPart : blockPart,
      ],
    ]);
  }
}
