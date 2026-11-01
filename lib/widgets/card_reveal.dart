import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/card_seen_store.dart';
import 'package:productivitwo_v1/utils/badge_cards.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/widgets/badge_card.dart';
import 'package:productivitwo_v1/utils/collection_badges.dart';
import 'package:productivitwo_v1/widgets/collection_badge_view.dart';

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

  /// « Ouvre ta collection » : les cartes gagnées avant les cartes, une fois.
  Future<void> _openPack(List<NewCard> pack) async {
    if (_open) return;
    _open = true;
    final deck = widget.badges?.deck;
    final album = await showCardReveal(context, pack, points: deck == null ? null : collectionPoints(deck), pack: true);
    if (deck != null) CardSeenStore.markOpened(deck);
    _open = false;
    if (!mounted) return;
    setState(() {});
    if (album) widget.onOpenAlbum?.call();
  }

  /// « Ranger dans l'album » : les cartes qui ont passé un palier se
  /// retournent, puis les badges de collection ; la récolte est faite.
  Future<void> _collect() async {
    final bc = widget.badges;
    final deck = bc?.deck;
    if (bc == null || deck == null) return;
    final cards = CardSeenStore.pending(deck);
    if (cards.isNotEmpty || CardSeenStore.pendingCollection(deck).isNotEmpty) {
      await _reveal(cards);
    }
    CardSeenStore.markHarvested(deck, bc.logic.livedTodayYmd);
    if (mounted) setState(() {});
  }

  Future<void> _reveal(List<NewCard> cards) async {
    if (_open) return;
    _open = true;
    final deck = widget.badges?.deck;
    var album = false;
    if (cards.isNotEmpty) album = await showCardReveal(context, cards, points: deck == null ? null : collectionPoints(deck));
    // Puis les badges de collection qui viennent de tomber (badges de collection, lot 2).
    if (mounted && deck != null) {
      final drops = CardSeenStore.pendingCollection(deck);
      if (drops.isNotEmpty) {
        final a = await showCollectionDrop(context, drops);
        album = album || a;
      }
    }
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
        final pack = CardSeenStore.packPending(deck);
        if (pack.isNotEmpty) return _packPrompt(context, pack);
        final harvest = CardSeenStore.harvestPending(deck, bc.logic.livedTodayYmd);
        if (harvest.isNotEmpty) return _harvestPrompt(context, harvest);
        final cards = CardSeenStore.pending(deck);
        final drops = CardSeenStore.pendingCollection(deck);
        if (cards.isEmpty && drops.isEmpty) return const SizedBox.shrink();
        if (!_autoOpened) {
          _autoOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveal(cards);
          });
        }
        final best = cards.isEmpty ? drops.last.metal : cards.last.after;
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
                      if (cards.isEmpty) CollectionShield(badge: drops.last, size: 52),
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
                      Text(cards.isEmpty ? 'Un badge à poser sur l’étagère' : '${cards.length} carte${cards.length > 1 ? 's' : ''} à retourner',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                      Text(cards.isEmpty ? drops.last.name : (best == CardRarity.legend ? 'dont une légendaire' : 'touche pour les découvrir'),
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

/// La carte « Ouvre ta collection » (paquet scellé, éventail, compte) et
/// « Ta récolte d'hier ».
extension on _CardRevealPromptState {
  Widget _harvestPrompt(BuildContext context, List<HarvestItem> items) {
    const gold = Color(0xFFFFD36A);
    final cs = Theme.of(context).colorScheme;
    final pts = items.fold<int>(0, (s, h) => s + cardPoints(rarityOf(h.badge)) - cardPoints(h.rarityBefore));
    final fresh = items.where((h) => h.levelBefore == 0 && h.badge.acquired).length;
    String measure(BadgeState b) {
      if (b.complete) return 'complète';
      if (b.showGauge) return '${fmtInt(b.value.round())} / ${fmtInt(b.nextTarget!)}${b.def.unit.isEmpty ? '' : ' ${b.def.unit}'}';
      return b.acquired ? rarityLabel(rarityOf(b)).toLowerCase() : 'pas encore';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: gold.withValues(alpha: .08), borderRadius: BorderRadius.circular(16), border: Border.all(color: gold.withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Ta récolte d’hier', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface))),
            if (pts > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(99), border: Border.all(color: gold.withValues(alpha: .5))),
                child: Text('+$pts pt${pts > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: gold)),
              ),
          ]),
          Text('${items.length} carte${items.length > 1 ? 's ont' : ' a'} avancé${fresh > 0 ? ' · $fresh nouvelle${fresh > 1 ? 's' : ''}' : ''}',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .65))),
          const SizedBox(height: 8),
          for (final h in items.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                BadgeCardView(state: h.badge, width: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h.badge.def.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    Text(measure(h.badge), style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
                  ]),
                ),
                Text(harvestLabel(h), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: h.tierUp ? gold : const Color(0xFF3DDC84))),
              ]),
            ),
          if (items.length > 4)
            Text('+ ${items.length - 4} autre${items.length - 4 > 1 ? 's' : ''}', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .55))),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _collect,
              style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: const Color(0xFF2A2312), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(items.any((h) => h.tierUp) ? 'Ranger dans l’album · retourner' : 'Ranger dans l’album', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _packPrompt(BuildContext context, List<NewCard> pack) {
    const gold = Color(0xFFFFD36A);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: gold.withValues(alpha: .10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: gold, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPack(pack),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              SizedBox(
                width: 76,
                height: 58,
                child: Stack(children: [
                  for (var i = 0; i < math.min(4, pack.length); i++)
                    Positioned(
                      left: i * 11.0,
                      child: Transform.rotate(angle: (i - 1.5) * .12, child: BadgeCardView(state: pack[pack.length - 1 - i].badge, width: 38)),
                    ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ouvre ta collection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  Text('${pack.length} carte${pack.length > 1 ? 's' : ''} déjà gagnée${pack.length > 1 ? 's' : ''}, jamais ouvertes',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .65))),
                ]),
              ),
              const Icon(Icons.inventory_2_outlined, color: gold),
            ]),
          ),
        ),
      ),
    );
  }
}

