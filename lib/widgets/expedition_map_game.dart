import 'dart:math';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart' show expeditionBiome;
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_economy.dart';
import 'package:productivitwo_v1/gold_purchase.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/gold_icon.dart';

/// PROTOTYPE (branche feat/expedition-2d-map) — version « vrai mini-jeu 2D » du
/// déblocage de niveau : une carte à cases qu'on EXPLORE avec un perso qui se
/// déplace (tap sur une case adjacente), brouillard à dissiper, obstacles à
/// franchir avec des outils achetés en boutique (⛏️ pioche / 🔑 clé / 🪏 pelle),
/// trésors à ramasser, drapeau 🏁 à atteindre.
///
/// Différence vs la V1 (chemin à nœuds) : ici **marcher est gratuit**, seuls les
/// obstacles coûtent un outil — plus proche de l'idée d'origine « explorer ».
/// Réutilise le backend : `expeditionCleared` (obstacles cassés + trésors pris),
/// `advanceExpedition` / `completeExpedition`, outils boutique.

const _kGold = Color(0xFFD4A017);
const double _tile = 46;

Future<void> showExpeditionGame(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpeditionGame(logic: logic, sync: sync),
  );
}

enum TileKind { floor, wall, rock, gate, hole, treasure, start, exit }

String? _toolForTile(TileKind k) {
  switch (k) {
    case TileKind.rock:
      return 'pioche';
    case TileKind.gate:
      return 'cle';
    case TileKind.hole:
      return 'pelle';
    default:
      return null;
  }
}

class _Tile {
  final int x, y;
  TileKind kind;
  final int gold;
  _Tile(this.x, this.y, this.kind, {this.gold = 0});
  String get id => '${x}_$y';
}

class _GameMap {
  final int cols, rows, level;
  final List<List<_Tile>> grid;
  final Point<int> start, exit;
  _GameMap(this.cols, this.rows, this.level, this.grid, this.start, this.exit);
  _Tile at(int x, int y) => grid[y][x];
  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
}

/// Génère une carte déterministe (seed = niveau) : chemin garanti start→exit,
/// quelques obstacles sur le chemin, branches latérales avec trésors, le reste = murs.
_GameMap generateMap(int level) {
  final rng = Random(level * 73856093 + 19);
  final cols = 7;
  final rows = (8 + level).clamp(8, 16);
  final grid = [
    for (int y = 0; y < rows; y++)
      [for (int x = 0; x < cols; x++) _Tile(x, y, TileKind.wall)]
  ];

  // Chemin principal : marche biaisée vers le bas.
  var cx = cols ~/ 2;
  var cy = 0;
  final path = <Point<int>>[Point(cx, cy)];
  grid[cy][cx].kind = TileKind.floor;
  while (cy < rows - 1) {
    final goDown = rng.nextInt(10) < 6 || (cx == 0 && cx == cols - 1);
    if (goDown) {
      cy++;
    } else {
      final left = rng.nextBool();
      if (left && cx > 0) {
        cx--;
      } else if (!left && cx < cols - 1) {
        cx++;
      } else {
        cy++;
      }
    }
    grid[cy][cx].kind = TileKind.floor;
    path.add(Point(cx, cy));
  }
  final start = path.first;
  final exit = path.last;
  grid[start.y][start.x].kind = TileKind.start;
  grid[exit.y][exit.x].kind = TileKind.exit;

  // Obstacles sur des cases intérieures du chemin.
  final obstacleCount = (2 + level ~/ 3).clamp(2, 6);
  final interior = path
      .where((p) =>
          (p != start) &&
          (p != exit) &&
          !(p.x == start.x && (p.y - start.y).abs() <= 1))
      .toList();
  interior.shuffle(rng);
  final kinds = [TileKind.rock, TileKind.gate, TileKind.hole];
  for (var i = 0; i < obstacleCount && i < interior.length; i++) {
    final p = interior[i];
    grid[p.y][p.x].kind = kinds[rng.nextInt(3)];
  }

  // Branches latérales (exploration) → trésor au bout.
  final treasureCount = (1 + level ~/ 4).clamp(1, 4);
  var placed = 0;
  final shuffledPath = [...path]..shuffle(rng);
  for (final p in shuffledPath) {
    if (placed >= treasureCount) break;
    // cherche une case murale adjacente libre pour amorcer une branche
    final dirs = [const Point(1, 0), const Point(-1, 0), const Point(0, 1)]
      ..shuffle(rng);
    for (final d in dirs) {
      final bx = p.x + d.x, by = p.y + d.y;
      if (bx < 0 || bx >= cols || by < 0 || by >= rows) continue;
      if (grid[by][bx].kind != TileKind.wall) continue;
      grid[by][bx].kind = TileKind.floor;
      // une case plus loin = trésor si possible, sinon le trésor ici
      final tx = bx + d.x, ty = by + d.y;
      if (bx + d.x >= 0 &&
          bx + d.x < cols &&
          by + d.y >= 0 &&
          by + d.y < rows &&
          grid[ty][tx].kind == TileKind.wall) {
        grid[ty][tx] = _Tile(tx, ty, TileKind.treasure, gold: 6 + rng.nextInt(10));
      } else {
        grid[by][bx] = _Tile(bx, by, TileKind.treasure, gold: 6 + rng.nextInt(10));
      }
      placed++;
      break;
    }
  }

  return _GameMap(cols, rows, level, grid, start, exit);
}

