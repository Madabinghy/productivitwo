import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/card_seen_store.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart' show BadgeState;
import 'package:productivitwo_v1/widgets/badge_card.dart';
import 'package:productivitwo_v1/utils/collection_badges.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/badge_painter.dart';

/// Badges de collection (2026-11-01) : l'écusson au métal du palier, monté
/// sur sa plaque gravée (nom, palier, chiffre). Logique :
/// `utils/collection_badges.dart`.
BadgeMetal? metalOf(CardRarity r) => switch (r) {
      CardRarity.bronze => BadgeMetal.bronze,
      CardRarity.argent => BadgeMetal.argent,
      CardRarity.or => BadgeMetal.or,
      CardRarity.legend => BadgeMetal.legend,
      CardRarity.none => null,
    };

class CollectionShield extends StatelessWidget {
  final CollectionBadge badge;
  final double size;
  const CollectionShield({super.key, required this.badge, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return Semantics(
      label: '${b.name}${b.acquired ? ', ${b.palier}' : ', pas encore obtenu'}',
      child: CustomPaint(
        size: Size.square(size),
        painter: BadgePainter(
          symbol: b.symbol,
          acquired: b.acquired,
          levels: b.ribbon != null ? 1 : b.tiers.length,
          level: b.level,
          progress: b.acquired ? null : b.progress,
          label: b.ribbon ?? '',
          metal: metalOf(b.metal),
        ),
      ),
    );
  }
}

/// La plaque : fond de métal vissé, l'écusson en haut, le texte gravé dessous.
class CollectionPlaque extends StatelessWidget {
  final CollectionBadge badge;
  final double width;
  final VoidCallback? onTap;
  const CollectionPlaque({super.key, required this.badge, this.width = 160, this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = badge;
    final m = b.acquired ? metalOf(b.metal) : null;
    // Plaque sombre teintée du métal, liseré et gravure au métal : l'écusson ressort.
    final ink = m?.top ?? kBText3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: m == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(m.bottom, Colors.black, .45)!, Color.lerp(m.bottom, Colors.black, .72)!],
                ),
          color: m == null ? kBSurface : null,
          border: Border.all(color: m == null ? kBLine : m.top.withValues(alpha: .75), width: m == null ? 1 : 2),
        ),
        child: Stack(children: [
          if (m != null) ...[
            const Positioned(left: 0, top: 0, child: _Screw()),
            const Positioned(right: 0, top: 0, child: _Screw()),
          ],
          Column(children: [
            CollectionShield(badge: b, size: width * .64),
            const SizedBox(height: 4),
            SizedBox(
              height: 24,
              child: Center(
                child: Text(b.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, height: 1.15, letterSpacing: .9, fontWeight: FontWeight.w800, color: ink.withValues(alpha: .8))),
              ),
            ),
            const SizedBox(height: 2),
            Text(b.palier, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: m == null ? kBText2 : ink)),
            Text(b.figure, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: m == null ? kBText3 : ink, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ]),
      ),
    );
  }
}

class _Screw extends StatelessWidget {
  const _Screw();
  @override
  Widget build(BuildContext context) =>
      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .28)));
}

