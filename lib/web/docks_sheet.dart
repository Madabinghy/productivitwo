import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/battle_sim.dart';

// « Mes Docks » — vue d'ensemble de tous mes decks en COLONNES (pour repérer d'un
// coup d'œil). Cartes INDIVIDUELLES (jusqu'à 30/deck), pas un emoji avec ×N.
// Squelette « grande direction » : on affinera (badge « envahie », en mission, etc.).
//   🟢 Vert       : nuisibles récoltés (captures) → attaquer / crafter du rouge.
//   🔴 Rouge      : arsenal rouge (+ combien en mission).
//   🃏 Cartes     : créatures débloquées (collection).
//   🏰 Territoires: maps conquises ailleurs (PvP) — vide en solo.

const _kBg = Color(0xFF0E0A0A);
const _kGreen = Color(0xFF22C55E);
const _kRed = Color(0xFFEF4444);
const _kCardCol = Color(0xFFD4A017);
const _kTerr = Color(0xFF3B82F6);
const int _kMaxCards = 30;

String _tierEmoji(String tier) => switch (tier) {
      'serpent' || 'snake' => '🐍',
      'scorpion' => '🦂',
      _ => '🕷️',
    };

Future<void> showDocksSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(10),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: _DocksView(logic: logic, sync: sync),
      ),
    ),
  );
}

class _DocksView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _DocksView({required this.logic, required this.sync});

  @override
  State<_DocksView> createState() => _DocksViewState();
}

class _DocksViewState extends State<_DocksView> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;

  List<Invasion> _held = [];
  int _enMission = 0;
  bool _loadingInv = true;

  @override
  void initState() {
    super.initState();
    _fetchInvasions();
  }

  Future<void> _fetchInvasions() async {
    try {
      final inv = await sync.fetchInvasionsAsInvader();
      if (!mounted) return;
      setState(() {
        _held = inv.where((i) => i.status == 'held').toList();
        _enMission =
            inv.where((i) => i.status == 'pending' || i.status == 'active').length;
        _loadingInv = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingInv = false);
    }
  }

  // ── Sources de données par deck ────────────────────────────────────────────
  List<String> _greenEmojis() {
    final d = logic.invasionDeckByCapture();
    return [
      for (var i = 0; i < d.spiders; i++) '🕷️',
      for (var i = 0; i < d.scorpions; i++) '🦂',
      for (var i = 0; i < d.serpents; i++) '🐍',
    ];
  }

  List<String> _redEmojis() {
    final out = <String>[];
    for (final tier in const ['serpent', 'scorpion', 'spider']) {
      for (var i = 0; i < logic.redCount(tier); i++) {
        out.add(_tierEmoji(tier));
      }
    }
    return out;
  }

  List<({String emoji, String name})> _collectionCards() {
    final out = <({String emoji, String name})>[];
    for (final id in logic.state.collection) {
      if (id.startsWith('complete_') || id.startsWith('wpn_')) continue;
      final c = collectibleById(id);
      if (c != null) {
        out.add((emoji: c.emoji, name: c.name));
        continue;
      }
      for (final b in GoldEconomy.bestiaryRecipes) {
        if (b.id == id) {
          out.add((emoji: b.emoji, name: b.name));
          break;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
        child: Row(children: [
          const Text('🗃️ Mes Docks',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Expanded(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
          children: [
            _emojiColumn('🟢', 'Vert', 'captures à dépenser', _kGreen,
                _greenEmojis()),
            _redColumn(),
            _cardsColumn(),
            _territoiresColumn(),
          ],
        ),
      ),
    ]);
  }

  // ── Colonnes ────────────────────────────────────────────────────────────────
  Widget _columnFrame(
      String emoji, String title, String subtitle, Color col, Widget body) {
    return Container(
      width: 188,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withOpacity(.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: col.withOpacity(.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(title,
                    style: TextStyle(
                        color: col, fontWeight: FontWeight.w900, fontSize: 14)),
              ]),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withOpacity(.4), fontSize: 10.5)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emojiColumn(String emoji, String title, String subtitle, Color col,
      List<String> items) {
    final shown = items.take(_kMaxCards).toList();
    final overflow = items.length - shown.length;
    return _columnFrame(
      emoji,
      title,
      subtitle,
      col,
      items.isEmpty
          ? _emptyHint('Aucune carte pour l\'instant.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final e in shown) _emojiCard(e, col)],
              ),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('+$overflow de plus',
                      style: TextStyle(
                          color: col.withOpacity(.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
    );
  }

  Widget _redColumn() {
    final reds = _redEmojis();
    final shown = reds.take(_kMaxCards).toList();
    final overflow = reds.length - shown.length;
    return _columnFrame(
      '🔴',
      'Rouge',
      'arsenal d\'invasion',
      _kRed,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _kRed.withOpacity(.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            _loadingInv
                ? '⚔️ en mission : …'
                : '⚔️ en mission : $_enMission',
            style: TextStyle(
                color: _kRed, fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ),
        if (reds.isEmpty)
          _emptyHint('Forge des rouges depuis tes captures vertes.')
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final e in shown) _emojiCard(e, _kRed)],
          ),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('+$overflow de plus',
                  style: TextStyle(
                      color: _kRed.withOpacity(.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
  }

  Widget _cardsColumn() {
    final cards = _collectionCards();
    final shown = cards.take(_kMaxCards).toList();
    final overflow = cards.length - shown.length;
    return _columnFrame(
      '🃏',
      'Cartes',
      'créatures débloquées',
      _kCardCol,
      cards.isEmpty
          ? _emptyHint('Débloque des créatures (chasse, recettes, exploration).')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in shown) _emojiCard(c.emoji, _kCardCol, label: c.name)
                ],
              ),
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('+$overflow de plus',
                      style: TextStyle(
                          color: _kCardCol.withOpacity(.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
    );
  }

  Widget _territoiresColumn() {
    return _columnFrame(
      '🏰',
      'Territoires',
      'maps conquises ailleurs',
      _kTerr,
      _loadingInv
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))))
          : _held.isEmpty
              ? _emptyHint('Aucun territoire conquis (PvP à venir).')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final i in _held)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 7),
                        decoration: BoxDecoration(
                          color: _kTerr.withOpacity(.10),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: _kTerr.withOpacity(.3)),
                        ),
                        child: Row(children: [
                          Text(_tierEmoji(i.redTier),
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('@${i.defenderPseudo}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text('👑',
                              style: TextStyle(fontSize: 13)),
                        ]),
                      ),
                  ],
                ),
    );
  }

  // ── Briques ───────────────────────────────────────────────────────────────
  Widget _emojiCard(String emoji, Color frame, {String? label}) {
    return SizedBox(
      width: 48,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: frame.withOpacity(.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: frame.withOpacity(.55)),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(.6), fontSize: 8.5)),
          ),
      ]),
    );
  }

  Widget _emptyHint(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(msg,
            style: TextStyle(
                color: Colors.white.withOpacity(.4), fontSize: 11, height: 1.3)),
      );
}