class _ExpeditionGame extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _ExpeditionGame({required this.logic, required this.sync});
  @override
  State<_ExpeditionGame> createState() => _ExpeditionGameState();
}

class _ExpeditionGameState extends State<_ExpeditionGame> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  bool _busy = false;

  int get _level => logic.effectiveLevel() + 1;
  late final _GameMap _map = generateMap(_level);
  late Point<int> _avatar = _map.start;
  final Set<String> _visited = {};

  Set<String> get _cleared =>
      logic.state.expeditionCleared.toSet(); // obstacles cassés + trésors pris

  @override
  void initState() {
    super.initState();
    _reveal(_map.start);
  }

  void _reveal(Point<int> p) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = p.x + dx, ny = p.y + dy;
        if (_map.inBounds(nx, ny)) _visited.add('${nx}_$ny');
      }
    }
  }

  bool _visible(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (_visited.contains('${x + dx}_${y + dy}')) return true;
      }
    }
    return false;
  }

  bool _walkable(_Tile t) {
    switch (t.kind) {
      case TileKind.wall:
        return false;
      case TileKind.rock:
      case TileKind.gate:
      case TileKind.hole:
        return _cleared.contains(t.id); // franchissable une fois cassé
      default:
        return true;
    }
  }

  String _toolLabel(String key) =>
      const {'pioche': '⛏️ pioche', 'cle': '🔑 clé', 'pelle': '🪏 pelle'}[key] ??
      key;

  Future<void> _onTapTile(_Tile t) async {
    if (_busy) return;
    final adj = (t.x - _avatar.x).abs() + (t.y - _avatar.y).abs() == 1;
    if (!adj) return; // déplacement orthogonal d'une case

    final tool = _toolForTile(t.kind);
    final isObstacle = tool != null;

    // Obstacle non franchi → tenter de le casser (sur place).
    if (isObstacle && !_cleared.contains(t.id)) {
      if ((logic.state.goldInventory[tool] ?? 0) < 1) {
        final bought = await offerBuyConsumable(
          context,
          sync,
          itemKey: tool,
          price: GoldEconomy.scaledPrice(
              GoldEconomy.toolBasePrice(tool), logic.effectiveLevel()),
          label: _toolLabel(tool),
          rationale: 'Pour franchir ${_kindLabel(t.kind)}, il te faut un « ${_toolLabel(tool)} ».',
          logic: logic,
        );
        if (!bought) return;
      }
      setState(() => _busy = true);
      final ok = await sync.advanceExpedition(nodeId: t.id, toolKey: tool);
      if (ok) {
        logic.state.goldInventory[tool] =
            (logic.state.goldInventory[tool] ?? 1) - 1;
        logic.state.expeditionCleared.add(t.id);
        logic.onChange();
      }
      if (mounted) setState(() => _busy = false);
      return; // on casse d'abord, on marchera au prochain tap
    }

    // Case franchissable → s'y déplacer.
    if (!_walkable(t)) return;
    setState(() {
      _avatar = Point(t.x, t.y);
      _reveal(_avatar);
    });

    // Trésor → ramasser.
    if (t.kind == TileKind.treasure && !_cleared.contains(t.id)) {
      logic.state.expeditionCleared.add(t.id);
      logic.state.gold += t.gold;
      logic.state.goldLifetime += t.gold;
      logic.onChange();
      sync.advanceExpedition(nodeId: t.id); // persiste « ramassé »
      sync.applyGold(GoldLedgerEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        delta: t.gold,
        category: 'gain',
        reasonCode: 'expedition_bonus',
        label: 'Trésor d\'expédition',
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('💰 Trésor : +${t.gold} or'),
            duration: const Duration(seconds: 1)));
      }
      setState(() {});
    }

    // Arrivée → niveau débloqué.
    if (t.kind == TileKind.exit) await _finish();
  }

  String _kindLabel(TileKind k) => const {
        TileKind.rock: 'ce rocher',
        TileKind.gate: 'cette grille',
        TileKind.hole: 'ce trou',
      }[k] ??
      'cet obstacle';

  Future<void> _finish() async {
    final ok = await sync.completeExpedition(_level);
    if (ok) {
      logic.state.unlockedLevel = _level;
      logic.state.expeditionCleared.clear();
      logic.onChange();
    }
    if (!mounted) return;
    final lvl = logic.userLevelData();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Niveau ${lvl.level} débloqué ! 🏁'),
        content: Text('Tu as traversé la carte. Tu es désormais « ${lvl.title} ».'),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kGold),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Super')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final biome = expeditionBiome(_level);
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Row(children: [
            Text(biome.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Niveau $_level · ???',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Explore ${biome.label} jusqu\'au 🏁',
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
                ],
              ),
            ),
            goldAmount('${logic.state.gold}',
                fontSize: 15, weight: FontWeight.bold, color: _kGold),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
              'Touche une case voisine pour t\'y déplacer. Un obstacle (🪨/🔒/🕳️) se '
              'casse avec l\'outil correspondant — achète-le sur place si besoin.',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(.5))),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var y = 0; y < _map.rows; y++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var x = 0; x < _map.cols; x++)
                            _TileView(
                              tile: _map.at(x, y),
                              visible: _visible(x, y),
                              cleared: _cleared.contains(_map.at(x, y).id),
                              isAvatar: _avatar.x == x && _avatar.y == y,
                              reachable: (_map.at(x, y).x - _avatar.x).abs() +
                                      (_map.at(x, y).y - _avatar.y).abs() ==
                                  1,
                              cs: cs,
                              onTap: () => _onTapTile(_map.at(x, y)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TileView extends StatelessWidget {
  final _Tile tile;
  final bool visible, cleared, isAvatar, reachable;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _TileView({
    required this.tile,
    required this.visible,
    required this.cleared,
    required this.isAvatar,
    required this.reachable,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Container(
        width: _tile,
        height: _tile,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: cs.onSurface.withOpacity(.08),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    String content = '';
    Color bg = cs.surfaceContainerHighest.withOpacity(.4);

    switch (tile.kind) {
      case TileKind.wall:
        bg = cs.onSurface.withOpacity(.22);
        break;
      case TileKind.start:
        content = '🏳️';
        bg = Colors.green.withOpacity(.15);
        break;
      case TileKind.exit:
        content = '🏁';
        bg = _kGold.withOpacity(.18);
        break;
      case TileKind.treasure:
        content = cleared ? '' : '💰';
        bg = cleared
            ? cs.surfaceContainerHighest.withOpacity(.4)
            : _kGold.withOpacity(.12);
        break;
      case TileKind.rock:
        content = cleared ? '' : '🪨';
        break;
      case TileKind.gate:
        content = cleared ? '' : '🔒';
        break;
      case TileKind.hole:
        content = cleared ? '' : '🕳️';
        break;
      case TileKind.floor:
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _tile,
        height: _tile,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: reachable && tile.kind != TileKind.wall
              ? Border.all(color: _kGold, width: 2)
              : null,
        ),
        child: Text(isAvatar ? '🧍' : content,
            style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