/// La fiche d'un badge de collection : l'écusson en grand, où on en est, la
/// règle, ce qu'il manque.
/// [cards] = les cartes du badge (`cardsOfCollection`), en grille sous la
/// jauge ; tap = [onCard] (fiche de la carte).
Future<void> showCollectionBadgeSheet(BuildContext context, CollectionBadge b,
    {List<BadgeState> cards = const [], void Function(BadgeState card)? onCard}) {
  final rule = switch (b.id) {
    'collector' => 'Chaque carte rapporte des points selon son cadre : bronze 1 · argent 2 · or 3 · légendaire 5. Une carte qui monte de cadre rapporte la différence. Paliers : ${kCollectorTiers.join(' · ')} pts.',
    'gold-case' => 'Les cartes en or ou légendaires. Paliers : ${kGoldCaseTiers.join(' · ')}.',
    'legend' => 'Les cartes légendaires (le dernier palier d’un badge). Paliers : ${kLegendTiers.join(' · ')}.',
    _ => 'Toutes les cartes de la famille gagnées : écusson argent. Toutes en or ou mieux : il passe en or.',
  };
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: kBSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(children: [
          CollectionShield(badge: b, size: 150),
          const SizedBox(height: 8),
          const Text('BADGE DE COLLECTION', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: kBText3)),
          Text(b.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kBText)),
          const SizedBox(height: 4),
          Text('${b.palier} · ${b.figure}', style: const TextStyle(fontSize: 15, color: kBText2)),
          if (!b.complete) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(value: b.progress, minHeight: 8, backgroundColor: kBadgeGaugeTrack, color: kBadgeBrass),
            ),
            const SizedBox(height: 6),
            Text(b.nextLine, style: const TextStyle(fontSize: 13, color: kBText3)),
          ],
          if (b.missing.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(b.level == 0 ? 'IL MANQUE · ${b.missing.length}' : 'PAS ENCORE EN OR · ${b.missing.length}',
                  style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: kBText3)),
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text(b.missing.join(' · '), style: const TextStyle(fontSize: 14, height: 1.4, color: kBText))),
          ],
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  b.id.startsWith('family-')
                      ? 'LES CARTES · ${cards.where((c) => c.acquired).length} / ${cards.length}'
                      : 'LES CARTES · ${cards.length}',
                  style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: kBText3)),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (ctx, c) {
              final w = ((c.maxWidth - 2 * 10) / 3).floorToDouble();
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (final card in cards)
                  GestureDetector(
                    onTap: onCard == null ? null : () => onCard(card),
                    child: BadgeCardView(state: card, width: w),
                  ),
              ]);
            }),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kBBg, borderRadius: BorderRadius.circular(12)),
            child: Text(rule, style: const TextStyle(fontSize: 13, height: 1.4, color: kBText3)),
          ),
        ]),
      ),
    ),
  );
}

/// « Un badge tombe » (badges de collection, lot 2) : l'écusson en grand,
/// des rayons qui tournent derrière, une fois par palier. Renvoie vrai si
/// « Voir l'album » a été choisi ; tout ce qui a été montré passe vu.
Future<bool> showCollectionDrop(BuildContext context, List<CollectionBadge> badges) async {
  final r = await Navigator.of(context).push<bool>(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    pageBuilder: (_, __, ___) => CollectionDropScreen(badges: badges),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
  CardSeenStore.markCollectionSeen(badges);
  return r ?? false;
}

class CollectionDropScreen extends StatefulWidget {
  final List<CollectionBadge> badges;
  const CollectionDropScreen({super.key, required this.badges});

  @override
  State<CollectionDropScreen> createState() => _CollectionDropScreenState();
}

class _CollectionDropScreenState extends State<CollectionDropScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  int _i = 0;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.badges[_i];
    final m = metalOf(b.metal) ?? BadgeMetal.or;
    final last = _i + 1 >= widget.badges.length;
    final w = MediaQuery.sizeOf(context).width;
    final size = w * .5 > 220 ? 220.0 : w * .5;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(children: [
            Row(children: [
              Text(widget.badges.length > 1 ? 'BADGE ${_i + 1} / ${widget.badges.length}' : 'UN BADGE TOMBE',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white70)),
              const Spacer(),
              IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop(false)),
            ]),
            Expanded(
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  RotationTransition(
                    turns: _spin,
                    child: CustomPaint(size: Size.square(size * 1.6), painter: _RaysPainter(m.top)),
                  ),
                  CollectionShield(badge: b, size: size),
                ]),
              ),
            ),
            const Text('BADGE DE COLLECTION', style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Colors.white60)),
            const SizedBox(height: 4),
            Text(b.ribbon == null ? '${b.name} ${roman(b.level)}' : b.name,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text('${b.figure} · ${b.nextLine}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: m.top)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => last ? Navigator.of(context).pop(false) : setState(() => _i++),
                style: FilledButton.styleFrom(backgroundColor: m.top, foregroundColor: m.ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(last ? 'Sur l’étagère' : 'Badge suivant', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            if (last) TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Voir l’album', style: TextStyle(color: Colors.white70))),
          ]),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  final Color color;
  const _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final p = Paint()
      ..shader = RadialGradient(colors: [color.withValues(alpha: .35), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    for (var i = 0; i < 18; i++) {
      final a0 = i * 2 * math.pi / 18;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
        ..lineTo(c.dx + r * math.cos(a0 + .14), c.dy + r * math.sin(a0 + .14))
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}
