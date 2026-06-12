import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/territory.dart';
import 'package:productivitwo_v1/web/invasion_defense_sheet.dart';

// Sous-tranche A : rend la map de territoire PERSISTÉE (château + 4 grottes +
// brouillard), lue depuis `territories/{uid}`. La grille se régénère depuis la
// seed (déterministe). Pas encore de gameplay (bot/siège = tranches C/D).

const _kBg = Color(0xFF0E0A0A);
const _kCard = Color(0xFF160C0C);
const _kBlue = Color(0xFF3B82F6); // grottes à moi
const _kGold = Color(0xFFD4A017); // château
const _kEnemy = Color(0xFFFF2B2B); // grottes prises (ennemi)

Future<void> showTerritorySheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(.65),
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: _TerritoryView(logic: logic, sync: sync),
      ),
    ),
  );
}

class _TerritoryView extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _TerritoryView({required this.logic, required this.sync});

  @override
  State<_TerritoryView> createState() => _TerritoryViewState();
}

class _TerritoryViewState extends State<_TerritoryView> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = widget.sync.ensureTerritory('Toi');
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.sync.uid;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        child: Row(children: [
          const Text('🗺️ Mon territoire',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Flexible(
        child: FutureBuilder<void>(
          future: _ready,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return _loader();
            return StreamBuilder<Territory?>(
              stream: widget.sync.streamTerritory(me ?? ''),
              builder: (context, s) {
                final t = s.data;
                if (t == null) return _loader();
                return _content(t, me);
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _loader() => const Center(
      child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _kBlue)));

  Widget _content(Territory t, String? me) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusBar(t),
        const SizedBox(height: 12),
        _board(t, me),
        const SizedBox(height: 8),
        Text(
          'Touche une de tes grottes 🕳️ pour entraîner son boss : le repousser '
          'le fait monter d\'un niveau (ta défense + ton niveau de map). Ça dépense '
          'tes flèches 🏹 — plus le boss est haut, plus c\'est dur.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(.45), fontSize: 11),
        ),
        const SizedBox(height: 12),
        _legend(),
      ],
    );
  }

  // Lever une grotte : combat partie-minute contre son boss ; victoire = +1 niveau.
  Future<void> _fightCave(Territory t, TerritoryCave cave, String? me) async {
    if (cave.ownerUid != me) {
      _toast('Cette grotte ne t\'appartient pas', _kEnemy);
      return;
    }
    final winner = await showCaveFight(context, widget.logic, widget.sync,
        blueLevel: cave.blueLevel, title: 'Grotte ${cave.id.toUpperCase()} — niv. ${cave.blueLevel}');
    if (!mounted || winner != 'defender') return;
    // Persiste +1 niveau (le stream rafraîchit l'affichage).
    final next = t.caves
        .map((c) => c.id == cave.id
            ? c.copyWith(blueLevel: c.blueLevel + 1)
            : c)
        .toList();
    await widget.sync.saveTerritory(t.copyWith(caves: next));
    if (!mounted) return;
    _toast('🕳️ Grotte ${cave.id.toUpperCase()} montée → niveau ${cave.blueLevel + 1}',
        _kBlue);
  }

  void _toast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
  }

  Widget _statusBar(Territory t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Niveau de map',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text('${t.level}',
              style: const TextStyle(
                  color: _kBlue, fontSize: 22, fontWeight: FontWeight.w900)),
          Text('Σ des 4 grottes',
              style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 10)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: (t.fog ? Colors.white12 : _kEnemy.withOpacity(.18)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: t.fog ? Colors.white24 : _kEnemy.withOpacity(.6)),
          ),
          child: Text(t.fog ? '🌫️ brouillard' : '⚔️ sous invasion',
              style: TextStyle(
                  color: t.fog ? Colors.white60 : _kEnemy,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5)),
        ),
      ]),
    );
  }

  Widget _board(Territory t, String? me) {
    final grid = generateTerritoryGrid(t);
    // Index des grottes par position pour superposer niveau + propriété.
    final caveAt = <String, TerritoryCave>{
      for (final c in t.caves) '${c.x}_${c.y}': c,
    };
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth / t.cols).clamp(18.0, 52.0);
      final inner = slot - 4;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int y = 0; y < t.rows; y++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (int x = 0; x < t.cols; x++)
                  _cell(grid[y][x], caveAt['${x}_$y'], me, inner,
                      onTapCave: caveAt['${x}_$y'] != null
                          ? () => _fightCave(t, caveAt['${x}_$y']!, me)
                          : null),
              ]),
          ],
        ),
      );
    });
  }

  Widget _cell(TerrTile kind, TerritoryCave? cave, String? me, double inner,
      {VoidCallback? onTapCave}) {
    Color bg;
    Color border;
    Widget? child;
    switch (kind) {
      case TerrTile.wall:
        bg = Colors.white.withOpacity(.03);
        border = Colors.white.withOpacity(.05);
        break;
      case TerrTile.floor:
        bg = Colors.white.withOpacity(.10);
        border = Colors.white.withOpacity(.12);
        break;
      case TerrTile.castle:
        bg = _kGold.withOpacity(.22);
        border = _kGold.withOpacity(.7);
        child = Text('❤️', style: TextStyle(fontSize: inner * 0.5));
        break;
      case TerrTile.cave:
        final mine = cave != null && cave.ownerUid == me;
        final col = mine ? _kBlue : _kEnemy;
        bg = col.withOpacity(.22);
        border = col.withOpacity(.7);
        child = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🕳️', style: TextStyle(fontSize: inner * 0.36)),
            Text('${cave?.blueLevel ?? 0}',
                style: TextStyle(
                    color: col,
                    fontSize: inner * 0.28,
                    fontWeight: FontWeight.w900,
                    height: 1)),
          ],
        );
        break;
    }
    final tile = Container(
      width: inner,
      height: inner,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: child,
    );
    if (onTapCave == null) return tile;
    return GestureDetector(onTap: onTapCave, child: tile);
  }

  Widget _legend() {
    Widget item(String emoji, String label, Color c) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 11.5)),
          ],
        );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item('❤️', 'Château', _kGold),
        item('🕳️', 'Grotte à toi', _kBlue),
        item('🕳️', 'Grotte prise', _kEnemy),
      ],
    );
  }
}
