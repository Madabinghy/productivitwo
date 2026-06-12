import 'dart:math';

/// Expédition = la mini-carte sinueuse 2D qu'on traverse pour révéler/débloquer
/// le prochain niveau. PUR (aucune dépendance Flutter) : généré de façon
/// DÉTERMINISTE à partir du numéro de niveau (même niveau ⇒ même carte au reload),
/// re-skinné/rallongé selon le niveau. Pas de moteur de jeu : juste un graphe de
/// nœuds (row, lane) + des arêtes, dessiné côté widget.

enum ExpNodeType { start, step, rock, gate, hole, bonus, finish }

/// Outil (consommable boutique) requis pour franchir un nœud. null = gratuit
/// (départ, bonus, arrivée).
String? toolForType(ExpNodeType t) {
  switch (t) {
    case ExpNodeType.step:
      return 'pas';
    case ExpNodeType.rock:
      return 'pioche';
    case ExpNodeType.gate:
      return 'cle';
    case ExpNodeType.hole:
      return 'pelle';
    case ExpNodeType.start:
    case ExpNodeType.bonus:
    case ExpNodeType.finish:
      return null;
  }
}

class ExpeditionNode {
  final String id;
  final int row; // position verticale (0 = départ, en haut)
  final int lane; // colonne (0..lanes-1)
  final ExpNodeType type;
  final List<String> next; // ids des nœuds suivants (peut brancher)
  final int bonusGold; // or crédité en atteignant un nœud bonus
  ExpeditionNode({
    required this.id,
    required this.row,
    required this.lane,
    required this.type,
    required this.next,
    this.bonusGold = 0,
  });
}

class Expedition {
  final int level;
  final List<ExpeditionNode> nodes;
  final int lanes;
  final int rows;
  Expedition({
    required this.level,
    required this.nodes,
    required this.lanes,
    required this.rows,
  });

  ExpeditionNode get start => nodes.first;
  ExpeditionNode byId(String id) => nodes.firstWhere((n) => n.id == id);

  /// Nœuds atteignables = non franchis mais ayant un prédécesseur franchi.
  /// [cleared] inclut implicitement le départ.
  Set<String> reachable(Set<String> cleared) {
    final eff = {start.id, ...cleared};
    final out = <String>{};
    for (final n in nodes) {
      if (eff.contains(n.id)) continue;
      for (final src in nodes) {
        if (eff.contains(src.id) && src.next.contains(n.id)) {
          out.add(n.id);
          break;
        }
      }
    }
    return out;
  }

  bool isComplete(Set<String> cleared) =>
      cleared.contains(nodes.lastWhere((n) => n.type == ExpNodeType.finish).id);
}

/// Génère l'expédition d'un niveau (déterministe via seed = level).
/// Chaîne de segments : linéaires (1 nœud) ou forks (vrai choix de route :
/// route courte 1 obstacle cher ⟷ route longue 2 pas bon marché), puis arrivée.
/// Plus le niveau monte : plus de segments (traversée plus longue).
Expedition generateExpedition(int level) {
  final rng = Random(level * 1000003 + 7);
  const lanes = 3;
  const center = 1;
  final nodes = <ExpeditionNode>[];
  var row = 0;
  var idc = 0;
  String nid() => 'n${idc++}';

  final start = ExpeditionNode(
      id: nid(), row: row, lane: center, type: ExpNodeType.start, next: []);
  nodes.add(start);
  var prev = start;

  final segCount = (2 + level ~/ 2).clamp(2, 8);
  for (var s = 0; s < segCount; s++) {
    final fork = rng.nextBool();
    if (!fork) {
      row++;
      final n = ExpeditionNode(
          id: nid(), row: row, lane: center, type: ExpNodeType.step, next: []);
      prev.next.add(n.id);
      nodes.add(n);
      // Embranchement bonus optionnel (cul-de-sac récompense).
      if (rng.nextInt(3) == 0) {
        final b = ExpeditionNode(
            id: nid(),
            row: row,
            lane: rng.nextBool() ? 0 : 2,
            type: ExpNodeType.bonus,
            next: [],
            bonusGold: 5 + rng.nextInt(6));
        n.next.add(b.id);
        nodes.add(b);
      }
      prev = n;
    } else {
      final entry = prev;
      row++;
      final obs = [ExpNodeType.rock, ExpNodeType.gate, ExpNodeType.hole][
          rng.nextInt(3)];
      // Route courte (droite) : 1 obstacle.
      final a = ExpeditionNode(
          id: nid(), row: row, lane: 2, type: obs, next: []);
      // Route longue (gauche) : 2 pas.
      final b1 = ExpeditionNode(
          id: nid(), row: row, lane: 0, type: ExpNodeType.step, next: []);
      row++;
      final b2 = ExpeditionNode(
          id: nid(), row: row, lane: 0, type: ExpNodeType.step, next: []);
      final merge = ExpeditionNode(
          id: nid(), row: row, lane: center, type: ExpNodeType.step, next: []);
      entry.next.addAll([a.id, b1.id]);
      a.next.add(merge.id);
      b1.next.add(b2.id);
      b2.next.add(merge.id);
      nodes.addAll([a, b1, b2, merge]);
      prev = merge;
    }
  }

  row++;
  final finish = ExpeditionNode(
      id: nid(), row: row, lane: center, type: ExpNodeType.finish, next: []);
  prev.next.add(finish.id);
  nodes.add(finish);

  return Expedition(
      level: level, nodes: nodes, lanes: lanes, rows: row + 1);
}