/// L'écran de révélation ; renvoie vrai si « Voir l'album » a été choisi.
/// Toutes les cartes montrées passent vues à la fermeture.
/// [points] = points de collection actuels (toutes les cartes comprises) :
/// chaque carte montre ce qu'elle rapporte et où en est Collectionneur.
Future<bool> showCardReveal(BuildContext context, List<NewCard> cards, {int? points, bool pack = false}) async {
  final r = await Navigator.of(context).push<bool>(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    pageBuilder: (_, __, ___) => CardRevealScreen(cards: cards, points: points, pack: pack),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
  CardSeenStore.markSeen(cards.map((c) => c.badge));
  return r ?? false;
}

class CardRevealScreen extends StatefulWidget {
  final List<NewCard> cards;
  final int? points;
  /// Ouverture de la collection : « Tout retourner » et un récapitulatif en grille.
  final bool pack;
  const CardRevealScreen({super.key, required this.cards, this.points, this.pack = false});

  @override
  State<CardRevealScreen> createState() => _CardRevealScreenState();
}

class _CardRevealScreenState extends State<CardRevealScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  int _i = 0;
  bool _all = false;

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  int _gain(NewCard c) => cardPoints(c.after) - cardPoints(c.before);

  /// « Collectionneur III · 43 / 50 pts » après cette carte (les suivantes pas encore comptées).
  String? _collectorLine() {
    final total = widget.points;
    if (total == null) return null;
    final later = widget.cards.skip(_i + 1).fold<int>(0, (s, c) => s + _gain(c));
    final now = total - later;
    final level = kCollectorTiers.where((t) => now >= t).length;
    if (level >= kCollectorTiers.length) return 'Collectionneur · $now pts · tous les paliers';
    return 'Collectionneur ${roman(level + 1)} · $now / ${kCollectorTiers[level]} pts';
  }

  void _next() {
    if (_i + 1 >= widget.cards.length) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _i++);
    _flip.value = 0;
  }

  /// Toutes les cartes d'un coup (ouverture de la collection).
  Widget _allView() {
    final w = (MediaQuery.sizeOf(context).width - 40 - 3 * 8) / 4;
    final pts = widget.points;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('TA COLLECTION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white70)),
              const Spacer(),
              IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop(false)),
            ]),
            Text('${widget.cards.length} cartes${pts == null ? '' : ' · $pts pts'}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in widget.cards.reversed) BadgeCardView(state: c.badge, width: w),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFD36A), foregroundColor: const Color(0xFF2A2312), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('Ranger dans l’album', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_all) return _allView();
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
              Expanded(
                child: Text(widget.pack ? 'TA COLLECTION · ${_i + 1} / ${widget.cards.length}' : (widget.cards.length > 1 ? 'CARTE ${_i + 1} / ${widget.cards.length}' : 'UNE CARTE TOMBE'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white70)),
              ),
              if (widget.cards.length > 3 && _i + 1 < widget.cards.length)
                TextButton(onPressed: () => setState(() => _all = true), child: const Text('Tout retourner', style: TextStyle(color: Colors.white70))),
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
                if (_gain(c) > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: ink.withValues(alpha: .14), borderRadius: BorderRadius.circular(99), border: Border.all(color: ink.withValues(alpha: .5))),
                    child: Text('+${_gain(c)} pt${_gain(c) > 1 ? 's' : ''}${c.upgrade ? ' · ${rarityLabel(c.before).toLowerCase()} → ${rarityLabel(c.after).toLowerCase()}' : ''}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink)),
                  ),
                  if (_collectorLine() case final line?) ...[
                    const SizedBox(height: 6),
                    Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  ],
                ],
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
