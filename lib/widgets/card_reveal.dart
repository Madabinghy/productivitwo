import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/card_seen_store.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';

/// Une carte tombe (badges en cartes, lot 2) : les cartes gagnées ou montées
/// de rareté depuis la dernière fois arrivent de dos et se retournent au tap,
/// avec un halo, une seule fois. Carte d'Aujourd'hui « n cartes à retourner »
/// (rouverte d'elle-même une fois par lancement de l'app), écran plein.
class CardRevealPrompt extends StatefulWidget {
  final BadgeCenter? badges;
  final VoidCallback? onOpenAlbum;
  const CardRevealPrompt({super.key, required this.badges, this.onOpenAlbum});

  @override
  State<CardRevealPrompt> createState() => _CardRevealPromptState();
}

class _CardRevealPromptState extends State<CardRevealPrompt> {
  static bool _autoOpened = false;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    CardSeenStore.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _reveal(List<NewCard> cards) async {
    if (_open) return;
    _open = true;
    final album = await showCardReveal(context, cards);
    _open = false;
    if (!mounted) return;
    setState(() {});
    if (album) widget.onOpenAlbum?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bc = widget.badges;
    if (bc == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: bc,
      builder: (context, _) {
        final deck = bc.deck;
        if (deck == null || !CardSeenStore.ready) return const SizedBox.shrink();
        final cards = CardSeenStore.pending(deck);
        if (cards.isEmpty) return const SizedBox.shrink();
        if (!_autoOpened) {
          _autoOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveal(cards);
          });
        }
        final best = cards.last.after;
        final c = rarityInk(best);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: c.withValues(alpha: .10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.withValues(alpha: .55))),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _reveal(cards),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(children: [
                  SizedBox(
                    width: 58,
                    height: 52,
                    child: Stack(children: [
                      for (var i = 0; i < math.min(3, cards.length); i++)
                        Positioned(
                          left: i * 9.0,
                          child: Transform.rotate(
                            angle: (i - 1) * .12,
                            child: BadgeCardView(state: BadgeState(def: cards[i].badge.def, level: 0, value: 0), width: 36),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${cards.length} carte${cards.length > 1 ? 's' : ''} à retourner',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                      Text(best == CardRarity.legend ? 'dont une légendaire' : 'touche pour les découvrir',
                          style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .65))),
                    ]),
                  ),
                  Icon(Icons.style_rounded, color: c),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// L'écran de révélation ; renvoie vrai si « Voir l'album » a été choisi.
/// Toutes les cartes montrées passent vues à la fermeture.
Future<bool> showCardReveal(BuildContext context, List<NewCard> cards) async {
  final r = await Navigator.of(context).push<bool>(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    pageBuilder: (_, __, ___) => CardRevealScreen(cards: cards),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
  CardSeenStore.markSeen(cards.map((c) => c.badge));
  return r ?? false;
}

class CardRevealScreen extends StatefulWidget {
  final List<NewCard> cards;
  const CardRevealScreen({super.key, required this.cards});

  @override
  State<CardRevealScreen> createState() => _CardRevealScreenState();
}

class _CardRevealScreenState extends State<CardRevealScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  int _i = 0;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _next() {
    if (_i + 1 >= widget.cards.length) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _i++);
    _flip.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cards[_i];
    final b = c.badge;
    final r = c.after;
    final ink = rarityInk(r);
    final w = math.min(MediaQuery.sizeOf(context).width * .62, 260.0);
    final revealed = _flip.value >= .5;
    final next = b.nextTarget;
    final last = _i + 1 >= widget.cards.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(children: [
            Row(children: [
              Text(widget.cards.length > 1 ? 'CARTE ${_i + 1} / ${widget.cards.length}' : 'UNE CARTE TOMBE',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white70)),
              const Spacer(),
              IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop(false)),
            ]),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    if (_flip.isAnimating) return;
                    if (_flip.value < .5) _flip.forward().then((_) => mounted ? setState(() {}) : null);
                  },
                  child: AnimatedBuilder(
                    animation: _flip,
                    builder: (_, __) {
                      final t = Curves.easeOutBack.transform(_flip.value.clamp(0.0, 1.0));
                      final angle = t * math.pi;
                      final front = angle > math.pi / 2;
                      return Stack(alignment: Alignment.center, children: [
                        Opacity(
                          opacity: (_flip.value * 1.4 - .4).clamp(0.0, 1.0),
                          child: Container(
                            width: w * 1.7,
                            height: w * 1.7,
                            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [ink.withValues(alpha: .38), ink.withValues(alpha: 0)])),
                          ),
                        ),
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .0012)
                            ..rotateY(angle),
                          child: front
                              ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: BadgeCardView(state: b, width: w))
                              : BadgeCardView(state: BadgeState(def: b.def, level: 0, value: 0), width: w),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: revealed ? 1 : 0,
              child: Column(children: [
                Text('Carte ${rarityLabel(r).toLowerCase()} · ${b.def.name}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '${newCardLine(c)}${next == null ? ' · tous les paliers' : ' · prochain palier à ${fmtInt(next)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: ink),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: revealed ? _next : () => _flip.forward().then((_) => mounted ? setState(() {}) : null),
                style: FilledButton.styleFrom(backgroundColor: revealed ? ink : Colors.white24, foregroundColor: const Color(0xFF1A1F12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text(!revealed ? 'Retourner' : (last ? 'Fermer' : 'Carte suivante'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            if (revealed && last)
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Voir l’album', style: TextStyle(color: Colors.white70))),
          ]),
        ),
      ),
    );
  }
}