/// Biome (skin) du niveau — purement cosmétique, varie selon le niveau.
({String emoji, String label}) expeditionBiome(int level) {
  const biomes = [
    (emoji: '🌲', label: 'Forêt'),
    (emoji: '🏜️', label: 'Désert'),
    (emoji: '🏔️', label: 'Montagne'),
    (emoji: '🌊', label: 'Côte'),
    (emoji: '🌋', label: 'Volcan'),
    (emoji: '❄️', label: 'Toundra'),
    (emoji: '🏝️', label: 'Île'),
    (emoji: '🕳️', label: 'Caverne'),
  ];
  return biomes[level % biomes.length];
}

// ════════════════════════════════════════════════════════════════════════════
// OVERWORLD (carte 2D explorable, Phase 1) — terrain + collectibles. Les entités
// (nuisibles/bonus) ne sont PAS générées ici : elles spawnent à la révélation.
// ════════════════════════════════════════════════════════════════════════════

enum OwTileKind { wall, floor, start, castle }

class OwTile {
  final int x, y;
  OwTileKind kind;
  String? collectibleId; // collectible posé sur la case (généré par seed)
  OwTile(this.x, this.y, this.kind, {this.collectibleId});
  String get id => '${x}_$y';
}

class Overworld {
  final int level, cols, rows;
  final List<List<OwTile>> grid;
  final Point<int> start, castle;
  Overworld(this.level, this.cols, this.rows, this.grid, this.start, this.castle);
  OwTile at(int x, int y) => grid[y][x];
  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  bool walkable(int x, int y) =>
      inBounds(x, y) && grid[y][x].kind != OwTileKind.wall;
  Iterable<OwTile> get all => grid.expand((r) => r);
  int get walkableCount => all.where((t) => t.kind != OwTileKind.wall).length;
}

/// Catalogue des collectibles (animaux communs + butins rares).
const overworldCollectibles = <({String id, String emoji, String name, bool rare})>[
  (id: 'fox', emoji: '🦊', name: 'Renard', rare: false),
  (id: 'deer', emoji: '🦌', name: 'Cerf', rare: false),
  (id: 'rabbit', emoji: '🐰', name: 'Lapin', rare: false),
  (id: 'owl', emoji: '🦉', name: 'Hibou', rare: false),
  (id: 'hedgehog', emoji: '🦔', name: 'Hérisson', rare: false),
  (id: 'boar', emoji: '🐗', name: 'Sanglier', rare: false),
  (id: 'gem', emoji: '💎', name: 'Gemme', rare: true),
  (id: 'amphora', emoji: '🏺', name: 'Amphore', rare: true),
  (id: 'crown', emoji: '👑', name: 'Couronne', rare: true),
  (id: 'ring', emoji: '💍', name: 'Anneau', rare: true),
  (id: 'wpn_arc', emoji: '🏹', name: 'Arc (pickup)', rare: false),
  (id: 'wpn_couteau', emoji: '🔪', name: 'Couteau (pickup)', rare: false),
  (id: 'wpn_epee', emoji: '🗡️', name: 'Épée (pickup)', rare: false),
];

({String id, String emoji, String name, bool rare})? collectibleById(String id) {
  for (final c in overworldCollectibles) {
    if (c.id == id) return c;
  }
  return null;
}

/// Marque une case en floor (sauf si déjà start/castle).
void _floor(List<List<OwTile>> grid, int x, int y, int cols, int rows) {
  if (x < 0 || x >= cols || y < 0 || y >= rows) return;
  if (grid[y][x].kind == OwTileKind.wall) grid[y][x].kind = OwTileKind.floor;
}

/// Carve une route start(top,startX) → castle(bottom,castleX), biaisée vers
/// [laneBias] (deux valeurs différentes ⇒ deux routes distinctes).
List<Point<int>> _carve(List<List<OwTile>> grid, Random rng, int cols, int rows,
    int startX, int castleX, int laneBias) {
  final path = <Point<int>>[];
  var x = startX, y = 0;
  _floor(grid, x, y, cols, rows);
  path.add(Point(x, y));
  while (y < rows - 1) {
    if (rng.nextInt(100) < 55) {
      y++;
    } else if (x < laneBias && x < cols - 1) {
      x++;
    } else if (x > laneBias && x > 0) {
      x--;
    } else {
      y++;
    }
    _floor(grid, x, y, cols, rows);
    path.add(Point(x, y));
  }
  while (x != castleX) {
    x += x < castleX ? 1 : -1;
    _floor(grid, x, y, cols, rows);
    path.add(Point(x, y));
  }
  return path;
}

