import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';

/// Une pile de cartes (2026-11-03, retour user : séries et compteurs à part des
/// badges, une carte par cadre) : deux dos décalés derrière, la carte de devant
/// au cadre de la pile, l'icône de la sorte et le nombre de cartes dedans.
/// `rarity` null = « En route » (commencées, sans cadre, ne compte pas).
class CardPileView extends StatelessWidget {
  final PileKind kind;
  final CardRarity? rarity;
  final int count;
  final double width;
  const CardPileView({super.key, required this.kind, required this.rarity, required this.count, this.width = 64});

  @override
  Widget build(BuildContext context) {
    final r = rarity;
    final won = r != null && count > 0;
    final h = width * 7 / 5;
    final off = width * .06;
    final radius = width * .12;
    final frame = won ? rarityFrame(r) : const [Color(0xFF2A3A33), Color(0xFF22322B), Color(0xFF2A3A33)];
    final ink = won ? rarityInk(r) : const Color(0xFF6F877B);
    final label = r == null ? 'EN ROUTE' : rarityLabel(r).toUpperCase();
    Widget back(double dx) => Positioned(
          left: dx,
          top: dx,
          child: Container(
            width: width,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: Color.lerp(frame[1], kBSurface, .55),
              border: Border.all(color: kBLine),
            ),
          ),
        );
    return Semantics(
      label: '${kind == PileKind.series ? 'Séries' : 'Compteurs'} ${label.toLowerCase()} : $count carte${count > 1 ? 's' : ''}',
      child: SizedBox(
        width: width + 2 * off,
        height: h + 2 * off,
        child: Stack(children: [
          if (count > 1) back(2 * off),
          if (count > 0) back(off),
          Container(
            width: width,
            height: h,
            padding: EdgeInsets.all(width * .045),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: frame),
            ),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF101A15), borderRadius: BorderRadius.circular(radius - width * .045)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(kind == PileKind.series ? Icons.local_fire_department_rounded : Icons.hourglass_bottom_rounded,
                    size: width * .26, color: ink.withValues(alpha: won || count > 0 ? 1 : .5)),
                Text('$count', style: TextStyle(fontSize: width * .3, height: 1.05, fontWeight: FontWeight.w900, color: count > 0 ? kBText : kBText4)),
                Text(label,
                    maxLines: 1,
                    style: TextStyle(fontSize: (width * .1).clamp(7, 12).toDouble(), letterSpacing: .4, fontWeight: FontWeight.w800, color: ink)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// La pile ouverte : ses cartes en grille ; tap = la fiche de la carte.
Future<void> showCardPileSheet(BuildContext context,
    {required String title, required String subtitle, required List<BadgeState> cards, required void Function(BadgeState) onCard}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: .85,
      minChildSize: .4,
      maxChildSize: .95,
      expand: false,
      builder: (ctx, scroll) => LayoutBuilder(builder: (ctx, c) {
        final w = (c.maxWidth - 40 - 2 * 10) / 3;
        return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13.5, color: kBText3)),
          const SizedBox(height: 16),
          if (cards.isEmpty)
            const Text('Aucune carte ici pour l’instant.', style: TextStyle(fontSize: 14, color: kBText3))
          else
            Wrap(spacing: 10, runSpacing: 12, children: [
              for (final b in cards)
                GestureDetector(
                  onTap: () => onCard(b),
                  child: BadgeCardView(state: b, width: w, footer: cardFooter(b, date: (d) => '${d.day}/${d.month}')),
                ),
            ]),
        ]);
      }),
    ),
  );
}