Overworld generateOverworld(int level) {
  final rng = Random(level * 100003 + 41);
  const cols = 7;
  final rows = (8 + level).clamp(8, 16);
  final grid = [
    for (int y = 0; y < rows; y++)
      [for (int x = 0; x < cols; x++) OwTile(x, y, OwTileKind.wall)]
  ];
  const startX = 3, castleX = 3;
  final pathA = _carve(grid, rng, cols, rows, startX, castleX, 1); // biais gauche
  _carve(grid, rng, cols, rows, startX, castleX, 5); // biais droite (2e route)
  grid[0][startX].kind = OwTileKind.start;
  grid[rows - 1][castleX].kind = OwTileKind.castle;

  // Collectibles : sur des cases floor HORS route A (récompense l'exploration).
  final pathAset = pathA.map((p) => '${p.x}_${p.y}').toSet();
  final offPath = grid
      .expand((r) => r)
      .where((t) => t.kind == OwTileKind.floor && !pathAset.contains(t.id))
      .toList()
    ..shuffle(rng);
  final commons = overworldCollectibles.where((c) => !c.rare).toList();
  final rares = overworldCollectibles.where((c) => c.rare).toList();
  final weapons =
      overworldCollectibles.where((c) => c.id.startsWith('wpn_')).toList();
  final count = (2 + level ~/ 3).clamp(2, 6);
  for (var i = 0; i < count && i < offPath.length; i++) {
    // i==0 : arme garantie (les flèches/couteaux/épées doivent réapparaître) ;
    // sinon rare 1/4, commun sinon (les communs incluent aussi des armes).
    final cat = i == 0
        ? weapons[rng.nextInt(weapons.length)]
        : (rng.nextInt(4) == 0
            ? rares[rng.nextInt(rares.length)]
            : commons[rng.nextInt(commons.length)]);
    offPath[i].collectibleId = cat.id;
  }
  return Overworld(level, cols, rows, grid, const Point(startX, 0),
      Point(castleX, rows - 1));
}

// ── Entités vivantes (nuisibles/bonus) encodées "type:tile:meta" ────────────
// pest  : "spider|scorpion|snake:x_y:spawnYmd"
// bonus : "bonus:x_y:amount"
({String type, String tile, String meta}) decodeEntity(String e) {
  final p = e.split(':');
  return (type: p[0], tile: p.length > 1 ? p[1] : '', meta: p.length > 2 ? p[2] : '');
}

String encodeEntity(String type, String tile, String meta) => '$type:$tile:$meta';

// Le meta d'un nuisible encode le jour de spawn ET un baseline de forge
// (combien de routines/actions étaient déjà faites à la rencontre), séparés par
// '~'. Formats : pest "spawnYmd~baseline" · gardien "guardian~spawnYmd~baseline".
// Rétro-compatible : un ancien meta "spawnYmd" ou "guardian" donne baseline 0.
bool isGuardianMeta(String meta) => meta.startsWith('guardian');

// Ennemi « vrai backlog » : meta = "ref~<itemId>" (l'itemId est une routine, une
// activité-temps ou une tâche, selon le type d'ennemi). PV calculés en direct.
bool isBacklogMeta(String meta) => meta.startsWith('ref~');
String backlogItemId(String meta) =>
    meta.startsWith('ref~') ? meta.substring(4) : '';

/// Baseline de forge effectif d'une entité pour [todayYmd] : le nombre de
/// routines/actions à NE PAS compter (déjà faites au spawn). Vaut 0 si l'entité
/// a spawné un autre jour (chaque jour repart de zéro).
int forgeBaselineFromMeta(String meta, String todayYmd) {
  final parts = meta.split('~');
  // pest : [ymd, base] · gardien : [guardian, ymd, base]
  final offset = isGuardianMeta(meta) ? 1 : 0;
  final spawnYmd = parts.length > offset ? parts[offset] : '';
  if (spawnYmd != todayYmd) return 0;
  final raw = parts.length > offset + 1 ? parts[offset + 1] : '';
  return int.tryParse(raw) ?? 0;
}

bool isPestType(String t) => t == 'spider' || t == 'scorpion' || t == 'snake';

String entityEmoji(String t) =>
    const {'spider': '🕷️', 'scorpion': '🦂', 'snake': '🐍', 'bonus': '💰'}[t] ?? '❓';

String pestName(String t) =>
    const {'spider': 'Araignée', 'scorpion': 'Scorpion', 'snake': 'Serpent'}[t] ?? t;
